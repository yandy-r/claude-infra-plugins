#!/usr/bin/env bash
# Direct tests of load-change-window-adapter.sh dispatcher.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

DISPATCHER="${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/load-change-window-adapter.sh"

# ---------------------------------------------------------------------------
# Helper: build a minimal profile JSON for the dispatcher
# ---------------------------------------------------------------------------
_profile_json_with_adapter() {
    local adapter="$1"
    local tmp
    tmp="$(mktemp)"
    python3 -c "
import json, sys
data = {
    'customer': {'id': 'acme-test', 'display_name': 'Acme Test'},
    'engagement': {'id': 'acme-test-eng', 'type': 'implementation',
                   'sow_ref': 'SOW-001', 'scope_tags': ['test'],
                   'start_date': '2026-01-01', 'end_date': '2026-12-31'},
    'compliance': {'regime': 'commercial', 'evidence_schema_version': 1},
    'inventory': {'adapter': 'file'},
    'approval': {'adapter': 'github-pr'},
    'deliverable': {'format': ['markdown'], 'header_template': '/tmp/h.md',
                    'handoff_format': 'git-repo'},
    'safety': {'default_posture': 'review', 'change_window_required': True,
               'scope_enforcement': 'warn'},
    'change_window': {'adapter': sys.argv[1]}
}
print(json.dumps(data))
" "$adapter" > "$tmp"
    printf '%s' "$tmp"
}

# ---------------------------------------------------------------------------
# Test: valid profile with ical adapter → prints adapter directory path, exit 0
# ---------------------------------------------------------------------------
test_dispatcher_valid_ical() {
    local sb="$1"
    local pf rc out
    pf="$(_profile_json_with_adapter "ical")"
    out="$("$DISPATCHER" --profile-json-path "$pf" 2>/dev/null)"; rc=$?
    rm -f "$pf"

    assert_exit 0 "$rc" "dispatcher ical: exit 0"
    assert_contains "$out" "ical" "dispatcher ical: output contains 'ical'"
}

# ---------------------------------------------------------------------------
# Test: valid profile with always-open adapter → exit 0
# ---------------------------------------------------------------------------
test_dispatcher_valid_always_open() {
    local sb="$1"
    local pf rc out
    pf="$(_profile_json_with_adapter "always-open")"
    out="$("$DISPATCHER" --profile-json-path "$pf" 2>/dev/null)"; rc=$?
    rm -f "$pf"

    assert_exit 0 "$rc" "dispatcher always-open: exit 0"
    assert_contains "$out" "always-open" "dispatcher always-open: output contains 'always-open'"
}

# ---------------------------------------------------------------------------
# Test: unknown adapter → exit 2
# ---------------------------------------------------------------------------
test_dispatcher_unknown_adapter() {
    local sb="$1"
    local pf rc
    pf="$(_profile_json_with_adapter "my-unknown-adapter")"
    rc=0
    "$DISPATCHER" --profile-json-path "$pf" >/dev/null 2>&1 || rc=$?
    rm -f "$pf"
    assert_exit 2 "$rc" "dispatcher unknown adapter: exit 2"
}

# ---------------------------------------------------------------------------
# Test: deferred adapter (servicenow-cab) → exit 5 with "deferred" in stderr
# ---------------------------------------------------------------------------
test_dispatcher_deferred_adapter() {
    local sb="$1"
    local pf rc out_err
    pf="$(_profile_json_with_adapter "servicenow-cab")"
    rc=0
    out_err="$("$DISPATCHER" --profile-json-path "$pf" 2>&1 >/dev/null)" || rc=$?
    rm -f "$pf"
    assert_exit 5 "$rc" "dispatcher deferred: exit 5"
    assert_contains "$out_err" "deferred" "dispatcher deferred: 'deferred' in stderr"
}

# ---------------------------------------------------------------------------
# Test: --adapter flag directly (bypasses JSON)
# ---------------------------------------------------------------------------
test_dispatcher_adapter_flag() {
    local sb="$1"
    local rc out
    out="$("$DISPATCHER" --adapter "json-schedule" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "dispatcher --adapter flag: exit 0"
    assert_contains "$out" "json-schedule" "dispatcher --adapter flag: output contains adapter"
}

# ---------------------------------------------------------------------------
# Test: --export flag emits shell export lines
# ---------------------------------------------------------------------------
test_dispatcher_export_flag() {
    local sb="$1"
    local pf rc out
    pf="$(_profile_json_with_adapter "none")"
    out="$("$DISPATCHER" --profile-json-path "$pf" --export 2>/dev/null)"; rc=$?
    rm -f "$pf"
    assert_exit 0 "$rc" "dispatcher --export: exit 0"
    assert_contains "$out" "YCI_CW_ADAPTER_DIR" "dispatcher --export: emits YCI_CW_ADAPTER_DIR"
    assert_contains "$out" "YCI_CW_ADAPTER_NAME" "dispatcher --export: emits YCI_CW_ADAPTER_NAME"
}

# ---------------------------------------------------------------------------
with_sandbox test_dispatcher_valid_ical
with_sandbox test_dispatcher_valid_always_open
with_sandbox test_dispatcher_unknown_adapter
with_sandbox test_dispatcher_deferred_adapter
with_sandbox test_dispatcher_adapter_flag
with_sandbox test_dispatcher_export_flag

yci_test_summary
