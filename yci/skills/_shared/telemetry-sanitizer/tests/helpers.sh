#!/usr/bin/env bash
# Shared helpers for telemetry-sanitizer tests.

YCI_TEST_PASS=0
YCI_TEST_FAIL=0

_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
YCI_TELEMETRY_SCRIPTS_DIR="$(cd "${_HELPERS_DIR}/../scripts" && pwd -P)"
export YCI_TELEMETRY_SCRIPTS_DIR
YCI_PLUGIN_ROOT="$(cd "${_HELPERS_DIR}/../../../.." && pwd -P)"
export YCI_PLUGIN_ROOT

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
        *"$needle"*) _yci_test_report FAIL "$name" "unexpected '$needle' in output" ;;
        *)           _yci_test_report PASS "$name" ;;
    esac
}
