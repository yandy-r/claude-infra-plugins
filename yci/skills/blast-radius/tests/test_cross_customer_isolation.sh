#!/usr/bin/env bash
# yci blast-radius — cross-customer isolation regression.
# Confirms the adapter + reasoner cannot leak one customer's inventory into
# another customer's label, and that the inventory_source_fingerprint
# distinguishes two customer inventories.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helpers.sh"

ADAPTER="${YCI_SCRIPTS_DIR}/adapter-file.sh"
REASON="${YCI_SCRIPTS_DIR}/reason.sh"
INV_WIDGET="${FIXTURES_DIR}/inventory-widgetcorp"
INV_OTHER="${FIXTURES_DIR}/inventory-other-customer"

export YCI_GENERATED_AT="2026-04-21T00:00:00Z"

# --- two inventories yield different fingerprints --------------------------
INV_W="$("$ADAPTER" "$INV_WIDGET")"
INV_O="$("$ADAPTER" "$INV_OTHER")"

FP_W="$(compute_inventory_fingerprint "$INV_W")"
FP_O="$(compute_inventory_fingerprint "$INV_O")"

if [ "$FP_W" != "$FP_O" ]; then
    _yci_test_report PASS "two customer inventories yield distinct fingerprints"
else
    _yci_test_report FAIL "two customer inventories yield distinct fingerprints" "FP_W == FP_O == $FP_W"
fi

# --- change that references the OTHER customer's device is unknown in widgetcorp
CROSS_CHANGE='{
  "change_id": "CROSS-LEAK-TEST-01",
  "change_type": "config",
  "summary": "Cross-customer leak test",
  "targets": [
    {"kind": "device", "id": "other-edge-01", "rationale": "this id belongs to a different customer"}
  ]
}'

PAYLOAD="$(python3 -c "
import json, sys
inv = json.loads(sys.argv[1])
ch = json.loads(sys.argv[2])
print(json.dumps({'inventory': inv, 'change': ch, 'customer': 'widget-corp'}))
" "$INV_W" "$CROSS_CHANGE")"

LABEL="$(printf '%s' "$PAYLOAD" | "$REASON")"

assert_json_field "$LABEL" "customer" "widget-corp" "isolation: label reports widget-corp customer"
assert_json_field "$LABEL" "confidence" "low" "isolation: confidence low due to unknown device"
assert_json_contains_item "$LABEL" "coverage_gaps" "kind" "unknown-device" "isolation: unknown-device gap emitted"

# Confirm the resulting label's fingerprint matches widget-corp inventory only
got_fp="$(python3 -c 'import json, sys; print(json.loads(sys.argv[1])["inventory_source_fingerprint"])' "$LABEL")"
assert_eq "$got_fp" "$FP_W" "isolation: fingerprint matches widgetcorp, NOT other-customer"

# Confirm NO record from inventory-other-customer leaked into direct_devices/services/dependencies.
# (None of widget-corp's fixtures contain the string "other-edge-01" or "other-service" or "other-tenant".)
if printf '%s' "$LABEL" | python3 -c '
import json, sys
d = json.load(sys.stdin)
bad_ids = {"other-edge-01", "other-service", "other-tenant"}
found = []
for arr_key in ("direct_devices", "services", "downstream_consumers", "tenants"):
    for item in d.get(arr_key, []):
        if isinstance(item, dict):
            if item.get("id") in bad_ids:
                found.append((arr_key, item.get("id")))
        elif isinstance(item, str):
            if item in bad_ids:
                found.append((arr_key, item))
for edge in d.get("dependencies", []):
    if edge.get("from") in bad_ids or edge.get("to") in bad_ids:
        found.append(("dependencies", edge))
sys.exit(0 if not found else 1)
'; then
    _yci_test_report PASS "isolation: no other-customer ids leaked into label fields"
else
    _yci_test_report FAIL "isolation: no other-customer ids leaked into label fields" "found other-customer ids in label"
fi

# The unknown-device detail may legitimately mention the id (that's the whole
# point of a coverage gap). Coverage-gaps references are OK; everywhere else
# must be clean.

# --- adapter against widget cannot read paths in other-customer via symlink
trap_dir="$(mktemp -d)"
trap 'rm -rf "$trap_dir"' EXIT
mkdir -p "$trap_dir/services"
ln -s "${INV_OTHER}/services/other-service.yaml" "$trap_dir/services/planted.yaml"
stderr="$("$ADAPTER" "$trap_dir" 2>&1 >/dev/null)"
rc=$?
assert_exit 1 "$rc" "isolation: adapter refuses symlink escape"
assert_contains "$stderr" "adapter-path-escape" "isolation: path-escape error id surfaced"

yci_test_summary
