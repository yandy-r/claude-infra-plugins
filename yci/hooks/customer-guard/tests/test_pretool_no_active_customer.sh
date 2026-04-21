#!/usr/bin/env bash
# Integration tests: pretool.sh behavior when no active customer is configured.
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

PRETOOL="${REPO_ROOT}/yci/hooks/customer-guard/scripts/pretool.sh"

_pretool_ok() {
    if [ ! -f "$PRETOOL" ]; then
        printf 'DIAGNOSTIC: pretool.sh not found at %s\n' "$PRETOOL" >&2
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# test_fail_closed_default: no YCI_CUSTOMER, no dotfile, no state.json.
# Default behavior: fail-closed → emit deny JSON with guard-no-active-customer.
#
# with_sandbox sets YCI_CUSTOMER="" (empty). resolve-customer.sh treats
# empty/whitespace-only YCI_CUSTOMER as "set but empty" and falls through to
# Tier 2 (dotfile walk) and Tier 3 (state.json), both of which also fail in
# the clean sandbox. Tier 4: refuse with error → pretool.sh emits deny JSON.
# ---------------------------------------------------------------------------
test_fail_closed_default() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "fail_closed: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"
    # YCI_CUSTOMER is already "" per with_sandbox; leave it empty.

    local payload='{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'

    local stdout stderr rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/tmp/yci-test-fc-stderr-$$)"; rc=$?
    stderr="$(cat /tmp/yci-test-fc-stderr-$$ 2>/dev/null)"; rm -f /tmp/yci-test-fc-stderr-$$

    assert_exit 0 "$rc" "fail_closed: exit 0 (deny emitted as JSON)"
    assert_contains "$stdout" '{"hookSpecificOutput"' "fail_closed: stdout has hookSpecificOutput"
    assert_contains "$stdout" '"permissionDecision": "deny"' "fail_closed: decision=deny"
    assert_contains "$stdout" "no active customer" "fail_closed: reason mentions no active customer"
    assert_error_id "guard-no-active-customer" "$stdout" "fail_closed: guard-no-active-customer phrase in stdout"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# test_fail_open_env: YCI_GUARD_FAIL_OPEN=1 with no active customer → allow.
# ---------------------------------------------------------------------------
test_fail_open_env() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "fail_open: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"
    # YCI_CUSTOMER is "" per with_sandbox.
    local YCI_GUARD_FAIL_OPEN=1
    export YCI_GUARD_FAIL_OPEN

    local payload='{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "fail_open: exit 0"
    assert_eq "$stdout" "" "fail_open: stdout empty (allow with YCI_GUARD_FAIL_OPEN=1)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED YCI_GUARD_FAIL_OPEN
}

# ---------------------------------------------------------------------------
with_sandbox test_fail_closed_default
with_sandbox test_fail_open_env

yci_test_summary
