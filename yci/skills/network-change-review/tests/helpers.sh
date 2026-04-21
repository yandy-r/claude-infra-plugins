#!/usr/bin/env bash
# Shared test helpers for yci network-change-review tests.
# Source this file from every test_*.sh.
# This helper enables strict mode. Test scripts that expect a failing command should
# wrap that command with `set +e` / `set -e` or an `if` / `|| true` guard.

set -euo pipefail

YCI_TEST_PASS=0
YCI_TEST_FAIL=0
YCI_TEST_FILE="${BASH_SOURCE[1]##*/}"  # caller's basename

# Resolve key directory paths (tolerates missing dirs — scripts may not yet exist)
_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if cd "${_HELPERS_DIR}/../scripts" 2>/dev/null; then
    SKILL_ROOT_SCRIPTS="$(pwd -P)"
    cd "${_HELPERS_DIR}" || true
else
    SKILL_ROOT_SCRIPTS="${_HELPERS_DIR}/../scripts"
fi

# SKILL_ROOT is the skill directory (parent of tests/, scripts/, references/)
SKILL_ROOT="$(cd "${_HELPERS_DIR}/.." && pwd -P)"
export SKILL_ROOT

# PLUGIN_ROOT — runtime plugin install (invoking repo); falls back for bare test runs.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${_HELPERS_DIR}/../../.." && pwd -P)}"
export PLUGIN_ROOT

FIXTURES_ROOT="${_HELPERS_DIR}/fixtures"
export FIXTURES_ROOT

# ---------------------------------------------------------------------------
# Internal reporter
# ---------------------------------------------------------------------------

_yci_test_report() {
    local status="$1" name="$2" detail="${3:-}"
    if [ "$status" = "PASS" ]; then
        YCI_TEST_PASS=$((YCI_TEST_PASS + 1))
        if [ "${YCI_TEST_VERBOSE:-0}" = "1" ]; then
            printf '  \033[32m+\033[0m %s\n' "$name"
        fi
    else
        YCI_TEST_FAIL=$((YCI_TEST_FAIL + 1))
        printf '  \033[31mFAIL\033[0m %s\n' "$name" >&2
        if [ -n "$detail" ]; then
            printf '    %s\n' "$detail" >&2
        fi
    fi
}

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

assert_equals() {
    local expected="$1" actual="$2" name="${3:-assert_equals}"
    if [ "$actual" = "$expected" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "expected='$expected' actual='$actual'"
    fi
}

# Alias matching blast-radius api style
assert_eq() {
    local got="$1" expected="$2" name="${3:-assert_eq}"
    assert_equals "$expected" "$got" "$name"
}

assert_contains() {
    local substring="$1" haystack="$2" name="${3:-assert_contains}"
    case "$haystack" in
        *"$substring"*) _yci_test_report PASS "$name" ;;
        *)              _yci_test_report FAIL "$name" "'$substring' not found in string" ;;
    esac
}

assert_not_contains() {
    local substring="$1" haystack="$2" name="${3:-assert_not_contains}"
    case "$haystack" in
        *"$substring"*) _yci_test_report FAIL "$name" "unexpected '$substring' found in string" ;;
        *)              _yci_test_report PASS "$name" ;;
    esac
}

assert_file_exists() {
    local path="$1" name="${2:-assert_file_exists}"
    if [ -f "$path" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "file not found: $path"
    fi
}

assert_exit_code() {
    local expected_code="$1" actual_code="$2" name="${3:-assert_exit_code}"
    if [ "$actual_code" = "$expected_code" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "exit code: expected=$expected_code actual=$actual_code"
    fi
}

# Alias matching blast-radius api style
assert_exit() {
    local expected="$1" got="$2" name="${3:-assert_exit}"
    assert_exit_code "$expected" "$got" "$name"
}

assert_matches() {
    local regex="$1" string="$2" name="${3:-assert_matches}"
    if printf '%s' "$string" | grep -qP "$regex" 2>/dev/null; then
        _yci_test_report PASS "$name"
    elif printf '%s' "$string" | grep -qE "$regex" 2>/dev/null; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "pattern '$regex' did not match: '$string'"
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
        _yci_test_report FAIL "$name" "field '$field': expected='$expected' got='$got'"
    fi
}

assert_json_field_matches() {
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
# Summary — call at the end of every test_*.sh
# ---------------------------------------------------------------------------

summary() {
    if [ "$YCI_TEST_FAIL" -eq 0 ]; then
        printf '  %s: %d passed\n' "$YCI_TEST_FILE" "$YCI_TEST_PASS"
        return 0
    else
        printf '  %s: %d passed, %d FAILED\n' "$YCI_TEST_FILE" "$YCI_TEST_PASS" "$YCI_TEST_FAIL" >&2
        return 1
    fi
}

# Alias matching blast-radius api style
yci_test_summary() {
    summary
}
