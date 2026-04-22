#!/usr/bin/env bash
# D7: no active profile + write to artifacts/ → deny with cwg-no-profile-cannot-create.
#
# Note: the artifact-creation deny only fires for calls that are BOTH:
#   (a) classified as destructive by cwg_is_destructive, AND
#   (b) classified as artifact-creation by cwg_is_artifact_creation.
# Write/Edit tool calls to artifacts/ satisfy both conditions.
# Bash commands with read-only verbs (echo, printf) are non-destructive and
# allow silently — they never reach the D7 branch.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# ---------------------------------------------------------------------------
# Test: Write to artifacts/ with no profile → deny
# ---------------------------------------------------------------------------
test_write_to_artifacts_denied() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles" "${sandbox}/artifacts"
    export YCI_DATA_ROOT="$sandbox"
    unset YCI_CUSTOMER YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local artifact_path="${sandbox}/artifacts/report.md"
    local payload
    payload="$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Write','tool_input':{'file_path':sys.argv[1]}}))" "$artifact_path")"

    local out rc=0
    out="$(printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "artifact no profile: exit 0 (deny as JSON)"
    assert_contains "$out" '"permissionDecision": "deny"' "artifact no profile: deny json"
    assert_contains "$out" "cwg-no-profile-cannot-create" "artifact no profile: rationale"

    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
# Test: Edit to artifacts/ with no profile → deny
# ---------------------------------------------------------------------------
test_edit_to_artifacts_denied() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles" "${sandbox}/artifacts"
    export YCI_DATA_ROOT="$sandbox"
    unset YCI_CUSTOMER YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local artifact_path="${sandbox}/artifacts/notes.md"
    local payload
    payload="$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Edit','tool_input':{'file_path':sys.argv[1]}}))" "$artifact_path")"

    local out rc=0
    out="$(printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "artifact edit no profile: exit 0 (deny as JSON)"
    assert_contains "$out" '"permissionDecision": "deny"' "artifact edit no profile: deny json"
    assert_contains "$out" "cwg-no-profile-cannot-create" "artifact edit no profile: rationale"

    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
# Test: Bash with echo (read-only verb) redirecting to artifacts/ with no profile
# → allow silently (echo is non-destructive; hook exits at step 4)
# The artifact-creation deny only fires for destructive Bash operations.
# ---------------------------------------------------------------------------
test_bash_readonly_redirect_artifacts_allows() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles" "${sandbox}/artifacts"
    export YCI_DATA_ROOT="$sandbox"
    unset YCI_CUSTOMER YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    # echo is in CWG_READONLY_VERBS, so the entire Bash call is non-destructive.
    # The hook never reaches the D7 artifact-creation check.
    local cmd="echo hello >${sandbox}/artifacts/output.txt"
    local payload
    payload="$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]}}))" "$cmd")"

    local out rc=0
    out="$(printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "echo redirect artifacts: exit 0 (non-destructive allows)"
    assert_eq "$out" "" "echo redirect artifacts: stdout empty (allow silently)"

    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
with_sandbox test_write_to_artifacts_denied
with_sandbox test_edit_to_artifacts_denied
with_sandbox test_bash_readonly_redirect_artifacts_allows

yci_test_summary
