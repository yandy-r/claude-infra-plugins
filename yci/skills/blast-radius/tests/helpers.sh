#!/usr/bin/env bash
# Shared test helpers for yci blast-radius tests.
# Source this file from every test_*.sh.
# Do NOT set -euo here — tests need fine-grained control over exit behavior.

YCI_TEST_PASS=0
YCI_TEST_FAIL=0
YCI_TEST_FILE="${BASH_SOURCE[1]##*/}"  # caller's basename

# Resolve key directory paths (tolerates missing dirs — scripts may not yet exist)
_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if cd "${_HELPERS_DIR}/../scripts" 2>/dev/null; then
    YCI_SCRIPTS_DIR="$(pwd -P)"
    cd "${_HELPERS_DIR}" || true
else
    YCI_SCRIPTS_DIR="${_HELPERS_DIR}/../scripts"
fi
export YCI_SCRIPTS_DIR

if cd "${_HELPERS_DIR}/../references" 2>/dev/null; then
    YCI_REFS_DIR="$(pwd -P)"
    cd "${_HELPERS_DIR}" || true
else
    YCI_REFS_DIR="${_HELPERS_DIR}/../references"
fi
export YCI_REFS_DIR

FIXTURES_DIR="${_HELPERS_DIR}/fixtures"
export FIXTURES_DIR

# ---------------------------------------------------------------------------
# Internal reporter
# ---------------------------------------------------------------------------

_yci_test_report() {
    local status="$1" name="$2" detail="${3:-}"
    if [ "$status" = "PASS" ]; then
        YCI_TEST_PASS=$((YCI_TEST_PASS + 1))
        [ "${YCI_TEST_VERBOSE:-0}" = "1" ] && printf '  \033[32m+\033[0m %s\n' "$name"
    else
        YCI_TEST_FAIL=$((YCI_TEST_FAIL + 1))
        printf '  \033[31mFAIL\033[0m %s\n' "$name" >&2
        [ -n "$detail" ] && printf '    %s\n' "$detail" >&2
    fi
}

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

assert_eq() {
    local got="$1" expected="$2" name="${3:-assert_eq}"
    if [ "$got" = "$expected" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "got='$got' expected='$expected'"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" name="${3:-assert_contains}"
    case "$haystack" in
        *"$needle"*) _yci_test_report PASS "$name" ;;
        *)           _yci_test_report FAIL "$name" "'$needle' not in output" ;;
    esac
}

assert_not_contains() {
    local haystack="$1" needle="$2" name="${3:-assert_not_contains}"
    case "$haystack" in
        *"$needle"*) _yci_test_report FAIL "$name" "unexpected '$needle' found in output" ;;
        *)           _yci_test_report PASS "$name" ;;
    esac
}

assert_exit() {
    local expected="$1" got="$2" name="${3:-assert_exit}"
    if [ "$got" = "$expected" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "exit got=$got expected=$expected"
    fi
}

assert_file_exists() {
    local path="$1" name="${2:-assert_file_exists}"
    if [ -f "$path" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "file not found: $path"
    fi
}

assert_json_valid() {
    local input="$1" name="${2:-assert_json_valid}"
    if python3 -c "import json,sys; json.loads(sys.argv[1])" "$input" 2>/dev/null; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "invalid JSON"
    fi
}

assert_json_eq() {
    # Deep-equal two JSON strings using python3.
    local got="$1" expected="$2" name="${3:-assert_json_eq}"
    if python3 -c "
import json, sys
a = json.loads(sys.argv[1])
b = json.loads(sys.argv[2])
sys.exit(0 if a == b else 1)
" "$got" "$expected" >/dev/null 2>&1; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "JSON objects not equal"
    fi
}

assert_json_field() {
    # Assert that a JSON string has a top-level field with a specific value.
    # Usage: assert_json_field <json_str> <field> <expected_value> <test_name>
    local json_str="$1" field="$2" expected="$3" name="${4:-assert_json_field}"
    local got
    got=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
v = d.get(sys.argv[2])
print(v if v is not None else '')
" "$json_str" "$field" 2>/dev/null)
    if [ "$got" = "$expected" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "field '$field': got='$got' expected='$expected'"
    fi
}

assert_json_field_matches() {
    # Assert a JSON top-level field matches a regex pattern (python re.search).
    local json_str="$1" field="$2" pattern="$3" name="${4:-assert_json_field_matches}"
    if python3 -c "
import json, re, sys
d = json.loads(sys.argv[1])
v = str(d.get(sys.argv[2], ''))
sys.exit(0 if re.search(sys.argv[3], v) else 1)
" "$json_str" "$field" "$pattern" >/dev/null 2>&1; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "field '$field' did not match pattern '$pattern'"
    fi
}

assert_json_array_nonempty() {
    # Assert a JSON top-level array field is non-empty.
    local json_str="$1" field="$2" name="${3:-assert_json_array_nonempty}"
    if python3 -c "
import json, sys
d = json.loads(sys.argv[1])
arr = d.get(sys.argv[2], [])
sys.exit(0 if isinstance(arr, list) and len(arr) > 0 else 1)
" "$json_str" "$field" >/dev/null 2>&1; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "field '$field' is empty or missing"
    fi
}

assert_json_contains_item() {
    # Assert a JSON top-level array field contains an item where key==value.
    # Usage: assert_json_contains_item <json_str> <array_field> <item_key> <item_value> <name>
    local json_str="$1" field="$2" key="$3" value="$4" name="${5:-assert_json_contains_item}"
    if python3 -c "
import json, sys
d = json.loads(sys.argv[1])
arr = d.get(sys.argv[2], [])
found = any(str(item.get(sys.argv[3], '')) == sys.argv[4] for item in arr if isinstance(item, dict))
sys.exit(0 if found else 1)
" "$json_str" "$field" "$key" "$value" >/dev/null 2>&1; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "array '$field' has no item where $key='$value'"
    fi
}

# ---------------------------------------------------------------------------
# Inventory helpers
# ---------------------------------------------------------------------------

# Compute the canonical inventory_source_fingerprint for a normalized adapter
# output (JSON string on stdin argument). Mirrors the fingerprint logic inside
# reason.sh so tests can assert fingerprint identity/divergence without
# invoking the reasoner.
#
# Usage: compute_inventory_fingerprint "$INVENTORY_JSON"
# Stdout: sha256:<64-hex>
compute_inventory_fingerprint() {
    python3 -c '
import hashlib, json, sys
d = json.loads(sys.argv[1])
subset = {k: d.get(k, []) for k in ("tenants", "services", "devices", "dependencies", "sites")}
print("sha256:" + hashlib.sha256(json.dumps(subset, sort_keys=True, separators=(",", ":")).encode()).hexdigest())
' "$1"
}

# ---------------------------------------------------------------------------
# Summary — call at the end of every test_*.sh
# ---------------------------------------------------------------------------

yci_test_summary() {
    if [ "$YCI_TEST_FAIL" -eq 0 ]; then
        printf '  %s: %d passed\n' "$YCI_TEST_FILE" "$YCI_TEST_PASS"
        return 0
    else
        printf '  %s: %d passed, %d FAILED\n' "$YCI_TEST_FILE" "$YCI_TEST_PASS" "$YCI_TEST_FAIL" >&2
        return 1
    fi
}
