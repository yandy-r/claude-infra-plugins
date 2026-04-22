#!/usr/bin/env bash
# Unit tests for cwg_decide (window-decision.sh).
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

BLOCKED_FIXTURE="$(fixture_path "blocked.ics")"
export CLAUDE_PLUGIN_ROOT

# Source window-decision library
# shellcheck source=../scripts/window-decision.sh
source "${YCI_CWG_SCRIPTS_DIR}/window-decision.sh"

# ---------------------------------------------------------------------------
# Helper: create a profile JSON file from a YAML profile
# write_profile_json <sandbox> <customer-id> <adapter> [source] → prints json path
# ---------------------------------------------------------------------------
_make_profile_json() {
    local sandbox="$1" customer_id="$2" adapter="$3" source="${4:-}"
    local json_path
    json_path="$(mktemp "${sandbox}/profile-XXXXXX.json")"

    write_profile_yaml "$sandbox" "$customer_id" "$adapter" "$source"
    bash "${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/load-profile.sh" \
        "$sandbox" "$customer_id" > "$json_path" 2>/dev/null
    printf '%s' "$json_path"
}

# ---------------------------------------------------------------------------
# Test: YCI_CWG_OVERRIDE=1 → allowed with adapter="override"
# ---------------------------------------------------------------------------
test_override_short_circuit() {
    local sb="$1"
    local data="${sb}/data"
    mkdir -p "${data}/profiles"

    export YCI_CWG_OVERRIDE=1
    local pf
    pf="$(_make_profile_json "$data" "acme-test" "none")"
    local result
    result="$(cwg_decide "$pf")"
    assert_decision "$result" "allowed" "override: decision=allowed"
    assert_decision_contains "$result" "override" "override: adapter=override"
    unset YCI_CWG_OVERRIDE

    teardown_test_sandbox "$data"
}

# ---------------------------------------------------------------------------
# Test: always-open adapter → allowed
# ---------------------------------------------------------------------------
test_always_open_allowed() {
    local sb="$1"
    local data="${sb}/data"
    mkdir -p "${data}/profiles"

    unset YCI_CWG_OVERRIDE
    local pf
    pf="$(_make_profile_json "$data" "widgetco-test" "always-open")"
    local result
    result="$(cwg_decide "$pf" "2026-04-22T12:00:00Z")"
    assert_decision "$result" "allowed" "always-open: decision=allowed"
    assert_decision_contains "$result" "always-open" "always-open: adapter name"

    teardown_test_sandbox "$data"
}

# ---------------------------------------------------------------------------
# Test: none adapter without override → blocked
# ---------------------------------------------------------------------------
test_none_adapter_blocked() {
    local sb="$1"
    local data="${sb}/data"
    mkdir -p "${data}/profiles"

    unset YCI_CWG_OVERRIDE
    local pf
    pf="$(_make_profile_json "$data" "acme-test" "none")"
    local result
    result="$(cwg_decide "$pf" "2026-04-22T12:00:00Z")"
    assert_decision "$result" "blocked" "none: decision=blocked"
    assert_decision_contains "$result" "none" "none: adapter name"

    teardown_test_sandbox "$data"
}

# ---------------------------------------------------------------------------
# Test: ical adapter with blocked.ics → blocked
# ---------------------------------------------------------------------------
test_ical_blocked() {
    local sb="$1"
    local data="${sb}/data"
    mkdir -p "${data}/profiles"

    unset YCI_CWG_OVERRIDE
    local pf
    pf="$(_make_profile_json "$data" "acme-test" "ical" "$BLOCKED_FIXTURE")"
    local result
    result="$(cwg_decide "$pf" "2026-04-22T12:00:00Z")"
    assert_decision "$result" "blocked" "ical blocked: decision=blocked"
    assert_decision_contains "$result" "Production freeze" "ical blocked: rationale has SUMMARY"

    teardown_test_sandbox "$data"
}

# ---------------------------------------------------------------------------
# Test: json-schedule adapter with blackout fixture → blocked
# ---------------------------------------------------------------------------
test_json_blocked() {
    local sb="$1"
    local data="${sb}/data"
    local json_fixture
    json_fixture="$(fixture_path "blackout.schedule.json")"
    mkdir -p "${data}/profiles"

    unset YCI_CWG_OVERRIDE
    local pf
    pf="$(_make_profile_json "$data" "widgetco-test" "json-schedule" "$json_fixture")"
    local result
    result="$(cwg_decide "$pf" "2026-04-22T12:00:00Z")"
    assert_decision "$result" "blocked" "json blocked: decision=blocked"
    assert_decision_contains "$result" "freeze" "json blocked: rationale has label"

    teardown_test_sandbox "$data"
}

# ---------------------------------------------------------------------------
# Test: missing profile file → blocked with profile-load-error
# ---------------------------------------------------------------------------
test_missing_profile_blocked() {
    local sb="$1"
    local data="${sb}/data"
    mkdir -p "${data}/profiles"

    unset YCI_CWG_OVERRIDE
    local nonexistent="${data}/profiles/nonexistent.json"
    local result
    result="$(cwg_decide "$nonexistent" "2026-04-22T12:00:00Z")"
    assert_decision "$result" "blocked" "missing profile: decision=blocked"
    # The dispatcher will fail because it can't read the file
    assert_decision_contains "$result" "cwg-adapter-load-failed" "missing profile: load error in rationale"

    teardown_test_sandbox "$data"
}

# ---------------------------------------------------------------------------
# Test: deferred adapter servicenow-cab → blocked with adapter-load-failed
# ---------------------------------------------------------------------------
test_deferred_adapter_blocked() {
    local sb="$1"
    local data="${sb}/data"
    mkdir -p "${data}/profiles"

    unset YCI_CWG_OVERRIDE
    local pf
    pf="$(_make_profile_json "$data" "acme-test" "servicenow-cab")"
    local result
    result="$(cwg_decide "$pf" "2026-04-22T12:00:00Z")"
    assert_decision "$result" "blocked" "deferred adapter: decision=blocked"
    assert_decision_contains "$result" "adapter-load-failed" "deferred adapter: load-failed in rationale"

    teardown_test_sandbox "$data"
}

# ---------------------------------------------------------------------------
with_sandbox test_override_short_circuit
with_sandbox test_always_open_allowed
with_sandbox test_none_adapter_blocked
with_sandbox test_ical_blocked
with_sandbox test_json_blocked
with_sandbox test_missing_profile_blocked
with_sandbox test_deferred_adapter_blocked

yci_test_summary
