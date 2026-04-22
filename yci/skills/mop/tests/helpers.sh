#!/usr/bin/env bash
# Shared test helpers for yci:mop tests.

set -euo pipefail

YCI_TEST_PASS=0
YCI_TEST_FAIL=0
YCI_TEST_FILE="${BASH_SOURCE[1]##*/}"

_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_ROOT="$(cd "${_HELPERS_DIR}/.." && pwd -P)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${_HELPERS_DIR}/../../.." && pwd -P)}"
FIXTURES_ROOT="${_HELPERS_DIR}/fixtures"

export SKILL_ROOT
export PLUGIN_ROOT
export FIXTURES_ROOT

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

assert_contains() {
    local substring="$1" haystack="$2" name="${3:-assert_contains}"
    case "$haystack" in
        *"$substring"*) _yci_test_report PASS "$name" ;;
        *) _yci_test_report FAIL "$name" "'$substring' not found" ;;
    esac
}

assert_equals() {
    local expected="$1" actual="$2" name="${3:-assert_equals}"
    if [ "$expected" = "$actual" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "expected='$expected' actual='$actual'"
    fi
}

assert_exit_code() {
    local expected="$1" actual="$2" name="${3:-assert_exit_code}"
    if [ "$expected" = "$actual" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "expected exit=$expected actual=$actual"
    fi
}

assert_file_exists() {
    local path="$1" name="${2:-assert_file_exists}"
    if [ -f "$path" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "missing file: $path"
    fi
}

assert_json_field() {
    local json_str="$1" field="$2" expected="$3" name="${4:-assert_json_field}"
    local got
    got="$(python3 - "$json_str" "$field" <<'PYEOF'
import json, sys
doc = json.loads(sys.argv[1])
print(doc.get(sys.argv[2], ""))
PYEOF
)"
    assert_equals "$expected" "$got" "$name"
}

summary() {
    if [ "$YCI_TEST_FAIL" -eq 0 ]; then
        printf '  %s: %d passed\n' "$YCI_TEST_FILE" "$YCI_TEST_PASS"
        return 0
    else
        printf '  %s: %d passed, %d FAILED\n' "$YCI_TEST_FILE" "$YCI_TEST_PASS" "$YCI_TEST_FAIL" >&2
        return 1
    fi
}
