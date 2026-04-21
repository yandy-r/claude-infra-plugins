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
# test_non_yci_payload_allowed: customer checks are yci-only. A generic payload
# with no yci markers/paths should pass through even when no customer is active.
#
# with_sandbox sets YCI_CUSTOMER="" (empty). resolve-customer.sh treats
# empty/whitespace-only YCI_CUSTOMER as "set but empty" and falls through to
# Tier 2 (dotfile walk) and Tier 3 (state.json), both of which also fail in
# the clean sandbox. The guard must still ALLOW because the payload is not yci.
# ---------------------------------------------------------------------------
test_non_yci_payload_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "non_yci_allow: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"
    # YCI_CUSTOMER is already "" per with_sandbox; leave it empty.

    local payload='{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'

    local stdout stderr rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/tmp/yci-test-fc-stderr-$$)"; rc=$?
    stderr="$(cat /tmp/yci-test-fc-stderr-$$ 2>/dev/null)"; rm -f /tmp/yci-test-fc-stderr-$$

    assert_exit 0 "$rc" "non_yci_allow: exit 0"
    assert_eq "$stdout" "" "non_yci_allow: stdout empty (allow)"
    assert_eq "$stderr" "" "non_yci_allow: stderr empty"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# test_yci_no_active_denied: yci calls still fail-closed by default when a
# customer is required and the payload is not a bootstrap init/switch flow.
# ---------------------------------------------------------------------------
test_yci_no_active_denied() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_no_active_denied: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"
    local payload='{"tool_name":"Skill","tool_input":{"command":"/yci:guard-check /tmp/x"}}'

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_no_active_denied: exit 0 (deny emitted as JSON)"
    assert_contains "$stdout" '"permissionDecision": "deny"' "yci_no_active_denied: decision=deny"
    assert_contains "$stdout" "no active customer" "yci_no_active_denied: reason mentions no active customer"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# test_yci_fail_open_env: YCI_GUARD_FAIL_OPEN=1 with no active customer allows
# a yci call that would otherwise deny.
# ---------------------------------------------------------------------------
test_yci_fail_open_env() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_fail_open: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"
    local YCI_GUARD_FAIL_OPEN=1
    export YCI_GUARD_FAIL_OPEN

    local payload='{"tool_name":"Skill","tool_input":{"command":"/yci:guard-check /tmp/x"}}'

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_fail_open: exit 0"
    assert_eq "$stdout" "" "yci_fail_open: stdout empty (allow with YCI_GUARD_FAIL_OPEN=1)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED YCI_GUARD_FAIL_OPEN
}

# ---------------------------------------------------------------------------
test_yci_skill_bootstrap_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_skill_bootstrap: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local payload='{"tool_name":"Skill","tool_input":{"command":"/yci:init itcn"}}'

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_skill_bootstrap: exit 0"
    assert_eq "$stdout" "" "yci_skill_bootstrap: stdout empty (allow)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
test_yci_bash_bootstrap_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_bash_bootstrap: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local cmd="bash ${REPO_ROOT}/yci/skills/customer-profile/scripts/init-profile.sh ${data} itcn"
    local payload
    payload="$(python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$cmd")"

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_bash_bootstrap: exit 0"
    assert_eq "$stdout" "" "yci_bash_bootstrap: stdout empty (allow)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
test_ycc_skill_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "ycc_skill_allowed: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local payload='{"tool_name":"Skill","tool_input":{"command":"/ycc:deep-research modernize ITCN"}}'

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "ycc_skill_allowed: exit 0"
    assert_eq "$stdout" "" "ycc_skill_allowed: stdout empty (allow)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
with_sandbox test_non_yci_payload_allowed
with_sandbox test_yci_no_active_denied
with_sandbox test_yci_fail_open_env
with_sandbox test_yci_skill_bootstrap_allowed
with_sandbox test_yci_bash_bootstrap_allowed
with_sandbox test_ycc_skill_allowed

yci_test_summary
