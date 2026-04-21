#!/usr/bin/env bash
# yci — validate customer id, load profile, persist active state.
#
# Usage: switch-profile.sh <data-root> <customer>
# Stdout: one-line confirmation on success.
# Stderr: error messages only.
# Exit 0: success.
# Exit 1: invalid customer id, or loader reports missing file.
# Exit 2: schema violation from loader.
# Exit 3: runtime error from loader or state-io.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/state-io.sh"

data_root="${1:?usage: switch-profile.sh <data-root> <customer>}"
customer="${2:?usage: switch-profile.sh <data-root> <customer>}"

# --- validate customer id format (init-invalid-customer-id, exit 1) ---------
if ! [[ "$customer" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    printf "yci: invalid customer id: '%s'\n" "$customer" >&2
    printf '  allowed pattern: [a-z0-9][a-z0-9-]*  (lowercase, hyphens only)\n' >&2
    exit 1
fi

# --- load and validate profile (propagates loader exit codes) ---------------
profile_json="$("${SCRIPT_DIR}/load-profile.sh" "$data_root" "$customer")"

# --- extract summary fields for confirmation line (single python3 invocation) ---
IFS=$'\t' read -r engagement_id compliance_regime default_posture < <(
    printf '%s' "$profile_json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(
    d.get("engagement", {}).get("id", ""),
    d.get("compliance", {}).get("regime", ""),
    d.get("safety", {}).get("default_posture", ""),
    sep="\t",
)
'
)

# --- persist active state (propagates state-io exit codes) ------------------
state_write_active "$data_root" "$customer"

# --- confirmation -----------------------------------------------------------
printf 'yci: switched to %s (%s, %s, %s)\n' \
    "$customer" "$engagement_id" "$compliance_regime" "$default_posture"
