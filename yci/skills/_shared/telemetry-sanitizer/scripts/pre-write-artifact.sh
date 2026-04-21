#!/usr/bin/env bash
# yci — read artifact body from stdin, sanitize, write to --output.
#
# Cross-customer relaxed mode (internal) requires BOTH:
#   - YCI_INTERNAL_CROSS_CUSTOMER_OK=1
#   - --meta-file whose contents include a YAML line: customer: _internal
#
# Usage:
#   pre-write-artifact.sh [--data-root ...] --output PATH [--meta-file PATH]
# All other args before --output are forwarded to yci_resolve_data_root / resolve-customer.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
YCI_PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd -P)"
SHARED_SCRIPTS="${YCI_PLUGIN_ROOT}/skills/_shared/scripts"

# shellcheck source=/dev/null
source "${SHARED_SCRIPTS}/resolve-data-root.sh"

OUTPUT_PATH=""
META_FILE=""
forward_args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output|--output=*)
            if [[ "$1" == --output=* ]]; then
                OUTPUT_PATH="${1#--output=}"
                shift
            else
                OUTPUT_PATH="${2:?--output requires a path}"
                shift 2
            fi
            ;;
        --meta-file|--meta-file=*)
            if [[ "$1" == --meta-file=* ]]; then
                META_FILE="${1#--meta-file=}"
                shift
            else
                META_FILE="${2:?--meta-file requires a path}"
                shift 2
            fi
            ;;
        *)
            forward_args+=("$1")
            shift
            ;;
    esac
done

if [ -z "$OUTPUT_PATH" ]; then
    printf 'yci: pre-write-artifact.sh: --output is required\n' >&2
    exit 2
fi

mode="strict"
if [ "${YCI_INTERNAL_CROSS_CUSTOMER_OK:-}" = "1" ] && [ -n "$META_FILE" ] && [ -f "$META_FILE" ]; then
    if grep -qE '^customer:[[:space:]]*_internal[[:space:]]*$' "$META_FILE"; then
        mode="internal"
    fi
fi

data_root="$(yci_resolve_data_root "${forward_args[@]}")"
customer="$(bash "${YCI_PLUGIN_ROOT}/skills/customer-profile/scripts/resolve-customer.sh" "${forward_args[@]}")"
profile_json="$(bash "${YCI_PLUGIN_ROOT}/skills/customer-profile/scripts/load-profile.sh" "$data_root" "$customer")"

prof_tmp="$(mktemp)"
body_tmp="$(mktemp)"
cleanup() { rm -f "$prof_tmp" "$body_tmp"; }
trap cleanup EXIT
printf '%s' "$profile_json" > "$prof_tmp"
cat > "$body_tmp"

regime="$(printf '%s' "$profile_json" | python3 -c "import json,sys; d=json.load(sys.stdin); c=d.get('compliance') or {}; r=c.get('regime'); print(r if isinstance(r,str) and r.strip() else 'none')")"

python3 "${SCRIPT_DIR}/sanitize_text.py" \
  --profile-json "$prof_tmp" \
  --yci-root "$YCI_PLUGIN_ROOT" \
  --regime "$regime" \
  --mode "$mode" \
  "$body_tmp" > "$OUTPUT_PATH"
