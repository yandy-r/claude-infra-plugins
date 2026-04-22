#!/usr/bin/env bash
# End-to-end: YCI_CWG_DRY_RUN=1 with blocking profile → allow + [DRY-RUN-BLOCKED] + audit log.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

BLOCKED_FIXTURE="$(fixture_path "blocked.ics")"

# ---------------------------------------------------------------------------
# Test: dry-run mode with ical profile that would block
# ---------------------------------------------------------------------------
test_dry_run_allows_and_logs() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles" "${sandbox}/logs"

    write_profile_yaml "$sandbox" "acme-test" "ical" "$BLOCKED_FIXTURE" "UTC"
    export YCI_DATA_ROOT="$sandbox"
    export YCI_CUSTOMER="acme-test"
    export YCI_CWG_DRY_RUN=1
    unset YCI_CWG_OVERRIDE

    local payload='{"tool_name":"Write","tool_input":{"file_path":"/tmp/output.txt"}}'

    local out_file err_file rc=0
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" \
        >"$out_file" 2>"$err_file" || rc=$?

    local out err
    out="$(< "$out_file")"
    err="$(< "$err_file")"
    rm -f "$out_file" "$err_file"

    assert_exit 0 "$rc" "dry-run: exit 0 (allow)"
    assert_eq "$out" "" "dry-run: stdout empty (allow)"
    assert_contains "$err" "[DRY-RUN-BLOCKED]" "dry-run: stderr has [DRY-RUN-BLOCKED] banner"

    # Audit log should have been created
    local audit_log="${sandbox}/logs/change-window-gate.audit.log"
    assert_file_exists "$audit_log" "dry-run: audit log created"

    local log_content
    log_content="$(< "$audit_log")"
    assert_contains "$log_content" "dry-run-blocked" "dry-run: audit log has dry-run-blocked entry"

    unset YCI_CUSTOMER YCI_CWG_DRY_RUN
    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
# Test: dry-run with none adapter (always blocked without override) → allow
# ---------------------------------------------------------------------------
test_dry_run_none_adapter() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles" "${sandbox}/logs"

    write_profile_yaml "$sandbox" "acme-test" "none"
    export YCI_DATA_ROOT="$sandbox"
    export YCI_CUSTOMER="acme-test"
    export YCI_CWG_DRY_RUN=1
    unset YCI_CWG_OVERRIDE

    local payload='{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}'

    local out_file err_file rc=0
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" \
        >"$out_file" 2>"$err_file" || rc=$?

    local out err
    out="$(< "$out_file")"
    err="$(< "$err_file")"
    rm -f "$out_file" "$err_file"

    assert_exit 0 "$rc" "dry-run none: exit 0"
    assert_eq "$out" "" "dry-run none: stdout empty (allow)"
    assert_contains "$err" "[DRY-RUN-BLOCKED]" "dry-run none: stderr has [DRY-RUN-BLOCKED]"

    unset YCI_CUSTOMER YCI_CWG_DRY_RUN
    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
with_sandbox test_dry_run_allows_and_logs
with_sandbox test_dry_run_none_adapter

yci_test_summary
