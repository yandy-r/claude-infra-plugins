#!/usr/bin/env bash
set -euo pipefail

YCI_TEST_PASS=0
YCI_TEST_FAIL=0
YCI_TEST_FILE="${BASH_SOURCE[1]##*/}"

HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_ROOT="$(cd "${HELPERS_DIR}/.." && pwd -P)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${HELPERS_DIR}/../../.." && pwd -P)}"
SCRIPTS_DIR="${SKILL_ROOT}/scripts"
FIXTURES_DIR="${HELPERS_DIR}/fixtures"

export SKILL_ROOT PLUGIN_ROOT SCRIPTS_DIR FIXTURES_DIR

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
        [ -n "$detail" ] && printf '    %s\n' "$detail" >&2
    fi
}

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
        *) _yci_test_report FAIL "$name" "'$needle' not found" ;;
    esac
}

assert_file_exists() {
    local path="$1" name="${2:-assert_file_exists}"
    if [ -f "$path" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "file missing: $path"
    fi
}

assert_exit() {
    local expected="$1" got="$2" name="${3:-assert_exit}"
    if [ "$expected" = "$got" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "expected exit $expected got $got"
    fi
}

yci_test_summary() {
    if [ "$YCI_TEST_FAIL" -eq 0 ]; then
        printf '  %s: %d passed\n' "$YCI_TEST_FILE" "$YCI_TEST_PASS"
        return 0
    fi
    printf '  %s: %d passed, %d FAILED\n' "$YCI_TEST_FILE" "$YCI_TEST_PASS" "$YCI_TEST_FAIL" >&2
    return 1
}
