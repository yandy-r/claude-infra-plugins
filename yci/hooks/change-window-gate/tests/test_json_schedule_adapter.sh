#!/usr/bin/env bash
# Direct adapter invocations for the json-schedule change-window adapter.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

JSON_CHECK="${CLAUDE_PLUGIN_ROOT}/skills/_shared/change-window-adapters/json-schedule/scripts/check.sh"

BLOCKED_FIXTURE="$(fixture_path "blackout.schedule.json")"
WARNING_FIXTURE="$(fixture_path "warning.schedule.json")"

# ---------------------------------------------------------------------------
# Test: ts inside blackout → blocked with label in rationale
# ---------------------------------------------------------------------------
test_json_ts_blocked() {
    local sb="$1"
    local out rc
    # blackout.schedule.json has blackout 2026-04-22T00:00:00Z to 2026-04-23T00:00:00Z
    out="$("$JSON_CHECK" --ts "2026-04-22T12:00:00Z" --source "$BLOCKED_FIXTURE" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "json blocked: exit 0"
    assert_decision "$out" "blocked" "json blocked: decision=blocked"
    assert_decision_contains "$out" "freeze" "json blocked: label in rationale"
}

# ---------------------------------------------------------------------------
# Test: ts 30 min before blackout → warning
# warning.schedule.json has blackout at 13:00Z; ts 12:30Z is 30 min before
# ---------------------------------------------------------------------------
test_json_ts_warning() {
    local sb="$1"
    local out rc
    out="$("$JSON_CHECK" --ts "2026-04-22T12:30:00Z" --source "$WARNING_FIXTURE" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "json warning: exit 0"
    assert_decision "$out" "warning" "json warning: decision=warning"
    assert_decision_contains "$out" "maintenance" "json warning: label in rationale"
}

# ---------------------------------------------------------------------------
# Test: ts well outside blackout → allowed
# ---------------------------------------------------------------------------
test_json_ts_allowed() {
    local sb="$1"
    local out rc
    # 2026-04-24 is after both blackouts in blackout.schedule.json
    out="$("$JSON_CHECK" --ts "2026-04-24T12:00:00Z" --source "$BLOCKED_FIXTURE" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "json allowed: exit 0"
    assert_decision "$out" "allowed" "json allowed: decision=allowed"
}

# ---------------------------------------------------------------------------
# Test: malformed JSON → exit 2
# ---------------------------------------------------------------------------
test_json_malformed() {
    local sb="$1"
    local bad_json="${sb}/bad.json"
    printf 'not valid json @@@@' > "$bad_json"

    local rc=0
    "$JSON_CHECK" --ts "2026-04-22T12:00:00Z" --source "$bad_json" >/dev/null 2>&1 || rc=$?
    assert_exit 2 "$rc" "json malformed: exit 2"
}

# ---------------------------------------------------------------------------
# Test: missing required 'blackouts' key → exit 2
# ---------------------------------------------------------------------------
test_json_missing_blackouts() {
    local sb="$1"
    local bad_json="${sb}/no-blackouts.json"
    printf '{"timezone":"UTC"}' > "$bad_json"

    local rc=0
    "$JSON_CHECK" --ts "2026-04-22T12:00:00Z" --source "$bad_json" >/dev/null 2>&1 || rc=$?
    assert_exit 2 "$rc" "json missing blackouts: exit 2"
}

# ---------------------------------------------------------------------------
# Test: source file missing → exit 2
# ---------------------------------------------------------------------------
test_json_missing_source() {
    local sb="$1"
    local rc=0
    "$JSON_CHECK" --ts "2026-04-22T12:00:00Z" --source "${sb}/nonexistent.json" >/dev/null 2>&1 || rc=$?
    assert_exit 2 "$rc" "json missing source: exit 2"
}

# ---------------------------------------------------------------------------
with_sandbox test_json_ts_blocked
with_sandbox test_json_ts_warning
with_sandbox test_json_ts_allowed
with_sandbox test_json_malformed
with_sandbox test_json_missing_blackouts
with_sandbox test_json_missing_source

yci_test_summary
