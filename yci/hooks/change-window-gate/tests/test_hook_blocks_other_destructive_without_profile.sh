#!/usr/bin/env bash
# D7 default: no profile + destructive (not init, not artifact) → deny.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# ---------------------------------------------------------------------------
# Test: Bash rm -rf with no profile → deny with cwg-no-profile-destructive-write
# ---------------------------------------------------------------------------
test_rm_no_profile_denied() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles"
    export YCI_DATA_ROOT="$sandbox"
    unset YCI_CUSTOMER YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local payload='{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}'

    local out rc=0
    out="$(printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "rm no profile: exit 0 (deny as JSON)"
    assert_contains "$out" '"permissionDecision": "deny"' "rm no profile: deny json"
    assert_contains "$out" "cwg-no-profile-destructive-write" "rm no profile: rationale"

    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
# Test: Write to /tmp with no profile → deny (destructive, not init, not artifact)
# ---------------------------------------------------------------------------
test_write_tmp_no_profile_denied() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles"
    export YCI_DATA_ROOT="$sandbox"
    unset YCI_CUSTOMER YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local payload='{"tool_name":"Write","tool_input":{"file_path":"/tmp/unrelated.txt"}}'

    local out rc=0
    out="$(printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "write tmp no profile: exit 0 (deny as JSON)"
    assert_contains "$out" '"permissionDecision": "deny"' "write tmp no profile: deny json"
    assert_contains "$out" "cwg-no-profile-destructive-write" "write tmp no profile: rationale"

    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
# Test: kubectl delete with no profile → deny
# ---------------------------------------------------------------------------
test_kubectl_delete_no_profile_denied() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles"
    export YCI_DATA_ROOT="$sandbox"
    unset YCI_CUSTOMER YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local payload='{"tool_name":"Bash","tool_input":{"command":"kubectl delete pod mypod"}}'

    local out rc=0
    out="$(printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "kubectl delete no profile: exit 0"
    assert_contains "$out" '"permissionDecision": "deny"' "kubectl delete no profile: deny json"
    assert_contains "$out" "cwg-no-profile-destructive-write" "kubectl delete no profile: rationale"

    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
with_sandbox test_rm_no_profile_denied
with_sandbox test_write_tmp_no_profile_denied
with_sandbox test_kubectl_delete_no_profile_denied

yci_test_summary
