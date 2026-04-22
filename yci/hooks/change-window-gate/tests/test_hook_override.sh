#!/usr/bin/env bash
# End-to-end: YCI_CWG_OVERRIDE=1 → allow regardless of profile/window state.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

BLOCKED_FIXTURE="$(fixture_path "blocked.ics")"

# ---------------------------------------------------------------------------
# Test: override with ical profile that would block → allow
# ---------------------------------------------------------------------------
test_override_bypasses_ical_block() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles"

    write_profile_yaml "$sandbox" "acme-test" "ical" "$BLOCKED_FIXTURE" "UTC"
    export YCI_DATA_ROOT="$sandbox"
    export YCI_CUSTOMER="acme-test"
    export YCI_CWG_OVERRIDE=1
    unset YCI_CWG_DRY_RUN

    local out rc=0
    out="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"}}' \
        | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "override ical: exit 0"
    assert_eq "$out" "" "override ical: stdout empty (allow)"

    unset YCI_CUSTOMER YCI_CWG_OVERRIDE
    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
# Test: override with none adapter (would block) → allow
# ---------------------------------------------------------------------------
test_override_bypasses_none_block() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles"

    write_profile_yaml "$sandbox" "acme-test" "none"
    export YCI_DATA_ROOT="$sandbox"
    export YCI_CUSTOMER="acme-test"
    export YCI_CWG_OVERRIDE=1
    unset YCI_CWG_DRY_RUN

    local out rc=0
    out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' \
        | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "override none: exit 0"
    assert_eq "$out" "" "override none: stdout empty (allow)"

    unset YCI_CUSTOMER YCI_CWG_OVERRIDE
    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
# Test: override with no active profile + destructive → allow (override wins)
# ---------------------------------------------------------------------------
test_override_bypasses_no_profile() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles"
    export YCI_DATA_ROOT="$sandbox"
    unset YCI_CUSTOMER
    export YCI_CWG_OVERRIDE=1
    unset YCI_CWG_DRY_RUN

    local out rc=0
    out="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"}}' \
        | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "override no profile: exit 0"
    assert_eq "$out" "" "override no profile: stdout empty (allow)"

    unset YCI_CWG_OVERRIDE
    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
with_sandbox test_override_bypasses_ical_block
with_sandbox test_override_bypasses_none_block
with_sandbox test_override_bypasses_no_profile

yci_test_summary
