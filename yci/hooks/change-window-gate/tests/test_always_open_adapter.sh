#!/usr/bin/env bash
# Tests for the always-open change-window adapter.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ALWAYS_OPEN_CHECK="${CLAUDE_PLUGIN_ROOT}/skills/_shared/change-window-adapters/always-open/scripts/check.sh"

# ---------------------------------------------------------------------------
# Test: always allows regardless of ts
# ---------------------------------------------------------------------------
test_always_open_past() {
    local out rc
    out="$("$ALWAYS_OPEN_CHECK" --ts "2020-01-01T00:00:00Z" --source "" --timezone "UTC" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "always-open past: exit 0"
    assert_decision "$out" "allowed" "always-open past: decision=allowed"
}

test_always_open_future() {
    local out rc
    out="$("$ALWAYS_OPEN_CHECK" --ts "2035-12-31T23:59:59Z" --source "" --timezone "UTC" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "always-open future: exit 0"
    assert_decision "$out" "allowed" "always-open future: decision=allowed"
}

test_always_open_no_flags() {
    local out rc
    out="$("$ALWAYS_OPEN_CHECK" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "always-open no flags: exit 0"
    assert_decision "$out" "allowed" "always-open no flags: decision=allowed"
}

# ---------------------------------------------------------------------------
with_sandbox test_always_open_past
with_sandbox test_always_open_future
with_sandbox test_always_open_no_flags

yci_test_summary
