#!/usr/bin/env bash
# derive-change-rollback.sh — shared rollback derivation for yci workflows.
#
# Reads a normalized-change JSON envelope on stdin and emits a rollback plan to
# stdout (or --output <path>). Consumers currently include:
#   - yci:network-change-review
#   - yci:mop
#
# Supported diff_kind values:
#   unified-diff     → reverse the diff mechanically
#   structured-yaml  → emit the explicit reverse: block
#   playbook         → manual-derivation stub
#   terraform-plan   → derive Terraform rollback workflow commands
#   vendor-cli       → derive vendor-specific inverse commands (iosxe, panos)
#
# Input contract (stdin):
#   JSON object with at least:
#     {
#       "diff_kind": "...",
#       "raw": "...",
#       "summary": "...",
#       "targets": [...],
#       "metadata": {...}   # optional
#     }
#
# Output contract (stdout):
#   Plain-text rollback plan intended to be embedded verbatim in a customer
#   deliverable.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: derive-change-rollback.sh [--output <path>] < normalized-change.json

Reads a normalized-change JSON envelope on stdin and writes a rollback plan to
stdout (default) or to the path specified by --output.

Options:
  --output <path>   Write rollback plan to <path> instead of stdout
  -h, --help        Show this help and exit

Exit codes:
  0  success (rollback plan emitted; may include MANUAL DERIVATION REQUIRED)
  3  input shape error (see stderr for structured error ID)
EOF
}

OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
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

err() {
  local id="$1"
  local msg="$2"
  local code="$3"
  printf '[%s] %s\n' "$id" "$msg" >&2
  exit "$code"
}

if [[ -t 0 ]]; then
  usage
  err "ncr-diff-unsupported-shape" "No stdin provided. Pipe a normalized-change JSON envelope." 3
fi

_NCR_STDIN="$(cat)"
if [[ -z "$_NCR_STDIN" ]]; then
  err "ncr-diff-unsupported-shape" "Empty stdin. Expected a normalized-change JSON envelope." 3
fi
export _NCR_STDIN

read_stdin_json() {
  local key="$1"
  python3 - "$key" <<'PYEOF'
import json
import os
import sys

try:
    data = json.loads(os.environ["_NCR_STDIN"])
except json.JSONDecodeError as exc:
    sys.stderr.write(f"[ncr-diff-unsupported-shape] Invalid JSON envelope: {exc}\n")
    print("")
    sys.exit(3)
except Exception as exc:
    sys.stderr.write(f"[ncr-diff-unsupported-shape] Failed to read JSON envelope: {exc}\n")
    print("")
    sys.exit(3)

val = data.get(sys.argv[1], "")
if isinstance(val, (dict, list)):
    print(json.dumps(val))
else:
    print(val)
PYEOF
}

reverse_unified_diff() {
  local raw
  raw="$(read_stdin_json raw)"
  NCR_RAW_DIFF="$raw" python3 <<'PYEOF'
import os
import re
import sys

raw = os.environ.get("NCR_RAW_DIFF", "")

lines = raw.splitlines(keepends=True)
fixed = []
for ln in lines:
    fixed.append(ln if ln.endswith("\n") else ln + "\n")
lines = fixed

file_diffs = []
i = 0
while i < len(lines):
    preamble = []
    while i < len(lines) and not lines[i].startswith("--- "):
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

    old_hdr = lines[i]
    i += 1
    if i >= len(lines) or not lines[i].startswith("+++ "):
        sys.stderr.write(
            f"[ncr-diff-unsupported-shape] Malformed unified diff: "
            f"expected '+++ ' after '--- ' at line {i}.\n"
        )
        sys.exit(3)
    new_hdr = lines[i]
    i += 1

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
        while i < len(lines) and not lines[i].startswith("@@") and not lines[i].startswith("--- "):
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

out = []
reverse_hunks_flag = os.environ.get("YCI_ROLLBACK_REVERSE_HUNKS") == "1"

for preamble, old_hdr, new_hdr, hunks in file_diffs:
    out.extend(preamble)

    old_path_m = re.match(r"^--- (.*)", old_hdr.rstrip("\n"))
    new_path_m = re.match(r"^\+\+\+ (.*)", new_hdr.rstrip("\n"))
    old_path = old_path_m.group(1)
    new_path = new_path_m.group(1)

    out.append(f"--- {new_path}\n")
    out.append(f"+++ {old_path}\n")

    iter_hunks = list(reversed(hunks)) if reverse_hunks_flag else hunks
    for hunk_hdr, hunk_body in iter_hunks:
        m = re.match(
            r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$",
            hunk_hdr.rstrip("\n"),
        )
        if not m:
            sys.stderr.write(
                f"[ncr-diff-unsupported-shape] Malformed hunk header: {hunk_hdr!r}\n"
            )
            sys.exit(3)

        old_start = int(m.group(1))
        old_count = int(m.group(2)) if m.group(2) is not None else 1
        new_start = int(m.group(3))
        new_count = int(m.group(4)) if m.group(4) is not None else 1
        trailing = m.group(5) or ""

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
                flipped.append(line)

        new_old_count = sum(1 for ln in flipped if ln and (ln[0] == " " or ln[0] == "-"))
        new_new_count = sum(1 for ln in flipped if ln and (ln[0] == " " or ln[0] == "+"))

        rev_hdr = (
            f"@@ -{new_start},{new_old_count} +{old_start},{new_new_count}"
            f" @@{trailing}\n"
        )
        out.append(rev_hdr)
        out.extend(flipped)

sys.stdout.write("".join(out))
PYEOF
}

reverse_structured_yaml() {
  python3 - <<'PYEOF'
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
PYEOF
}

reverse_terraform_plan() {
  python3 - <<'PYEOF'
import json
import os
import sys

try:
    data = json.loads(os.environ["_NCR_STDIN"])
except Exception as exc:
    sys.stderr.write(f"[ncr-diff-unsupported-shape] Invalid JSON envelope: {exc}\n")
    sys.exit(3)

raw = data.get("raw", "")
try:
    plan = json.loads(raw)
except Exception as exc:
    sys.stderr.write(f"[ncr-diff-unsupported-shape] Terraform rollback expects raw plan JSON: {exc}\n")
    sys.exit(3)

resource_changes = plan.get("resource_changes") or []
lines = [
    "# ROLLBACK PLAN — TERRAFORM",
    "",
    "1. Confirm the pre-change state snapshot exists:",
    "   terraform state pull > pre-change-tfstate",
    "",
    "2. Preferred rollback path for this workflow:",
    "   Restore the pre-change state snapshot using your backend's versioning or recovery mechanism.",
    "   Revert configuration to a known-good revision or saved plan, then re-run plan/apply from that state.",
    "   terraform plan -refresh-only",
    "",
    "   `terraform state push` is only for manual state recovery or migration and should be used with extreme caution.",
    "",
]

if resource_changes:
    lines.extend([
        "3. Resource-specific fast paths from the reviewed plan:",
        "",
    ])
    for rc in resource_changes:
        address = rc.get("address", "unknown")
        change = rc.get("change") or {}
        actions = change.get("actions") or []
        before = change.get("before") or {}
        action_label = ",".join(actions) if actions else "unknown"
        lines.append(f"- `{address}` ({action_label})")
        if actions == ["create"]:
            lines.append(f"  - `terraform destroy -target '{address}'`")
        elif actions == ["delete"]:
            before_id = before.get("id")
            if before_id:
                lines.append(f"  - `terraform import '{address}' '{before_id}'`")
            else:
                lines.append("  - Manual restore required: deleted resource has no prior id in the plan JSON.")
        elif "update" in actions or ("delete" in actions and "create" in actions):
            lines.append("  - Use the state snapshot rollback path above; resource updates are restored from pre-change state.")
        else:
            lines.append("  - Manual review required for this action set.")
    lines.extend(["", "4. Re-run the reviewed validation commands before closing the change window."])
else:
    lines.append("3. No resource_changes were present in the plan JSON. Re-run the reviewed validation commands before closing the change window.")

print("\n".join(lines))
PYEOF
}

reverse_vendor_cli() {
  python3 - <<'PYEOF'
import json
import os
import sys

try:
    data = json.loads(os.environ["_NCR_STDIN"])
except Exception as exc:
    sys.stderr.write(f"[ncr-diff-unsupported-shape] Invalid JSON envelope: {exc}\n")
    sys.exit(3)

raw = data.get("raw", "")
metadata = data.get("metadata") or {}
vendor = (metadata.get("vendor") or "").strip().lower()

def iosxe_inverse(text: str):
    safe_negatable_exact = {
        "shutdown",
        "logging event link-status",
        "spanning-tree portfast",
        "spanning-tree bpduguard enable",
        "switchport",
        "ip redirects",
        "ipv6 redirects",
    }
    safe_negatable_prefixes = (
        "service-policy input ",
        "service-policy output ",
        "ip access-group ",
        "ipv6 traffic-filter ",
    )

    def is_safe_negatable(cmd: str) -> bool:
        return cmd in safe_negatable_exact or cmd.startswith(safe_negatable_prefixes)

    def manual_inverse(indent: str, cmd: str) -> str:
        return indent + f"! MANUAL-ROLLBACK-REQUIRED: restore the prior value for `{cmd}`"

    out = []
    manual_required = False
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            out.append("")
            continue
        if stripped == "!":
            out.append("!")
            continue
        indent = line[: len(line) - len(line.lstrip())]
        cmd = line.lstrip()
        if cmd.startswith(("interface ", "router ", "vlan ", "line ", "policy-map ", "class-map ")):
            out.append(indent + cmd)
        elif cmd in {"exit", "end"}:
            out.append(indent + cmd)
        elif cmd.startswith("no "):
            positive_cmd = cmd[3:].strip()
            if is_safe_negatable(positive_cmd):
                out.append(indent + positive_cmd)
            else:
                manual_required = True
                out.append(manual_inverse(indent, positive_cmd))
        elif is_safe_negatable(cmd):
            out.append(indent + "no " + cmd)
        else:
            manual_required = True
            out.append(manual_inverse(indent, cmd))
    return "\n".join(out), manual_required

def panos_inverse(text: str) -> str:
    out = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            out.append("")
            continue
        if stripped.startswith("set "):
            out.append(line.replace("set ", "delete ", 1))
        elif stripped.startswith("delete "):
            out.append(line.replace("delete ", "set ", 1))
        else:
            out.append(line)
    return "\n".join(out)

if vendor == "iosxe":
    rendered, manual_required = iosxe_inverse(raw)
    if manual_required:
        sys.stderr.write(
            "[ncr-rollback-ambiguous] Rollback confidence: low. IOS XE payload "
            "contains non-invertible setters; restore the prior values for the "
            "marked commands.\n"
        )
    print(rendered)
elif vendor == "panos":
    print(panos_inverse(raw))
else:
    sys.stderr.write("[ncr-rollback-ambiguous] Rollback confidence: low. Unsupported vendor-cli subtype.\n")
    print(
        "# ROLLBACK PLAN — MANUAL DERIVATION REQUIRED\n\n"
        "No vendor-specific inverse was implemented for this CLI payload.\n\n"
        f"Detected vendor: {vendor or 'unknown'}"
    )
PYEOF
}

emit_manual_derivation_stub() {
  local shape_name="$1"
  printf '[ncr-rollback-ambiguous] Rollback confidence: low. Manual derivation required.\n' >&2
  cat <<EOF
# ROLLBACK PLAN — MANUAL DERIVATION REQUIRED

No mechanical inverse is available for this change shape. The operator must
supply or derive the rollback steps manually before proceeding.

Confidence: low
Detected shape: ${shape_name}
EOF
}

dispatch_rollback() {
  local diff_kind="$1"
  case "$diff_kind" in
    unified-diff)    reverse_unified_diff ;;
    structured-yaml) reverse_structured_yaml ;;
    playbook)        emit_manual_derivation_stub "playbook" ;;
    terraform-plan)  reverse_terraform_plan ;;
    vendor-cli)      reverse_vendor_cli ;;
    unknown)         err "ncr-diff-unsupported-shape" "Cannot derive rollback for unknown diff shape." 3 ;;
    *)               err "ncr-diff-unsupported-shape" "Unhandled diff_kind: $diff_kind" 3 ;;
  esac
}

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
