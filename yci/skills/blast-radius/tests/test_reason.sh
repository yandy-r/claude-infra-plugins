#!/usr/bin/env bash
# yci blast-radius — reason.sh tests

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helpers.sh"

ADAPTER="${YCI_SCRIPTS_DIR}/adapter-file.sh"
REASON="${YCI_SCRIPTS_DIR}/reason.sh"
INV_WIDGET="${FIXTURES_DIR}/inventory-widgetcorp"

export YCI_GENERATED_AT="2026-04-21T00:00:00Z"

build_payload() {
    # $1 = change name (simple|cascade|unknown-target)
    local change_name="$1"
    local inv_json
    inv_json="$("$ADAPTER" "$INV_WIDGET")"
    local change_json
    change_json="$(python3 -c '
import sys, json
try:
    import yaml
except ImportError:
    sys.stderr.write("test_reason.sh: pyyaml required to load change-*.yaml fixtures — install pyyaml via pip or your distro package manager\n")
    sys.exit(3)
print(json.dumps(yaml.safe_load(open(sys.argv[1]))))
' "${FIXTURES_DIR}/change-${change_name}.yaml")"
    python3 -c "
import json, sys
inv = json.loads(sys.argv[1])
ch = json.loads(sys.argv[2])
print(json.dumps({'inventory': inv, 'change': ch, 'customer': 'widget-corp'}))
" "$inv_json" "$change_json"
}

compare_to_golden() {
    # $1 = change name, $2 = golden name (simple|cascade|unknown)
    local change_name="$1" golden_name="$2"
    local payload
    payload="$(build_payload "$change_name")"
    local got
    got="$(printf '%s' "$payload" | "$REASON")"
    local rc=$?
    assert_exit 0 "$rc" "reason.sh exits 0 on $change_name"

    local expected
    expected="$(cat "${FIXTURES_DIR}/expected-label-${golden_name}.json")"
    if python3 -c "
import json, sys
a = json.loads(sys.argv[1])
b = json.loads(sys.argv[2])
sys.exit(0 if a == b else 1)
" "$got" "$expected"; then
        _yci_test_report PASS "label matches expected-label-${golden_name}.json"
    else
        _yci_test_report FAIL "label matches expected-label-${golden_name}.json" "golden divergence"
    fi

    # Top-level invariants
    assert_json_field "$got" "schema_version" "1" "$change_name schema_version == 1"
    assert_json_field "$got" "customer" "widget-corp" "$change_name customer correct"
    assert_json_field "$got" "inventory_adapter" "file" "$change_name adapter == file"
    assert_json_field_matches "$got" "inventory_source_fingerprint" "^sha256:[0-9a-f]{64}$" "$change_name fingerprint format"
    assert_json_field "$got" "generated_at" "2026-04-21T00:00:00Z" "$change_name generated_at pinned"
}

# --- golden comparisons ------------------------------------------------------
compare_to_golden simple simple
compare_to_golden cascade cascade
compare_to_golden unknown-target unknown

# --- simple-specific structural assertions ---------------------------------
label="$(build_payload simple | "$REASON")"
assert_json_contains_item "$label" "direct_devices" "id" "dc1-edge-01" "simple: direct_devices contains dc1-edge-01"
assert_json_contains_item "$label" "services" "id" "orders-api" "simple: services contains orders-api"
assert_json_contains_item "$label" "services" "id" "checkout-web" "simple: services contains checkout-web (downstream)"
assert_json_field "$label" "rto_band" "lt-5m" "simple: aggregate rto_band is strictest (lt-5m)"
assert_json_field "$label" "confidence" "high" "simple: confidence high (no gaps)"

# --- cascade: two direct devices, cascade through orders-api → checkout-web --
label="$(build_payload cascade | "$REASON")"
assert_json_contains_item "$label" "direct_devices" "id" "dc1-edge-01" "cascade: dc1-edge-01 direct"
assert_json_contains_item "$label" "direct_devices" "id" "dc1-edge-02" "cascade: dc1-edge-02 direct"
assert_json_contains_item "$label" "downstream_consumers" "id" "checkout-web" "cascade: checkout-web downstream"
assert_json_contains_item "$label" "downstream_consumers" "id" "retail-ops" "cascade: retail-ops tenant downstream"
assert_json_field "$label" "confidence" "high" "cascade: confidence high"

# --- unknown-target: unknown-device gap, low confidence --------------------
label="$(build_payload unknown-target | "$REASON")"
assert_json_field "$label" "confidence" "low" "unknown: confidence low"
assert_json_array_nonempty "$label" "coverage_gaps" "unknown: coverage_gaps non-empty"
assert_json_contains_item "$label" "coverage_gaps" "kind" "unknown-device" "unknown: unknown-device gap present"

# --- empty stdin -----------------------------------------------------------
out="$(printf '' | "$REASON" 2>&1 >/dev/null)"
rc=$?
assert_exit 1 "$rc" "reason exits 1 on empty stdin"
assert_contains "$out" "reason-missing-stdin" "empty-stdin error id surfaced"

# --- invalid JSON ----------------------------------------------------------
out="$(printf 'not json' | "$REASON" 2>&1 >/dev/null)"
rc=$?
assert_exit 1 "$rc" "reason exits 1 on non-JSON stdin"
assert_contains "$out" "reason-missing-stdin" "non-json error id surfaced"

# --- missing required payload key ------------------------------------------
out="$(printf '{"inventory":{}}' | "$REASON" 2>&1 >/dev/null)"
rc=$?
assert_exit 1 "$rc" "reason exits 1 on missing 'change' key"
assert_contains "$out" "reason-missing-required" "missing-required error id surfaced"

yci_test_summary
