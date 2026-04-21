#!/usr/bin/env bash
# derive-rollback.sh — yci:network-change-review rollback derivation
#
# Purpose:
#   Read a normalized-change JSON envelope on stdin and emit a rollback plan
#   to stdout (or --output <path>). Dispatches by diff_kind:
#     unified-diff     → reverse_unified_diff (TODO 3.2 — currently echoes raw verbatim)
#     structured-yaml  → emit the explicit reverse: block (fully implemented)
#     playbook         → emit MANUAL DERIVATION REQUIRED stub (fully implemented)
#     unknown/*        → error ncr-diff-unsupported-shape, exit 3
#
# Input contract (stdin):
#   JSON object: {"diff_kind":"...","raw":"...","summary":"...","targets":[...]}
#
# Output contract (stdout):
#   Plain text rollback plan. For unified-diff / structured-yaml: the derived
#   plan body. For playbook: the MANUAL DERIVATION REQUIRED stub block.
#   Not JSON — intended to be embedded verbatim in the rendered artifact.
#
# Error IDs (stderr, format: [ncr-<id>] <message>):
#   ncr-diff-unsupported-shape   — unrecognised or unknown diff_kind (exit 3)
#   ncr-rollback-missing-reverse — structured-yaml has forward: but no reverse: (exit 3)
#   ncr-rollback-binary-unsupported — binary diff cannot be mechanically reversed (exit 3)
#   ncr-rollback-ambiguous       — low-confidence stub emitted (exit 0, warning only)
#
# Spec: yci/skills/network-change-review/references/rollback-derivation.md

set -euo pipefail

# ---------------------------------------------------------------------------
# usage
# ---------------------------------------------------------------------------
usage() {
  cat >&2 <<'EOF'
Usage: derive-rollback.sh [--output <path>] < normalized-change.json

Reads a normalized-change JSON envelope on stdin and writes a rollback plan
to stdout (default) or to the path specified by --output.

Options:
  --output <path>   Write rollback plan to <path> instead of stdout
  -h, --help        Show this help and exit

Exit codes:
  0  success (rollback plan emitted; may include MANUAL DERIVATION stub)
  3  input shape error (see stderr for ncr-* error ID)
EOF
}

# ---------------------------------------------------------------------------
# flag parsing
# ---------------------------------------------------------------------------
OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      if [[ $# -lt 2 || -z "$2" ]]; then
        printf '[ncr-diff-unsupported-shape] --output requires a path argument\n' >&2
        exit 3
      fi
      OUTPUT_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[ncr-diff-unsupported-shape] Unknown option: %s\n' "$1" >&2
      usage
      exit 3
      ;;
  esac
done

# ---------------------------------------------------------------------------
# err helper — mirrors parse-change.sh convention
# Usage: err <ncr-id> <message> <exit-code>
# ---------------------------------------------------------------------------
err() {
  local id="$1"
  local msg="$2"
  local code="$3"
  printf '[%s] %s\n' "$id" "$msg" >&2
  exit "$code"
}

# ---------------------------------------------------------------------------
# stdin capture
# ---------------------------------------------------------------------------
if [[ -t 0 ]]; then
  usage
  err "ncr-diff-unsupported-shape" "No stdin provided. Pipe a normalized-change JSON envelope." 3
fi

_NCR_STDIN="$(cat)"
if [[ -z "$_NCR_STDIN" ]]; then
  err "ncr-diff-unsupported-shape" "Empty stdin. Expected a normalized-change JSON envelope." 3
fi
export _NCR_STDIN

# ---------------------------------------------------------------------------
# read_stdin_json — extract a single top-level key from the captured JSON
# Usage: read_stdin_json <key>  → prints the value (string repr)
# ---------------------------------------------------------------------------
read_stdin_json() {
  local key="$1"
  python3 -c "
import json, sys, os
data = json.loads(os.environ['_NCR_STDIN'])
val = data.get('${key}', '')
if isinstance(val, (dict, list)):
    print(json.dumps(val))
else:
    print(val)
"
}

# ---------------------------------------------------------------------------
# reverse_unified_diff — §3 of references/rollback-derivation.md
#
# Parses a unified diff from stdin JSON ("raw" field), reverses it, and
# emits the reversed diff to stdout.  All parsing and reversal is done in
# Python (inline heredoc) to avoid shell quoting hazards.  The raw diff is
# passed via the NCR_RAW_DIFF env var.
#
# Binary diffs are detected and cause an immediate fatal error
# (ncr-rollback-binary-unsupported, exit 3).
#
# Hunk-order reversal within each file diff is controlled by:
#   YCI_ROLLBACK_REVERSE_HUNKS=1   (default off — preserve original order)
# ---------------------------------------------------------------------------
reverse_unified_diff() {
  local raw
  raw="$(read_stdin_json raw)"
  NCR_RAW_DIFF="$raw" python3 <<'PYEOF'
import os
import re
import sys

raw = os.environ.get("NCR_RAW_DIFF", "")

# -----------------------------------------------------------------------
# Parse the unified diff into a list of file-diff records.
# Each record is a 4-tuple:
#   (preamble_lines, old_hdr_line, new_hdr_line, hunks)
# where hunks is a list of (hunk_header_line, hunk_body_lines).
# Lines retain their trailing newlines.
# -----------------------------------------------------------------------
lines = raw.splitlines(keepends=True)
# Ensure every line ends with \n so we can safely join later
fixed = []
for ln in lines:
    fixed.append(ln if ln.endswith("\n") else ln + "\n")
lines = fixed

file_diffs = []
i = 0
while i < len(lines):
    preamble = []
    # Consume any non-'--- ' lines as preamble (diff --git, Index:, etc.)
    while i < len(lines) and not lines[i].startswith("--- "):
        # Detect binary diff line early — reject immediately
        if re.match(r"^Binary files ", lines[i]):
            sys.stderr.write(
                "[ncr-rollback-binary-unsupported] Binary diffs are not "
                "auto-reversible.\n"
            )
            sys.exit(3)
        preamble.append(lines[i])
        i += 1
    if i >= len(lines):
        break

    old_hdr = lines[i]  # --- a/X  (or --- /dev/null)
    i += 1

    if i >= len(lines) or not lines[i].startswith("+++ "):
        sys.stderr.write(
            f"[ncr-diff-unsupported-shape] Malformed unified diff: "
            f"expected '+++ ' after '--- ' at line {i}.\n"
        )
        sys.exit(3)

    new_hdr = lines[i]  # +++ b/X  (or +++ /dev/null)
    i += 1

    # Detect binary marker between headers and hunks
    if i < len(lines) and re.match(r"^Binary files ", lines[i]):
        sys.stderr.write(
            "[ncr-rollback-binary-unsupported] Binary diffs are not "
            "auto-reversible.\n"
        )
        sys.exit(3)

    hunks = []
    while i < len(lines) and lines[i].startswith("@@"):
        hunk_hdr = lines[i]
        i += 1
        hunk_body = []
        # Collect body lines until next hunk header, next file header, or EOF
        while (
            i < len(lines)
            and not lines[i].startswith("@@")
            and not lines[i].startswith("--- ")
        ):
            # Binary marker inside hunk body is also fatal
            if re.match(r"^Binary files ", lines[i]):
                sys.stderr.write(
                    "[ncr-rollback-binary-unsupported] Binary diffs are not "
                    "auto-reversible.\n"
                )
                sys.exit(3)
            hunk_body.append(lines[i])
            i += 1
        hunks.append((hunk_hdr, hunk_body))

    if not hunks:
        sys.stderr.write(
            "[ncr-diff-unsupported-shape] Unified diff file section has no @@ hunks "
            "(header-only or empty diff).\n"
        )
        sys.exit(3)

    file_diffs.append((preamble, old_hdr, new_hdr, hunks))

# -----------------------------------------------------------------------
# Reverse each file diff.
# -----------------------------------------------------------------------
out = []
reverse_hunks_flag = os.environ.get("YCI_ROLLBACK_REVERSE_HUNKS") == "1"

for preamble, old_hdr, new_hdr, hunks in file_diffs:
    # Emit preamble verbatim (diff --git lines, Index: lines, etc.)
    out.extend(preamble)

    # Swap --- / +++ paths.
    # old_hdr: "--- <old_path>\n"   new_hdr: "+++ <new_path>\n"
    old_path_m = re.match(r"^--- (.*)", old_hdr.rstrip("\n"))
    new_path_m = re.match(r"^\+\+\+ (.*)", new_hdr.rstrip("\n"))
    old_path = old_path_m.group(1)
    new_path = new_path_m.group(1)

    # Emit swapped headers: --- <was-new-path>  /  +++ <was-old-path>
    out.append(f"--- {new_path}\n")
    out.append(f"+++ {old_path}\n")

    iter_hunks = list(reversed(hunks)) if reverse_hunks_flag else hunks
    for hunk_hdr, hunk_body in iter_hunks:
        # Parse @@ -old_start[,old_count] +new_start[,new_count] @@ [trailing]
        m = re.match(
            r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$",
            hunk_hdr.rstrip("\n"),
        )
        if not m:
            sys.stderr.write(
                f"[ncr-diff-unsupported-shape] Malformed hunk header: "
                f"{hunk_hdr!r}\n"
            )
            sys.exit(3)

        old_start = int(m.group(1))
        # old_count defaults to 1 when the ,N suffix is absent
        old_count = int(m.group(2)) if m.group(2) is not None else 1
        new_start = int(m.group(3))
        new_count = int(m.group(4)) if m.group(4) is not None else 1
        trailing = m.group(5) or ""

        # Flip body: + → -, - → +, context unchanged
        flipped = []
        for line in hunk_body:
            if not line:
                flipped.append(line)
                continue
            c = line[0]
            if c == "+":
                flipped.append("-" + line[1:])
            elif c == "-":
                flipped.append("+" + line[1:])
            else:
                # Space (context) or any unexpected prefix — preserve verbatim
                flipped.append(line)

        # Recount from flipped body.
        # After flipping:
        #   flipped '-' lines are what will be removed in the rollback (old side)
        #   flipped '+' lines are what will be added   in the rollback (new side)
        #   space lines are context (count toward both sides)
        new_old_count = sum(
            1 for ln in flipped if ln and (ln[0] == " " or ln[0] == "-")
        )
        new_new_count = sum(
            1 for ln in flipped if ln and (ln[0] == " " or ln[0] == "+")
        )

        # Swap positions: the rollback hunk's old-side starts where the
        # forward hunk's new-side started, and vice-versa.
        rev_hdr = (
            f"@@ -{new_start},{new_old_count} +{old_start},{new_new_count}"
            f" @@{trailing}\n"
        )
        out.append(rev_hdr)
        out.extend(flipped)

sys.stdout.write("".join(out))
PYEOF
}

# ---------------------------------------------------------------------------
# reverse_structured_yaml — emit the explicit reverse: block verbatim
# Errors with ncr-rollback-missing-reverse if reverse: key is absent.
# ---------------------------------------------------------------------------
reverse_structured_yaml() {
  # Read `raw` from the captured JSON envelope in _NCR_STDIN — never interpolate YAML
  # into the heredoc (triple quotes in the payload could break out or inject code).
  python3 - <<'PY'
import json
import os
import sys

try:
    import yaml
except ImportError:
    yaml = None

try:
    data = json.loads(os.environ["_NCR_STDIN"])
except Exception as exc:
    sys.stderr.write(f"[ncr-diff-unsupported-shape] Invalid JSON envelope: {exc}\n")
    sys.exit(3)

raw = data.get("raw", "")
if not isinstance(raw, str):
    raw = ""

if yaml is None:
    has_reverse = "reverse:" in raw
    if not has_reverse:
        sys.stderr.write("[ncr-rollback-missing-reverse] Structured change lacks required 'reverse:' block.\n")
        sys.exit(3)
    lines = raw.splitlines()
    in_reverse = False
    out = []
    for line in lines:
        if line.strip() == "reverse:" or line.startswith("reverse:"):
            in_reverse = True
            continue
        if in_reverse:
            if line and not line[0].isspace() and line[0] != "-":
                break
            out.append(line)
    body = "\n".join(out)
    if body.strip():
        print("reverse:\n" + body)
    else:
        print("reverse:")
    sys.exit(0)

try:
    ydata = yaml.safe_load(raw)
except Exception as exc:
    sys.stderr.write(f"[ncr-diff-unsupported-shape] Failed to parse structured YAML: {exc}\n")
    sys.exit(3)

if not isinstance(ydata, dict):
    sys.stderr.write("[ncr-diff-unsupported-shape] Structured YAML must be a mapping at top level.\n")
    sys.exit(3)

if "reverse" not in ydata:
    sys.stderr.write("[ncr-rollback-missing-reverse] Structured change lacks required 'reverse:' block.\n")
    sys.exit(3)

print(yaml.dump({"reverse": ydata["reverse"]}, default_flow_style=False).rstrip())
PY
}

# ---------------------------------------------------------------------------
# emit_manual_derivation_stub — §5 of rollback-derivation.md
# Fully implemented: prints the MANUAL DERIVATION REQUIRED block and exits 0.
# ---------------------------------------------------------------------------
emit_manual_derivation_stub() {
  local shape_name="$1"
  # ncr-rollback-ambiguous is exit-0 per error-messages.md (warning, not fatal)
  printf '[ncr-rollback-ambiguous] Rollback confidence: low. Manual derivation required.\n' >&2
  cat <<EOF
# ROLLBACK PLAN — MANUAL DERIVATION REQUIRED

No mechanical inverse is available for this change shape. The operator must
supply or derive the rollback steps manually before proceeding.

Confidence: low
Detected shape: ${shape_name}
EOF
}

# ---------------------------------------------------------------------------
# dispatch_rollback — route by diff_kind
# ---------------------------------------------------------------------------
dispatch_rollback() {
  local diff_kind="$1"
  case "$diff_kind" in
    unified-diff)    reverse_unified_diff ;;
    structured-yaml) reverse_structured_yaml ;;
    playbook)        emit_manual_derivation_stub "playbook" ;;
    unknown)         err "ncr-diff-unsupported-shape" "Cannot derive rollback for unknown diff shape." 3 ;;
    *)               err "ncr-diff-unsupported-shape" "Unhandled diff_kind: $diff_kind" 3 ;;
  esac
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  local diff_kind
  diff_kind="$(read_stdin_json diff_kind)"

  if [[ -z "$diff_kind" ]]; then
    err "ncr-diff-unsupported-shape" "Input JSON missing required 'diff_kind' field." 3
  fi

  if [[ -n "$OUTPUT_PATH" ]]; then
    dispatch_rollback "$diff_kind" > "$OUTPUT_PATH"
  else
    dispatch_rollback "$diff_kind"
  fi
}

main
