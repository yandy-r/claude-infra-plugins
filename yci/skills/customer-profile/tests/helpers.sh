#!/usr/bin/env bash
# Shared test helpers. Source this file from every test_*.sh.
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

if cd "${_HELPERS_DIR}/../../_shared/scripts" 2>/dev/null; then
    YCI_SHARED_DIR="$(pwd -P)"
    cd "${_HELPERS_DIR}" || true
else
    YCI_SHARED_DIR="${_HELPERS_DIR}/../../_shared/scripts"
fi
export YCI_SHARED_DIR

if cd "${_HELPERS_DIR}/../references" 2>/dev/null; then
    YCI_REFS_DIR="$(pwd -P)"
    cd "${_HELPERS_DIR}" || true
else
    YCI_REFS_DIR="${_HELPERS_DIR}/../references"
fi
export YCI_REFS_DIR

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
    # Assert that the given file (or string piped to python) is valid JSON.
    local path="$1" name="${2:-assert_json_valid}"
    if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$path" 2>/dev/null; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "invalid JSON in: $path"
    fi
}

assert_error_id() {
    # Match emitted stderr against the canonical message for <id> in error-messages.md.
    # Matching is lenient: we check that a distinctive phrase from the catalog appears.
    local id="$1" stderr_content="$2" name="${3:-assert_error_id}"
    local refs_md="${YCI_REFS_DIR}/error-messages.md"
    if [ ! -f "$refs_md" ]; then
        _yci_test_report FAIL "$name" "error-messages.md not found at $refs_md"
        return
    fi
    # Extract the first code-block line inside the entry for this id.
    local phrase
    phrase="$(awk -v id="$id" '
        /^### `/ { in_id = ($0 ~ id) ? 1 : 0 }
        in_id && /^- \*\*ID\*\*:/ { found_id=1 }
        found_id && /^```$/ { in_block=!in_block; next }
        found_id && in_block { print; exit }
    ' "$refs_md" | sed 's/[<>].*//' | head -1 | tr -d '\n')"
    if [ -z "$phrase" ]; then
        _yci_test_report FAIL "$name" "error catalog has no extractable phrase for id '$id'"
        return
    fi
    case "$stderr_content" in
        *"$phrase"*) _yci_test_report PASS "$name" ;;
        *)           _yci_test_report FAIL "$name" "expected phrase '$phrase' not in stderr for id '$id'" ;;
    esac
}

# ---------------------------------------------------------------------------
# Sandbox helper
# ---------------------------------------------------------------------------

with_sandbox() {
    # Usage: with_sandbox <fn-name>
    # Calls <fn-name> with the sandbox path as its first argument. Runs in the
    # CURRENT shell (not a subshell) so that assertion counters
    # YCI_TEST_PASS / YCI_TEST_FAIL propagate to yci_test_summary. Save/restore
    # HOME, YCI_DATA_ROOT, YCI_CUSTOMER, and the working directory around the
    # call so cross-test state never leaks.
    local fn="$1"
    local sb
    sb="$(mktemp -d -t yci-test-XXXXXX)"
    mkdir -p "$sb/real" "$sb/home" "$sb/cwd"

    # Save previous env + cwd (use +x for "was the var set at all" vs. empty).
    local saved_home="${HOME:-}"
    local saved_dr_set=${YCI_DATA_ROOT+x} saved_dr="${YCI_DATA_ROOT:-}"
    local saved_cu_set=${YCI_CUSTOMER+x}  saved_cu="${YCI_CUSTOMER:-}"
    local saved_cwd; saved_cwd="$(pwd -P)"

    export YCI_TEST_SANDBOX="$sb"
    export HOME="$sb/home"
    export YCI_DATA_ROOT=""
    export YCI_CUSTOMER=""

    local rc=0
    if cd "$sb/cwd"; then
        "$fn" "$sb" || rc=$?
    else
        rc=1
    fi

    # Restore cwd first (so cleanup doesn't delete the CWD out from under us).
    cd "$saved_cwd" || true

    # Restore env vars to their prior state (set vs. unset vs. value).
    export HOME="$saved_home"
    if [ -n "$saved_dr_set" ]; then export YCI_DATA_ROOT="$saved_dr"; else unset YCI_DATA_ROOT; fi
    if [ -n "$saved_cu_set" ]; then export YCI_CUSTOMER="$saved_cu";  else unset YCI_CUSTOMER; fi

    rm -rf "$sb"
    unset YCI_TEST_SANDBOX
    return "$rc"
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
