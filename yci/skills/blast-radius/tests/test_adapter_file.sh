#!/usr/bin/env bash
# yci blast-radius — adapter-file.sh tests

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helpers.sh"

ADAPTER="${YCI_SCRIPTS_DIR}/adapter-file.sh"
INV_WIDGET="${FIXTURES_DIR}/inventory-widgetcorp"
INV_OTHER="${FIXTURES_DIR}/inventory-other-customer"
EXPECTED="${FIXTURES_DIR}/expected-inventory.json"

# --- golden match (widgetcorp) ----------------------------------------------
got="$("$ADAPTER" "$INV_WIDGET" 2>/dev/null)"
rc=$?
assert_exit 0 "$rc" "adapter exits 0 on valid inventory"

expected="$(cat "$EXPECTED")"
if python3 -c "
import json, sys
got = json.loads(sys.argv[1])
expected = json.loads(sys.argv[2])
# normalize: root contains an absolute path that depends on the checkout location,
# so strip it before comparing
got['root'] = '<root>'
expected['root'] = '<root>'
sys.exit(0 if got == expected else 1)
" "$got" "$expected"; then
    _yci_test_report PASS "adapter output matches expected-inventory.json (modulo root path)"
else
    _yci_test_report FAIL "adapter output matches expected-inventory.json (modulo root path)" "JSON diverged"
fi

# --- missing path -----------------------------------------------------------
stderr="$("$ADAPTER" /does/not/exist 2>&1 >/dev/null)"
rc=$?
assert_exit 1 "$rc" "adapter exits 1 on missing path"
assert_contains "$stderr" "adapter-path-missing" "missing-path error id surfaced"

# --- no arguments -----------------------------------------------------------
stderr="$("$ADAPTER" 2>&1 >/dev/null)"
rc=$?
assert_exit 2 "$rc" "adapter exits 2 on no arguments"
assert_contains "$stderr" "usage" "usage message emitted"

# --- malformed yaml record --------------------------------------------------
bad_root="$(mktemp -d)"
trap 'rm -rf "$bad_root"' EXIT
mkdir -p "$bad_root/services"
cat > "$bad_root/services/orders-api.yaml" <<'YAML'
id: orders-api
criticality: [this is: not: valid yaml
YAML
stderr="$("$ADAPTER" "$bad_root" 2>&1 >/dev/null)"
rc=$?
assert_exit 2 "$rc" "adapter exits 2 on malformed YAML"
assert_contains "$stderr" "adapter-yaml-malformed" "malformed-yaml error id surfaced"

# --- id mismatch ------------------------------------------------------------
mm_root="$(mktemp -d)"
mkdir -p "$mm_root/services"
cat > "$mm_root/services/orders-api.yaml" <<'YAML'
id: different-id
criticality: tier-1
rto_band: 5m-1h
YAML
stderr="$("$ADAPTER" "$mm_root" 2>&1 >/dev/null)"
rc=$?
assert_exit 2 "$rc" "adapter exits 2 on id mismatch"
assert_contains "$stderr" "adapter-id-mismatch" "id-mismatch error id surfaced"
rm -rf "$mm_root"

# --- invalid enum (criticality) --------------------------------------------
en_root="$(mktemp -d)"
mkdir -p "$en_root/services"
cat > "$en_root/services/orders-api.yaml" <<'YAML'
id: orders-api
criticality: tier-99
rto_band: 5m-1h
YAML
stderr="$("$ADAPTER" "$en_root" 2>&1 >/dev/null)"
rc=$?
assert_exit 2 "$rc" "adapter exits 2 on invalid criticality enum"
assert_contains "$stderr" "adapter-schema-enum" "schema-enum error id surfaced"
rm -rf "$en_root"

# --- other-customer inventory loads independently --------------------------
out="$("$ADAPTER" "$INV_OTHER" 2>/dev/null)"
rc=$?
assert_exit 0 "$rc" "adapter loads inventory-other-customer"
assert_json_field "$out" "adapter" "file" "other-customer adapter == file"
assert_json_contains_item "$out" "devices" "id" "other-edge-01" "other-customer devices contain other-edge-01"
assert_json_contains_item "$out" "services" "id" "other-service" "other-customer services contain other-service"

yci_test_summary
