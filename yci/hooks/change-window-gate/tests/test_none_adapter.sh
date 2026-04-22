#!/usr/bin/env bash
# Tests for the none change-window adapter.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

NONE_CHECK="${CLAUDE_PLUGIN_ROOT}/skills/_shared/change-window-adapters/none/scripts/check.sh"

# ---------------------------------------------------------------------------
# Test: default → blocked (no override, no flags)
# ---------------------------------------------------------------------------
test_none_default_blocked() {
    local sb="$1"
    unset YCI_CWG_OVERRIDE
    local out rc
    out="$("$NONE_CHECK" --ts "2026-04-22T12:00:00Z" --timezone "UTC" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "none default: exit 0"
    assert_decision "$out" "blocked" "none default: decision=blocked"
    assert_decision_contains "$out" "override required" "none default: rationale mentions override"
}

# ---------------------------------------------------------------------------
# Test: YCI_CWG_OVERRIDE=1 → allowed
# ---------------------------------------------------------------------------
test_none_override_allowed() {
    local sb="$1"
    local out rc
    out="$(YCI_CWG_OVERRIDE=1 "$NONE_CHECK" --ts "2026-04-22T12:00:00Z" --timezone "UTC" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "none override: exit 0"
    assert_decision "$out" "allowed" "none override: decision=allowed"
}

# ---------------------------------------------------------------------------
# Test: no flags at all → blocked (override not set)
# ---------------------------------------------------------------------------
test_none_no_flags_blocked() {
    local sb="$1"
    unset YCI_CWG_OVERRIDE
    local out rc
    out="$("$NONE_CHECK" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "none no flags: exit 0"
    assert_decision "$out" "blocked" "none no flags: decision=blocked"
}

# ---------------------------------------------------------------------------
# Test: with --source flag (source is accepted but ignored) → blocked
# ---------------------------------------------------------------------------
test_none_with_source_blocked() {
    local sb="$1"
    unset YCI_CWG_OVERRIDE
    local dummy_source="${sb}/dummy.ics"
    printf '' > "$dummy_source"
    local out rc
    out="$("$NONE_CHECK" --ts "2026-04-22T12:00:00Z" --source "$dummy_source" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "none with source: exit 0"
    assert_decision "$out" "blocked" "none with source: decision=blocked"
}

# ---------------------------------------------------------------------------
with_sandbox test_none_default_blocked
with_sandbox test_none_override_allowed
with_sandbox test_none_no_flags_blocked
with_sandbox test_none_with_source_blocked

yci_test_summary
