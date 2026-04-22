#!/usr/bin/env bash
# End-to-end: ical profile + blocked.ics + destructive → deny with blackout rationale.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

BLOCKED_FIXTURE="$(fixture_path "blocked.ics")"

# ---------------------------------------------------------------------------
# Test: Bash rm -rf with ical profile + blocked window → deny
# Uses YCI_CUSTOMER envvar to activate the profile (Tier 1).
# ---------------------------------------------------------------------------
test_destructive_in_blackout_denied() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles"

    # Write a profile pointing to the blocked.ics fixture
    write_profile_yaml "$sandbox" "acme-test" "ical" "$BLOCKED_FIXTURE" "UTC"
    export YCI_DATA_ROOT="$sandbox"
    export YCI_CUSTOMER="acme-test"
    unset YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local payload='{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}'

    local out rc=0
    out="$(printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "blackout destructive: exit 0 (deny as JSON)"
    assert_contains "$out" '"permissionDecision": "deny"' "blackout destructive: deny json"
    assert_contains "$out" "cwg-destructive-in-blackout" "blackout destructive: rationale prefix"
    assert_contains "$out" "Production freeze" "blackout destructive: SUMMARY in rationale"

    unset YCI_CUSTOMER
    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
# Test: Write with ical profile + blocked window → deny
# ---------------------------------------------------------------------------
test_write_in_blackout_denied() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles"

    write_profile_yaml "$sandbox" "acme-test" "ical" "$BLOCKED_FIXTURE" "UTC"
    export YCI_DATA_ROOT="$sandbox"
    export YCI_CUSTOMER="acme-test"
    unset YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local payload='{"tool_name":"Write","tool_input":{"file_path":"/tmp/output.txt"}}'

    local out rc=0
    out="$(printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "blackout write: exit 0 (deny as JSON)"
    assert_contains "$out" '"permissionDecision": "deny"' "blackout write: deny json"
    assert_contains "$out" "cwg-destructive-in-blackout" "blackout write: rationale prefix"

    unset YCI_CUSTOMER
    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
with_sandbox test_destructive_in_blackout_denied
with_sandbox test_write_in_blackout_denied

yci_test_summary
