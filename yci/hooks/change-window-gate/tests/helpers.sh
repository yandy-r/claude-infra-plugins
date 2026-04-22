#!/usr/bin/env bash
# Shared test helpers for change-window-gate tests.
# Source this file from every test_*.sh.
# Do NOT set -euo here — tests need fine-grained control over exit behavior.

YCI_TEST_PASS=0
YCI_TEST_FAIL=0
YCI_TEST_FILE="${BASH_SOURCE[1]##*/}"  # caller's basename

# Resolve key directory paths
_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Hook scripts dir (pretool.sh lives here)
if cd "${_HELPERS_DIR}/../scripts" 2>/dev/null; then
    YCI_CWG_SCRIPTS_DIR="$(pwd -P)"
    cd "${_HELPERS_DIR}" || true
else
    YCI_CWG_SCRIPTS_DIR="${_HELPERS_DIR}/../scripts"
fi
export YCI_CWG_SCRIPTS_DIR

# Repo root — tests/ is 4 levels below repo root: yci/hooks/change-window-gate/tests/
if cd "${_HELPERS_DIR}/../../../.." 2>/dev/null; then
    REPO_ROOT="$(pwd -P)"
    cd "${_HELPERS_DIR}" || true
else
    REPO_ROOT="${_HELPERS_DIR}/../../../.."
fi
export REPO_ROOT

# CLAUDE_PLUGIN_ROOT is the yci/ directory (one level below repo root)
CLAUDE_PLUGIN_ROOT="${REPO_ROOT}/yci"
export CLAUDE_PLUGIN_ROOT

# ---------------------------------------------------------------------------
# Internal reporter
# ---------------------------------------------------------------------------

_yci_test_report() {
    local status="$1" name="$2" detail="${3:-}"
    if [ "$status" = "PASS" ]; then
        YCI_TEST_PASS=$((YCI_TEST_PASS + 1))
        if [ "${YCI_TEST_VERBOSE:-0}" = "1" ]; then
            printf '  \033[32m+\033[0m %s\n' "$name"
        fi
    else
        YCI_TEST_FAIL=$((YCI_TEST_FAIL + 1))
        printf '  \033[31mFAIL\033[0m %s\n' "$name" >&2
        if [ -n "$detail" ]; then
            printf '    %s\n' "$detail" >&2
        fi
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

assert_eq() {
    local got="$1" expected="$2" name="${3:-assert_eq}"
    if [ "$got" = "$expected" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "got='$got' expected='$expected'"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" name="${3:-assert_contains}"
    case "$haystack" in
        *"$needle"*) _yci_test_report PASS "$name" ;;
        *)           _yci_test_report FAIL "$name" "'$needle' not in output" ;;
    esac
}

assert_not_contains() {
    local haystack="$1" needle="$2" name="${3:-assert_not_contains}"
    case "$haystack" in
        *"$needle"*) _yci_test_report FAIL "$name" "unexpected '$needle' found in output" ;;
        *)           _yci_test_report PASS "$name" ;;
    esac
}

assert_exit() {
    local expected="$1" got="$2" name="${3:-assert_exit}"
    if [ "$got" = "$expected" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "exit got=$got expected=$expected"
    fi
}

assert_file_exists() {
    local path="$1" name="${2:-assert_file_exists}"
    if [ -f "$path" ]; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "file not found: $path"
    fi
}

assert_json_valid() {
    local path="$1" name="${2:-assert_json_valid}"
    if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$path" 2>/dev/null; then
        _yci_test_report PASS "$name"
    else
        _yci_test_report FAIL "$name" "invalid JSON in: $path"
    fi
}

assert_decision() {
    # assert_decision <decision_json_string> <expected_decision> [name]
    local json="$1" expected="$2" name="${3:-assert_decision}"
    local got
    got="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["decision"])' 2>/dev/null)" || got="(parse-error)"
    assert_eq "$got" "$expected" "$name"
}

assert_decision_contains() {
    # assert_decision_contains <decision_json_string> <substr> [name]
    local json="$1" substr="$2" name="${3:-assert_decision_contains}"
    local rationale
    rationale="$(printf '%s' "$json" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("rationale","") + " " + d.get("adapter",""))' 2>/dev/null)" || rationale="$json"
    assert_contains "$rationale" "$substr" "$name"
}

assert_hook_allows() {
    # assert_hook_allows <stdin-json> [name]
    local payload="$1" name="${2:-assert_hook_allows}"
    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "${name}:exit"
    assert_eq "$stdout" "" "${name}:stdout-empty"
}

assert_hook_denies() {
    # assert_hook_denies <stdin-json> <rationale-substr> [name]
    local payload="$1" rationale_substr="$2" name="${3:-assert_hook_denies}"
    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "${name}:exit"
    assert_contains "$stdout" '"permissionDecision": "deny"' "${name}:deny-json"
    assert_contains "$stdout" "$rationale_substr" "${name}:rationale"
}

# ---------------------------------------------------------------------------
# Sandbox management
# ---------------------------------------------------------------------------

# setup_test_sandbox [test-name]
# Creates a per-test ephemeral YCI_DATA_ROOT under /tmp/cwg-test-<PID>/<test-name>/
# with subdirs profiles/, artifacts/, logs/. Exports YCI_DATA_ROOT.
# Prints the sandbox root path.
setup_test_sandbox() {
    local label="${1:-sandbox}"
    local sandbox
    sandbox="$(mktemp -d -t "cwg-test-${$}-XXXXXX")"
    mkdir -p "${sandbox}/profiles" "${sandbox}/artifacts" "${sandbox}/logs"
    export YCI_DATA_ROOT="$sandbox"
    printf '%s' "$sandbox"
}

# teardown_test_sandbox <sandbox-path>
# Removes the sandbox and unsets YCI_DATA_ROOT.
teardown_test_sandbox() {
    local sandbox="${1:-}"
    [ -n "$sandbox" ] && rm -rf "$sandbox"
    unset YCI_DATA_ROOT
}

# fixture_path <name>
# Resolves to the fixtures/ directory sibling of the test.
fixture_path() {
    printf '%s/fixtures/%s' "${_HELPERS_DIR}" "${1:-}"
}

# write_profile_yaml <sandbox> <customer-id> <adapter> [source-path] [timezone]
# Writes a valid synthetic profile YAML to $sandbox/profiles/<customer-id>.yaml.
# Also writes a state.json so resolve-customer.sh Tier 3 can find the customer.
write_profile_yaml() {
    local sandbox="$1"
    local customer_id="$2"
    local adapter="$3"
    local source_path="${4:-}"
    local timezone="${5:-UTC}"

    local profile_path="${sandbox}/profiles/${customer_id}.yaml"

    # Build the change_window block based on adapter type.
    local cw_block
    case "$adapter" in
        ical|json-schedule)
            cw_block="change_window:
  adapter: ${adapter}
  source: \"${source_path}\"
  timezone: ${timezone}"
            ;;
        always-open)
            cw_block="change_window:
  adapter: always-open"
            ;;
        none)
            cw_block="change_window:
  adapter: none"
            ;;
        *)
            # Unknown adapter (e.g. servicenow-cab) — write a minimal block
            cw_block="change_window:
  adapter: ${adapter}"
            ;;
    esac

    cat > "$profile_path" <<EOF
customer:
  id: ${customer_id}
  display_name: "${customer_id} (synthetic test)"
engagement:
  id: ${customer_id}-eng-001
  type: implementation
  sow_ref: SOW-TEST-001
  scope_tags: [test]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: commercial
  evidence_schema_version: 1
inventory:
  adapter: file
  path: inventories/${customer_id}
approval:
  adapter: github-pr
deliverable:
  format: [markdown]
  header_template: /tmp/header.md
  handoff_format: git-repo
safety:
  default_posture: review
  change_window_required: true
  scope_enforcement: warn
${cw_block}
EOF

    # Write state.json so resolve-customer.sh Tier 3 finds the customer.
    python3 -c "import json; print(json.dumps({'active': '${customer_id}'}))" \
        > "${sandbox}/state.json"
}

# ---------------------------------------------------------------------------
# Hook runner
# ---------------------------------------------------------------------------

# run_hook <stdin-json>
# Invokes pretool.sh from the worktree root, passing the JSON payload on stdin.
# Sets _HOOK_STDOUT, _HOOK_STDERR, _HOOK_RC in caller scope.
run_hook() {
    local payload="$1"
    local _out_file _err_file
    _out_file="$(mktemp)"
    _err_file="$(mktemp)"

    _HOOK_RC=0
    printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" \
        >"$_out_file" 2>"$_err_file" || _HOOK_RC=$?

    _HOOK_STDOUT="$(< "$_out_file")"
    _HOOK_STDERR="$(< "$_err_file")"
    rm -f "$_out_file" "$_err_file"
}

# ---------------------------------------------------------------------------
# Sandbox wrapper (mirrors customer-guard pattern)
# ---------------------------------------------------------------------------

with_sandbox() {
    # Usage: with_sandbox <fn-name>
    # Calls <fn-name> with the sandbox path as its first argument. Saves/restores
    # HOME, YCI_DATA_ROOT, YCI_CUSTOMER, YCI_CWG_OVERRIDE, YCI_CWG_DRY_RUN,
    # and the working directory around the call.
    local fn="$1"
    local sb
    sb="$(mktemp -d -t "cwg-ws-${$}-XXXXXX")"
    mkdir -p "$sb/real" "$sb/home" "$sb/cwd"

    # Save prior env state
    local saved_home="${HOME:-}"
    local saved_dr_set=${YCI_DATA_ROOT+x}      saved_dr="${YCI_DATA_ROOT:-}"
    local saved_cu_set=${YCI_CUSTOMER+x}        saved_cu="${YCI_CUSTOMER:-}"
    local saved_ov_set=${YCI_CWG_OVERRIDE+x}   saved_ov="${YCI_CWG_OVERRIDE:-}"
    local saved_dr2_set=${YCI_CWG_DRY_RUN+x}   saved_dr2="${YCI_CWG_DRY_RUN:-}"
    local saved_cwd; saved_cwd="$(pwd -P)"

    export YCI_TEST_SANDBOX="$sb"
    export HOME="$sb/home"
    export YCI_DATA_ROOT=""
    unset YCI_CUSTOMER YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local rc=0
    if cd "$sb/cwd"; then
        "$fn" "$sb" || rc=$?
    else
        rc=1
    fi

    # Restore cwd
    cd "$saved_cwd" || true

    # Restore env vars
    export HOME="$saved_home"
    if [ -n "$saved_dr_set" ];  then export YCI_DATA_ROOT="$saved_dr";      else unset YCI_DATA_ROOT;      fi
    if [ -n "$saved_cu_set" ];  then export YCI_CUSTOMER="$saved_cu";        else unset YCI_CUSTOMER;        fi
    if [ -n "$saved_ov_set" ];  then export YCI_CWG_OVERRIDE="$saved_ov";   else unset YCI_CWG_OVERRIDE;   fi
    if [ -n "$saved_dr2_set" ]; then export YCI_CWG_DRY_RUN="$saved_dr2";   else unset YCI_CWG_DRY_RUN;    fi

    rm -rf "$sb"
    unset YCI_TEST_SANDBOX
    return "$rc"
}

# ---------------------------------------------------------------------------
# Summary — call at the end of every test_*.sh
# ---------------------------------------------------------------------------

yci_test_summary() {
    if [ "$YCI_TEST_FAIL" -eq 0 ]; then
        printf '  %s: %d passed\n' "$YCI_TEST_FILE" "$YCI_TEST_PASS"
        return 0
    else
        printf '  %s: %d passed, %d FAILED\n' "$YCI_TEST_FILE" "$YCI_TEST_PASS" "$YCI_TEST_FAIL" >&2
        return 1
    fi
}
