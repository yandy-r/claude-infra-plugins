#!/usr/bin/env bash
# yci — render the human-readable whoami view for an active customer profile.
#
# Usage: render-whoami.sh <data-root> <customer>
# Stdout: multi-line context summary on success.
# Stderr: error messages only.
# Exit 0: success.
# Exit 1: profile not found or invalid customer id.
# Exit 2: schema violation from loader.
# Exit 3: runtime error from loader.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

data_root="${1:?usage: render-whoami.sh <data-root> <customer>}"
customer="${2:?usage: render-whoami.sh <data-root> <customer>}"

# --- load and validate profile (propagates loader exit codes) ---------------
profile_json="$("${SCRIPT_DIR}/load-profile.sh" "$data_root" "$customer")"

# --- render human-readable summary ------------------------------------------
# Pass profile_json as argv[2] to avoid the pipe-vs-heredoc conflict (SC2259).
python3 - "$customer" "$profile_json" <<'PY'
import json, sys

customer_arg = sys.argv[1]
data = json.loads(sys.argv[2])

def get(obj, *keys, default="-"):
    """Safely traverse nested dicts; return default on any missing key."""
    for key in keys:
        if not isinstance(obj, dict):
            return default
        obj = obj.get(key)
        if obj is None:
            return default
    return str(obj) if obj is not None else default

cust       = data.get("customer", {})
eng        = data.get("engagement", {})
comp       = data.get("compliance", {})
safety     = data.get("safety", {})

cust_id       = get(cust,  "id",           default=customer_arg)
display_name  = get(cust,  "display_name")
eng_id        = get(eng,   "id")
eng_type      = get(eng,   "type")
sow_ref       = get(eng,   "sow_ref")
start_date    = get(eng,   "start_date")
end_date      = get(eng,   "end_date")
regime        = get(comp,  "regime")
ev_schema_ver = get(comp,  "evidence_schema_version")
posture       = get(safety, "default_posture")
scope_enf     = get(safety, "scope_enforcement")
cw_required   = get(safety, "change_window_required")

# scope_tags is a list; join with ", "
raw_tags = eng.get("scope_tags")
if isinstance(raw_tags, list) and raw_tags:
    scope_tags = ", ".join(str(t) for t in raw_tags)
elif isinstance(raw_tags, str) and raw_tags:
    scope_tags = raw_tags
else:
    scope_tags = "-"

print(f"yci: active customer = {cust_id}")
print(f"  display name   : {display_name}")
print(f"  engagement     : {eng_id} ({eng_type}, SOW {sow_ref})")
print(f"  dates          : {start_date} → {end_date}")
print(f"  compliance     : {regime} (evidence schema v{ev_schema_ver})")
print(f"  safety posture : {posture}  (scope: {scope_enf}, change-window-required: {cw_required})")
print(f"  scope tags     : {scope_tags}")
PY
