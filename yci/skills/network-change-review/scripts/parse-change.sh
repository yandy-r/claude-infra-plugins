#!/usr/bin/env bash
set -euo pipefail
# yci — parse-change.sh: detect diff shape, normalize to canonical JSON envelope.
#
# Usage:  parse-change.sh --input <path> [--output <path>] [-h|--help]
# Flags:
#   --input  <path>   (required) path to the change file to parse
#   --output <path>   (optional) write normalized JSON to this path; defaults to stdout
#   -h, --help        print this help and exit 0
#
# Stdout: JSON object — {diff_kind, raw, summary, targets[]} per change-input-schema.md
# Stderr: [ncr-<id>] <message> on any error
# Error IDs: ncr-diff-unsupported-shape (exit 3), ncr-targets-unresolvable (exit 3)
# See: ${CLAUDE_PLUGIN_ROOT}/skills/network-change-review/references/change-input-schema.md

usage() {
  cat <<EOF
Usage: parse-change.sh --input <path> [--output <path>] [-h|--help]

  --input  <path>   path to the change file (unified-diff, structured-yaml, or playbook)
  --output <path>   write normalized JSON to this path instead of stdout
  -h, --help        show this help and exit 0

Exit codes:
  0  success
  3  input shape error (ncr-diff-unsupported-shape, ncr-targets-unresolvable)
EOF
}

err() {
  # $1=ncr-* ID  $2=message  $3=exit code
  echo "[${1}] ${2}" >&2
  exit "${3}"
}

# --- flag parsing ------------------------------------------------------------

input_path=""
output_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      if [[ -z "${2:-}" ]]; then
        usage >&2
        err "ncr-diff-unsupported-shape" "Missing value for --input" 3
      fi
      input_path="$2"
      shift 2
      ;;
    --output)
      if [[ -z "${2:-}" ]]; then
        usage >&2
        err "ncr-diff-unsupported-shape" "Missing value for --output" 3
      fi
      output_path="$2"
      shift 2
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      usage >&2
      err "ncr-diff-unsupported-shape" "Unknown flag: $1" 3
      ;;
  esac
done

# --- validation guards -------------------------------------------------------

[[ -n "$input_path" ]] \
  || err "ncr-diff-unsupported-shape" "--input is required" 3
[[ -e "$input_path" ]] \
  || err "ncr-diff-unsupported-shape" "Input file not found: ${input_path}" 3
[[ -r "$input_path" ]] \
  || err "ncr-diff-unsupported-shape" "Input file is not readable: ${input_path}" 3

# --- detect_diff_kind --------------------------------------------------------
# Detection order (per change-input-schema.md):
#   1. unified-diff  — magic lines ^--- a/ AND ^+++ b/ (extension-agnostic)
#   2. structured-yaml — .yaml/.yml with top-level 'forward:' key (YAML parse)
#   3. playbook      — .yaml/.yml without 'forward:'
#   4. unknown       — no match

detect_diff_kind() {
  local path="$1"
  local ext="${path##*.}"

  if grep -qP '^--- a/' "$path" 2>/dev/null && grep -qP '^\+\+\+ b/' "$path" 2>/dev/null; then
    echo "unified-diff"; return
  fi

  if [[ "$ext" == "yaml" || "$ext" == "yml" ]]; then
    if python3 -c "
import yaml, sys
try:
    d = yaml.safe_load(open(sys.argv[1]))
    sys.exit(0 if isinstance(d, dict) and 'forward' in d else 1)
except Exception:
    sys.exit(1)
" "$path" 2>/dev/null; then
      echo "structured-yaml"
    else
      echo "playbook"
    fi
    return
  fi

  echo "unknown"
}

# --- extract_summary ---------------------------------------------------------
# Prints a one-line human-readable summary for the given diff_kind.

extract_summary() {
  local kind="$1"
  local path="$2"

  python3 - "$kind" "$path" <<'PYEOF'
import sys
import re
import yaml

kind = sys.argv[1]
path = sys.argv[2]
content = open(path).read()

MAX = 80

def truncate(s, max_len=MAX):
    return s if len(s) <= max_len else s[:max_len - 3] + "..."

if kind == "unified-diff":
    headers = re.findall(r'^\+\+\+ b/(.+)$', content, re.MULTILINE)
    n = len(headers)
    if n == 0:
        print("Unified diff (no file headers found)")
    else:
        first = headers[0]
        extra = f", +{n-1} more" if n > 1 else ""
        summary = f"Unified diff touching {n} file(s): {first}{extra}"
        print(truncate(summary))

elif kind == "structured-yaml":
    try:
        data = yaml.safe_load(content)
        # Prefer an explicit change_summary / summary field
        explicit = data.get("summary") or data.get("change_summary")
        if explicit:
            print(truncate(str(explicit)))
        else:
            forward = data.get("forward") or []
            n = len(forward)
            if n == 0:
                print("Structured YAML change (0 actions)")
            else:
                first = forward[0]
                first_str = first.get("action") or str(first)
                summary = f"{n} action(s): {first_str}"
                print(truncate(summary))
    except Exception:
        print("Structured YAML change (parse error)")

elif kind == "playbook":
    try:
        data = yaml.safe_load(content)
        plays = data if isinstance(data, list) else [data]
        n = len(plays)
        first_name = ""
        if isinstance(plays[0], dict):
            first_name = plays[0].get("name", "")
        prefix = f"Playbook: {first_name} " if first_name else "Playbook change "
        summary = f"{prefix}(shape ambiguous; {n} top-level key(s))"
        print(truncate(summary))
    except Exception:
        print("Playbook change (shape ambiguous; parse error)")
PYEOF
}

# --- extract_targets ---------------------------------------------------------
# Prints a JSON array of {kind, id} objects.
# On fatal failure (unified-diff with zero resolving targets when inventory root
# is set), emits ncr-targets-unresolvable to stderr and exits 3.

extract_targets() {
  local kind="$1"
  local path="$2"
  local inventory_root="${YCI_INVENTORY_ROOT:-}"

  # Pass inventory_root via env to python to avoid injection
  YCI_INVENTORY_ROOT="$inventory_root" \
  python3 - "$kind" "$path" <<'PYEOF'
import sys
import os
import re
import json
import yaml

kind = sys.argv[1]
path = sys.argv[2]
inventory_root = os.environ.get("YCI_INVENTORY_ROOT", "")
content = open(path).read()

FATAL_EXIT = 3
NCR_UNRESOLVABLE = "ncr-targets-unresolvable"

def emit_fatal(msg):
    print(f"[{NCR_UNRESOLVABLE}] {msg}", file=sys.stderr)
    sys.exit(FATAL_EXIT)

# ---- unified-diff -----------------------------------------------------------
if kind == "unified-diff":
    headers = re.findall(r'^\+\+\+ b/(.+)$', content, re.MULTILINE)
    if not headers:
        # No +++ b/ lines at all — no targets to resolve
        print(json.dumps([]))
        sys.exit(0)

    if not inventory_root:
        print("[warn] YCI_INVENTORY_ROOT not set; emitting unknown targets", file=sys.stderr)
        targets = [{"kind": "unknown", "id": p} for p in headers]
        print(json.dumps(targets))
        sys.exit(0)

    # Resolve each path against inventory
    # Map: dir name under inventory root -> kind label
    KIND_MAP = {
        "devices": "device",
        "services": "service",
        "tenants": "tenant",
    }

    def find_in_inventory(diff_path):
        """Return (kind, id) if diff_path matches an inventory record, else None."""
        # Last two path segments
        parts = [p for p in diff_path.split("/") if p]
        segments = parts[-2:] if len(parts) >= 2 else parts

        for subdir, label in KIND_MAP.items():
            inv_dir = os.path.join(inventory_root, subdir)
            if not os.path.isdir(inv_dir):
                continue
            for fname in os.listdir(inv_dir):
                if not fname.endswith(".yaml") and not fname.endswith(".yml"):
                    continue
                stem = fname.rsplit(".", 1)[0]
                # Check if any segment contains the stem as a substring,
                # or the stem contains any segment as a substring
                for seg in segments:
                    seg_no_ext = seg.rsplit(".", 1)[0] if "." in seg else seg
                    if stem in seg or seg in stem or stem in seg_no_ext or seg_no_ext in stem:
                        # Read inventory record to get id
                        inv_path = os.path.join(inv_dir, fname)
                        try:
                            rec = yaml.safe_load(open(inv_path))
                            rec_id = rec.get("id", stem) if isinstance(rec, dict) else stem
                        except Exception:
                            rec_id = stem
                        return (label, rec_id)
        return None

    targets = []
    for diff_path in headers:
        match = find_in_inventory(diff_path)
        if match:
            targets.append({"kind": match[0], "id": match[1]})
        else:
            targets.append({"kind": "unknown", "id": diff_path})

    # Check if ALL targets are unknown (zero resolved)
    resolved = [t for t in targets if t["kind"] != "unknown"]
    if not resolved:
        emit_fatal("Could not resolve any targets from change input.")

    print(json.dumps(targets))
    sys.exit(0)

# ---- structured-yaml --------------------------------------------------------
elif kind == "structured-yaml":
    try:
        data = yaml.safe_load(content)
    except Exception as e:
        emit_fatal(f"YAML parse error: {e}")

    forward = data.get("forward") or []
    IDENT_KEYS = ["device", "service", "tenant", "host"]
    targets = []
    seen = set()
    for step in forward:
        if not isinstance(step, dict):
            continue
        for key in IDENT_KEYS:
            if key in step:
                entry_kind = key if key != "host" else "unknown"
                entry_id = str(step[key])
                dedup_key = (entry_kind, entry_id)
                if dedup_key not in seen:
                    seen.add(dedup_key)
                    targets.append({"kind": entry_kind, "id": entry_id})

    if not targets:
        emit_fatal("Could not resolve any targets from change input.")

    print(json.dumps(targets))
    sys.exit(0)

# ---- playbook ---------------------------------------------------------------
elif kind == "playbook":
    try:
        data = yaml.safe_load(content)
    except Exception:
        print(json.dumps([]))
        sys.exit(0)

    # Best-effort: collect all 'hosts' values at any nesting level
    hosts = []
    seen = set()

    def collect_hosts(obj):
        if isinstance(obj, dict):
            if "hosts" in obj:
                val = obj["hosts"]
                for h in (val if isinstance(val, list) else [val]):
                    h_str = str(h)
                    if h_str not in seen:
                        seen.add(h_str)
                        hosts.append({"kind": "unknown", "id": h_str})
            for v in obj.values():
                collect_hosts(v)
        elif isinstance(obj, list):
            for item in obj:
                collect_hosts(item)

    collect_hosts(data)
    print(json.dumps(hosts))
    sys.exit(0)

else:
    print(json.dumps([]))
    sys.exit(0)
PYEOF
}

# --- main --------------------------------------------------------------------

main() {
  local diff_kind
  diff_kind="$(detect_diff_kind "$input_path")"

  [[ "$diff_kind" != "unknown" ]] \
    || err "ncr-diff-unsupported-shape" \
         "Unsupported change shape. Supported: unified-diff, structured-yaml, playbook." 3

  local summary targets_json
  summary="$(extract_summary "$diff_kind" "$input_path")"

  # extract_targets may exit 3 (ncr-targets-unresolvable) — let it propagate
  targets_json="$(extract_targets "$diff_kind" "$input_path")"

  # Assemble the canonical envelope via python for correct JSON escaping.
  # Pass summary via env var to avoid shell injection.
  local envelope
  envelope="$(PARSE_SUMMARY="$summary" python3 - "$diff_kind" "$input_path" "$targets_json" <<'PYEOF'
import json, sys, os

diff_kind  = sys.argv[1]
input_path = sys.argv[2]
targets    = json.loads(sys.argv[3])
summary    = os.environ["PARSE_SUMMARY"]
raw        = open(input_path).read()

out = {
    "diff_kind": diff_kind,
    "raw":       raw,
    "summary":   summary,
    "targets":   targets,
}
print(json.dumps(out, indent=2))
PYEOF
)"

  if [[ -n "$output_path" ]]; then
    printf '%s\n' "$envelope" > "$output_path"
  else
    printf '%s\n' "$envelope"
  fi
}

main
