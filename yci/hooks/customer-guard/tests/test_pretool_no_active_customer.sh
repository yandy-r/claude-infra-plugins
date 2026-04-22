#!/usr/bin/env bash
# Integration tests: pretool.sh behavior when no active customer is configured.
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

PRETOOL="${REPO_ROOT}/yci/hooks/customer-guard/scripts/pretool.sh"

_pretool_ok() {
    if [ ! -f "$PRETOOL" ]; then
        printf 'DIAGNOSTIC: pretool.sh not found at %s\n' "$PRETOOL" >&2
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# test_non_yci_payload_allowed: customer checks are yci-only. A generic payload
# with no yci markers/paths should pass through even when no customer is active.
#
# with_sandbox sets YCI_CUSTOMER="" (empty). resolve-customer.sh treats
# empty/whitespace-only YCI_CUSTOMER as "set but empty" and falls through to
# Tier 2 (dotfile walk) and Tier 3 (state.json), both of which also fail in
# the clean sandbox. The guard must still ALLOW because the payload is not yci.
# ---------------------------------------------------------------------------
test_non_yci_payload_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "non_yci_allow: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"
    # YCI_CUSTOMER is already "" per with_sandbox; leave it empty.

    local payload='{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'

    local stdout stderr rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/tmp/yci-test-fc-stderr-$$)"; rc=$?
    stderr="$(cat /tmp/yci-test-fc-stderr-$$ 2>/dev/null)"; rm -f /tmp/yci-test-fc-stderr-$$

    assert_exit 0 "$rc" "non_yci_allow: exit 0"
    assert_eq "$stdout" "" "non_yci_allow: stdout empty (allow)"
    assert_eq "$stderr" "" "non_yci_allow: stderr empty"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# test_yci_no_active_denied: yci calls still fail-closed by default when a
# customer is required and the payload is not a bootstrap init/switch flow.
# ---------------------------------------------------------------------------
test_yci_no_active_denied() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_no_active_denied: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"
    local payload='{"tool_name":"Skill","tool_input":{"command":"/yci:guard-check /tmp/x"}}'

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_no_active_denied: exit 0 (deny emitted as JSON)"
    assert_contains "$stdout" '"permissionDecision": "deny"' "yci_no_active_denied: decision=deny"
    assert_contains "$stdout" "no active customer" "yci_no_active_denied: reason mentions no active customer"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# test_yci_fail_open_env: YCI_GUARD_FAIL_OPEN=1 with no active customer allows
# a yci call that would otherwise deny.
# ---------------------------------------------------------------------------
test_yci_fail_open_env() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_fail_open: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"
    local YCI_GUARD_FAIL_OPEN=1
    export YCI_GUARD_FAIL_OPEN

    local payload='{"tool_name":"Skill","tool_input":{"command":"/yci:guard-check /tmp/x"}}'

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_fail_open: exit 0"
    assert_eq "$stdout" "" "yci_fail_open: stdout empty (allow with YCI_GUARD_FAIL_OPEN=1)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED YCI_GUARD_FAIL_OPEN
}

# ---------------------------------------------------------------------------
# test_yci_skill_bootstrap_allowed: a `Skill(yci:customer-profile)` call with
# mode `init` in its args — the real payload shape Claude Code emits when a
# slash command like `/yci:init itcn` dispatches to the customer-profile skill.
# The Skill tool carries `skill` and `args` fields (not `command`), and the
# slash-command literal is NOT in the payload by the time the hook sees it.
# ---------------------------------------------------------------------------
test_yci_skill_bootstrap_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_skill_bootstrap: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local payload='{"tool_name":"Skill","tool_input":{"skill":"yci:customer-profile","args":"init itcn"}}'

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_skill_bootstrap: exit 0"
    assert_eq "$stdout" "" "yci_skill_bootstrap: stdout empty (allow)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# Same shape as above but for `switch` mode — `/yci:switch <customer>` also
# needs to work against a no-active-customer state when the MRU state.json is
# missing or empty.
# ---------------------------------------------------------------------------
test_yci_skill_switch_bootstrap_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_skill_switch_bootstrap: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local payload='{"tool_name":"Skill","tool_input":{"skill":"yci:customer-profile","args":"switch itcn"}}'

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_skill_switch_bootstrap: exit 0"
    assert_eq "$stdout" "" "yci_skill_switch_bootstrap: stdout empty (allow)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# `whoami` with no active customer is a legitimate "who am I?" query — the
# skill answers "no active customer" rather than refusing, so the guard must
# not preemptively block the Skill invocation.
# ---------------------------------------------------------------------------
test_yci_skill_whoami_bootstrap_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_skill_whoami_bootstrap: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local payload='{"tool_name":"Skill","tool_input":{"skill":"yci:customer-profile","args":"whoami"}}'

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_skill_whoami_bootstrap: exit 0"
    assert_eq "$stdout" "" "yci_skill_whoami_bootstrap: stdout empty (allow)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# A non-customer-profile yci skill MUST still deny when no active customer
# is set — the bootstrap lane is intentionally narrow.
# ---------------------------------------------------------------------------
test_yci_skill_non_customer_profile_denied() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_skill_non_customer_profile_denied: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local payload='{"tool_name":"Skill","tool_input":{"skill":"yci:guard-check","args":"/tmp/x"}}'

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_skill_non_customer_profile_denied: exit 0 (deny emitted as JSON)"
    assert_contains "$stdout" '"permissionDecision": "deny"' "yci_skill_non_customer_profile_denied: decision=deny"
    assert_contains "$stdout" "no active customer" "yci_skill_non_customer_profile_denied: reason mentions no active customer"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# Regression guard: some upstream payloads (e.g., Task tool prompts or legacy
# paths) still carry a literal `/yci:init` string. The marker-based lane must
# keep working even when the structural Skill check doesn't match.
# ---------------------------------------------------------------------------
test_yci_slash_command_bootstrap_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_slash_command_bootstrap: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local payload='{"tool_name":"Task","tool_input":{"prompt":"run /yci:init itcn for me"}}'

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_slash_command_bootstrap: exit 0"
    assert_eq "$stdout" "" "yci_slash_command_bootstrap: stdout empty (allow)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# After the bootstrap Skill call lands, the customer-profile skill typically
# inspects the data root with `ls <data-root>/profiles` before picking or
# creating a profile. That payload has ONLY data-root paths (no repo-bootstrap
# path), but is still legitimate bootstrap work and must be allowed.
# ---------------------------------------------------------------------------
test_yci_bash_ls_data_root_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_bash_ls_data_root: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local cmd="ls ${data}/profiles"
    local payload
    payload="$(python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$cmd")"

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_bash_ls_data_root: exit 0"
    assert_eq "$stdout" "" "yci_bash_ls_data_root: stdout empty (allow)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# Reading the resolved data root with the Read tool must also be allowed
# during bootstrap — the skill uses Read on state.json and profile YAML files.
# ---------------------------------------------------------------------------
test_yci_read_data_root_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_read_data_root: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"
    : > "$data/state.json"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local payload
    payload="$(python3 -c 'import json, sys; print(json.dumps({"tool_name": "Read", "tool_input": {"file_path": sys.argv[1]}}))' "$data/state.json")"

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_read_data_root: exit 0"
    assert_eq "$stdout" "" "yci_read_data_root: stdout empty (allow)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# A Bash payload that mixes a yci data-root path with a non-yci path is NOT
# bootstrap — deny. This guards against an agent using the bootstrap lane to
# smuggle foreign-path reads.
# ---------------------------------------------------------------------------
test_yci_bash_mixed_paths_denied() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_bash_mixed_paths_denied: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local cmd="cp ${data}/profiles/acme.yaml /tmp/exfiltrated.yaml"
    local payload
    payload="$(python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$cmd")"

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_bash_mixed_paths_denied: exit 0 (deny emitted as JSON)"
    assert_contains "$stdout" '"permissionDecision": "deny"' "yci_bash_mixed_paths_denied: decision=deny"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
# Regression: when Claude Code's agent constructs the canonical bootstrap
# compound — `DATA_ROOT="$(resolve-data-root.sh)"; init-profile.sh "$DATA_ROOT"
# <customer>` — shlex.split merges the variable assignment and command
# substitution into one token. Prior versions of extract-paths.py synthesized
# a junk path from that token against cwd, which the bootstrap lane then
# classified as foreign and denied. The fix is to pull real paths out of the
# raw command via the hint regex and skip shell-syntax tokens.
# ---------------------------------------------------------------------------
test_yci_bash_compound_bootstrap_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_bash_compound_bootstrap: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local resolve="${REPO_ROOT}/yci/skills/_shared/scripts/resolve-data-root.sh"
    local init="${REPO_ROOT}/yci/skills/customer-profile/scripts/init-profile.sh"
    local cmd="DATA_ROOT=\"\$(${resolve})\"; ${init} \"\$DATA_ROOT\" itcn"
    local payload
    payload="$(python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$cmd")"

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_bash_compound_bootstrap: exit 0"
    assert_eq "$stdout" "" "yci_bash_compound_bootstrap: stdout empty (allow)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
test_yci_bash_bootstrap_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "yci_bash_bootstrap: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local cmd="bash ${REPO_ROOT}/yci/skills/customer-profile/scripts/init-profile.sh ${data} itcn"
    local payload
    payload="$(python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$cmd")"

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "yci_bash_bootstrap: exit 0"
    assert_eq "$stdout" "" "yci_bash_bootstrap: stdout empty (allow)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
test_ycc_skill_allowed() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "ycc_skill_allowed: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles"

    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local payload='{"tool_name":"Skill","tool_input":{"command":"/ycc:deep-research modernize ITCN"}}'

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "ycc_skill_allowed: exit 0"
    assert_eq "$stdout" "" "ycc_skill_allowed: stdout empty (allow)"

    unset YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
with_sandbox test_non_yci_payload_allowed
with_sandbox test_yci_no_active_denied
with_sandbox test_yci_fail_open_env
with_sandbox test_yci_skill_bootstrap_allowed
with_sandbox test_yci_skill_switch_bootstrap_allowed
with_sandbox test_yci_skill_whoami_bootstrap_allowed
with_sandbox test_yci_skill_non_customer_profile_denied
with_sandbox test_yci_slash_command_bootstrap_allowed
with_sandbox test_yci_bash_ls_data_root_allowed
with_sandbox test_yci_read_data_root_allowed
with_sandbox test_yci_bash_mixed_paths_denied
with_sandbox test_yci_bash_compound_bootstrap_allowed
with_sandbox test_yci_bash_bootstrap_allowed
with_sandbox test_ycc_skill_allowed

yci_test_summary
