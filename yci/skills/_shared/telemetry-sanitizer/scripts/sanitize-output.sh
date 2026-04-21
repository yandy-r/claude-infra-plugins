#!/usr/bin/env bash
# yci — sanitize stdin using active customer profile + compliance adapter rules.
#
# Resolves data root and customer like other yci CLIs, loads profile JSON,
# selects compliance.regime, then runs sanitize_text.py on stdin.
#
# Usage: sanitize-output.sh [--data-root <path> | --data-root=<path>] ...
# Stdin: raw text. Stdout: redacted text. Stderr: errors only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
YCI_PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd -P)"
SHARED_SCRIPTS="${YCI_PLUGIN_ROOT}/skills/_shared/scripts"

# shellcheck source=/dev/null
source "${SHARED_SCRIPTS}/resolve-data-root.sh"

data_root="$(yci_resolve_data_root "$@")"
customer="$(bash "${YCI_PLUGIN_ROOT}/skills/customer-profile/scripts/resolve-customer.sh" "$@")"
profile_json="$(bash "${YCI_PLUGIN_ROOT}/skills/customer-profile/scripts/load-profile.sh" "$data_root" "$customer")"

prof_tmp="$(mktemp)"
cleanup() { rm -f "$prof_tmp"; }
trap cleanup EXIT
printf '%s' "$profile_json" > "$prof_tmp"

regime="$(printf '%s' "$profile_json" | python3 -c "import json,sys; d=json.load(sys.stdin); c=d.get('compliance') or {}; r=c.get('regime'); print(r if isinstance(r,str) and r.strip() else 'none')")"

exec python3 "${SCRIPT_DIR}/sanitize_text.py" \
  --profile-json "$prof_tmp" \
  --yci-root "$YCI_PLUGIN_ROOT" \
  --regime "$regime" \
  --mode "${YCI_SANITIZER_MODE:-strict}"
