#!/usr/bin/env bash
# D7: no active profile + init path → exit 0 + stderr advisory.
# Read-only tools still allow silently; init-class package-manager commands and
# writes to profiles/ produce the documented advisory.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# ---------------------------------------------------------------------------
# Test: Write to profiles/ with no profile → allow + stderr advisory
# Write is destructive; writing to profiles/ is init-class → D7 advisory fires.
# ---------------------------------------------------------------------------
test_write_to_profiles_allowed() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles"
    export YCI_DATA_ROOT="$sandbox"
    # Ensure no customer is active
    unset YCI_CUSTOMER YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local profile_write_path="${sandbox}/profiles/acme-test.yaml"
    local payload
    payload="$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Write','tool_input':{'file_path':sys.argv[1]}}))" "$profile_write_path")"

    local out_file err_file rc=0
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" \
        >"$out_file" 2>"$err_file" || rc=$?

    local out err
    out="$(< "$out_file")"
    err="$(< "$err_file")"
    rm -f "$out_file" "$err_file"

    assert_exit 0 "$rc" "init write profiles: exit 0"
    assert_eq "$out" "" "init write profiles: stdout empty (allow)"
    assert_contains "$err" "allowing init-class" "init write profiles: stderr advisory"

    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
# Test: Edit to profiles/ with no profile → allow + stderr advisory
# Edit is destructive; writing to profiles/ is init-class → D7 advisory fires.
# ---------------------------------------------------------------------------
test_edit_profiles_allowed() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles"
    export YCI_DATA_ROOT="$sandbox"
    unset YCI_CUSTOMER YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local profile_path="${sandbox}/profiles/acme-test.yaml"
    local payload
    payload="$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Edit','tool_input':{'file_path':sys.argv[1]}}))" "$profile_path")"

    local out_file err_file rc=0
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" \
        >"$out_file" 2>"$err_file" || rc=$?

    local out err
    out="$(< "$out_file")"
    err="$(< "$err_file")"
    rm -f "$out_file" "$err_file"

    assert_exit 0 "$rc" "init edit profiles: exit 0"
    assert_eq "$out" "" "init edit profiles: stdout empty (allow)"
    assert_contains "$err" "allowing init-class" "init edit profiles: stderr advisory"

    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
# Test: Bash npm install with no profile → allow + stderr advisory.
# Package-manager commands are init-class when no profile is active, so they
# should produce the same advisory path as profile scaffolding.
# ---------------------------------------------------------------------------
test_bash_npm_install_allowed_with_advisory() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles"
    export YCI_DATA_ROOT="$sandbox"
    unset YCI_CUSTOMER YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local payload='{"tool_name":"Bash","tool_input":{"command":"npm install"}}'

    local out_file err_file rc=0
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" \
        >"$out_file" 2>"$err_file" || rc=$?

    local out err
    out="$(< "$out_file")"
    err="$(< "$err_file")"
    rm -f "$out_file" "$err_file"

    assert_exit 0 "$rc" "npm install no profile: exit 0"
    assert_eq "$out" "" "npm install no profile: stdout empty (allow)"
    assert_contains "$err" "allowing init-class" "npm install no profile: stderr advisory"

    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
# Test: Read with no profile → allow silently (non-destructive, no D7 path)
# ---------------------------------------------------------------------------
test_read_no_profile_allowed() {
    local sb="$1"
    local sandbox="${sb}/data"
    mkdir -p "${sandbox}/profiles"
    export YCI_DATA_ROOT="$sandbox"
    unset YCI_CUSTOMER YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local payload='{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}'

    local out rc=0
    out="$(printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "read no profile: exit 0"
    assert_eq "$out" "" "read no profile: stdout empty (allow)"

    teardown_test_sandbox "$sandbox"
}

# ---------------------------------------------------------------------------
with_sandbox test_write_to_profiles_allowed
with_sandbox test_edit_profiles_allowed
with_sandbox test_bash_npm_install_allowed_with_advisory
with_sandbox test_read_no_profile_allowed

yci_test_summary
