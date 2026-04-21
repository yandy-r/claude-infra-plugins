#!/usr/bin/env bash
# preflight-cross-customer.sh — scan raw change text for foreign-customer identifiers.
#
# Same logic as review.sh step 8. Invoke before ycc subagents (see SKILL.md);
# review.sh calls this script so behavior stays single-sourced.
#
# Usage:
#   preflight-cross-customer.sh --data-root <path> --customer <id> --change <path>
#
# --data-root must be the resolved data root (same string review.sh uses after
# resolve-data-root.sh).
#
# Exit: 0 ok | 1 configuration (PyYAML / profiles dir) | 7 foreign identifier hit

set -euo pipefail

data_root="" customer="" change_path=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data-root) data_root="${2:?}"; shift 2 ;;
    --customer)  customer="${2:?}"; shift 2 ;;
    --change)    change_path="${2:?}"; shift 2 ;;
    *)           printf 'preflight-cross-customer.sh: unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[[ -n "$data_root" && -n "$customer" && -n "$change_path" ]] || {
  printf 'preflight-cross-customer.sh: --data-root, --customer, and --change are required\n' >&2
  exit 2
}
[[ -r "$change_path" ]] || {
  printf 'preflight-cross-customer.sh: change file not readable: %s\n' "$change_path" >&2
  exit 2
}

change_path="$(cd "$(dirname "$change_path")" && pwd -P)/$(basename "$change_path")"

python3 - "$data_root" "$customer" "$change_path" <<'PYEOF'
import os
import sys

try:
    import yaml
except ImportError as exc:
    sys.stderr.write(
        f"preflight-cross-customer.sh: PyYAML is required for profile scanning: {exc}\n"
    )
    sys.exit(1)

data_root, active_customer, change_path = sys.argv[1], sys.argv[2], sys.argv[3]
profiles_dir = os.path.join(data_root, "profiles")
if not os.path.isdir(profiles_dir):
    sys.stderr.write(
        f"preflight-cross-customer.sh: profiles directory not found: {profiles_dir}\n"
    )
    sys.exit(1)

change_text = open(change_path).read()
hits = []

for fname in sorted(os.listdir(profiles_dir)):
    if not fname.endswith(".yaml"):
        continue
    pid = os.path.splitext(fname)[0]
    if pid == active_customer or pid.startswith("_"):
        continue
    try:
        prof = yaml.safe_load(open(os.path.join(profiles_dir, fname))) or {}
    except Exception:
        continue
    foreign_ids = set()
    c = prof.get("customer", {}) or {}
    if c.get("id"):
        foreign_ids.add(str(c["id"]))
    if c.get("sow_ref"):
        foreign_ids.add(str(c["sow_ref"]))
    n = prof.get("network", {}) or {}
    if n.get("hostname_suffix"):
        foreign_ids.add(str(n["hostname_suffix"]))
    for r in (n.get("ipv4_ranges") or []):
        s = str(r).split("/")[0]
        octets = s.split(".")
        if len(octets) >= 3:
            foreign_ids.add(".".join(octets[:3]) + ".")
    for fid in foreign_ids:
        if fid and fid in change_text:
            hits.append((pid, fid))

if hits:
    for pid, fid in hits:
        sys.stderr.write(
            f"  foreign identifier '{fid}' (customer={pid}) present in change\n"
        )
    sys.exit(7)
PYEOF
