#!/usr/bin/env bash
set -euo pipefail
# Tests for extract-paths.py — per-tool-type path extraction coverage.
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd -P)"
    export CLAUDE_PLUGIN_ROOT
fi
# shellcheck disable=SC1091
source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/customer-isolation/tests/helpers.sh"

EXTRACTOR="${CLAUDE_PLUGIN_ROOT}/skills/_shared/customer-isolation/scripts/extract-paths.py"

_extractor_ok() {
    if [ ! -f "$EXTRACTOR" ]; then
        printf 'DIAGNOSTIC: extract-paths.py not found at %s\n' "$EXTRACTOR" >&2
        return 1
    fi
    return 0
}

_require_extractor() {
    if ! _extractor_ok; then
        _yci_test_report FAIL "extract-paths.py missing at $EXTRACTOR"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Helper: run extractor with a JSON string, return stdout
# ---------------------------------------------------------------------------
_run() {
    printf '%s' "$1" | python3 "$EXTRACTOR" 2>/dev/null
}
_run_with_stderr() {
    # usage: stdout=$(  _run_with_stderr_impl "$json"  2>/tmp/err  )
    printf '%s' "$1" | python3 "$EXTRACTOR"
}

# ---------------------------------------------------------------------------
test_read() {
    _require_extractor || return 1
    local out
    out="$(_run '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}')"
    assert_contains "$out" "/tmp/x" "read: extracts file_path"
}

test_write() {
    _require_extractor || return 1
    local out
    out="$(_run '{"tool_name":"Write","tool_input":{"file_path":"/var/data/output.txt"}}')"
    assert_contains "$out" "/var/data/output.txt" "write: extracts file_path"
}

test_edit() {
    _require_extractor || return 1
    local out
    out="$(_run '{"tool_name":"Edit","tool_input":{"file_path":"/etc/config.conf"}}')"
    assert_contains "$out" "/etc/config.conf" "edit: extracts file_path"
}

test_multi_edit() {
    _require_extractor || return 1
    local out
    out="$(_run '{"tool_name":"MultiEdit","tool_input":{"file_path":"/srv/app/main.py"}}')"
    assert_contains "$out" "/srv/app/main.py" "multi_edit: extracts file_path"
}

test_notebook_edit() {
    _require_extractor || return 1
    local out
    out="$(_run '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/home/user/analysis.ipynb"}}')"
    assert_contains "$out" "/home/user/analysis.ipynb" "notebook_edit: extracts notebook_path"
}

test_glob_with_path() {
    _require_extractor || return 1
    local out
    out="$(_run '{"tool_name":"Glob","tool_input":{"pattern":"**/*.py","path":"/project/src"}}')"
    assert_contains "$out" "/project/src" "glob: extracts path"
}

test_grep_with_path() {
    _require_extractor || return 1
    local out
    out="$(_run '{"tool_name":"Grep","tool_input":{"pattern":"TODO","path":"/workspace/app"}}')"
    assert_contains "$out" "/workspace/app" "grep: extracts path"
}

test_bash_simple() {
    _require_extractor || return 1
    local out
    out="$(_run '{"tool_name":"Bash","tool_input":{"command":"cat /etc/hosts"}}')"
    assert_contains "$out" "/etc/hosts" "bash_simple: extracts path from command"
}

test_bash_grep_foreign_path() {
    _require_extractor || return 1
    local out
    out="$(_run '{"tool_name":"Bash","tool_input":{"command":"grep foo /foreign/path"}}')"
    assert_contains "$out" "/foreign/path" "bash_grep_path: extracts path argument"
}

test_bash_truncation() {
    _require_extractor || return 1
    # Build a command with >512 tokens: "echo 1 2 3 ..."
    local cmd="echo"
    local i
    for i in $(seq 1 600); do cmd="$cmd $i"; done
    local json
    json="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd")"
    local stderr_out
    stderr_out="$(printf '%s' "$json" | python3 "$EXTRACTOR" 2>&1 1>/dev/null)"
    assert_contains "$stderr_out" "truncated:paths" "bash_trunc: emits truncation warning"
}

test_webfetch_file() {
    _require_extractor || return 1
    local out
    out="$(_run '{"tool_name":"WebFetch","tool_input":{"url":"file:///etc/hosts"}}')"
    assert_contains "$out" "/etc/hosts" "webfetch_file: extracts path from file:// URL"
}

test_webfetch_https() {
    _require_extractor || return 1
    local out
    out="$(_run '{"tool_name":"WebFetch","tool_input":{"url":"https://example.com/page"}}')"
    assert_eq "$out" "" "webfetch_https: no path emitted for https URL"
}

test_task_prompt() {
    _require_extractor || return 1
    local out
    out="$(_run '{"tool_name":"Task","tool_input":{"prompt":"Please read ~/foo/bar.md and ./local.txt"}}')"
    assert_contains "$out" "foo/bar.md" "task_prompt: extracts tilde path"
    assert_contains "$out" "local.txt" "task_prompt: extracts relative path"
}

test_relative_with_cwd() {
    _require_extractor || return 1
    local out
    out="$(_run '{"tool_name":"Write","tool_input":{"file_path":"./relative.md"},"cwd":"/tmp/work"}')"
    assert_contains "$out" "/tmp/work/relative.md" "relative_cwd: resolves ./path against cwd"
}

test_missing_file_path() {
    _require_extractor || return 1
    local out rc
    out="$(_run '{"tool_name":"Read","tool_input":{}}')"; rc=$?
    assert_eq "$out" "" "missing_fp: empty output on missing file_path"
    assert_exit 0 "$rc" "missing_fp: exits 0"
}

test_bash_compound_with_command_substitution() {
    _require_extractor || return 1
    local cmd='DATA_ROOT="$(/plugins/yci/skills/_shared/scripts/resolve-data-root.sh)"; /plugins/yci/skills/customer-profile/scripts/init-profile.sh "$DATA_ROOT" itcn'
    local json
    json="$(python3 -c 'import json, sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")"
    local out
    out="$(printf '%s' "$json" | python3 "$EXTRACTOR" 2>/dev/null)"

    assert_contains "$out" "/plugins/yci/skills/_shared/scripts/resolve-data-root.sh" \
        "compound_cmdsub: extracts path inside \$(...)"
    assert_contains "$out" "/plugins/yci/skills/customer-profile/scripts/init-profile.sh" \
        "compound_cmdsub: extracts standalone path after ;"
    # The synthesized junk path must NOT appear.
    case "$out" in
        *'DATA_ROOT=$'*)
            _yci_test_report FAIL "compound_cmdsub: synthesized junk path leaked into output"
            return 1
            ;;
        *)
            _yci_test_report PASS "compound_cmdsub: no synthesized junk path"
            ;;
    esac
}

test_bash_variable_assignment_with_literal() {
    _require_extractor || return 1
    # `X=/literal/path` — shlex returns a single token containing `=`. Ensure
    # we don't synthesize `/cwd/X=/literal/path`; instead pull `/literal/path`
    # out via the hint regex.
    local cmd='X=/literal/plugin/bin/tool'
    local json
    json="$(python3 -c 'import json, sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")"
    local out
    out="$(printf '%s' "$json" | python3 "$EXTRACTOR" 2>/dev/null)"

    assert_contains "$out" "/literal/plugin/bin/tool" \
        "var_assignment: extracts literal path on RHS"
    case "$out" in
        *'X='*)
            _yci_test_report FAIL "var_assignment: leaked \`X=\` prefix"
            return 1
            ;;
        *)
            _yci_test_report PASS "var_assignment: no \`X=\` prefix leak"
            ;;
    esac
}

test_invalid_json() {
    _require_extractor || return 1
    local stderr_out rc
    stderr_out="$(printf 'not json' | python3 "$EXTRACTOR" 2>&1 1>/dev/null)"; rc=$?
    assert_contains "$stderr_out" "truncated:paths:invalid-json" "invalid_json: emits marker on stderr"
    assert_exit 0 "$rc" "invalid_json: exits 0"
}

# ---------------------------------------------------------------------------
with_sandbox test_read
with_sandbox test_write
with_sandbox test_edit
with_sandbox test_multi_edit
with_sandbox test_notebook_edit
with_sandbox test_glob_with_path
with_sandbox test_grep_with_path
with_sandbox test_bash_simple
with_sandbox test_bash_grep_foreign_path
with_sandbox test_bash_truncation
with_sandbox test_webfetch_file
with_sandbox test_webfetch_https
with_sandbox test_task_prompt
with_sandbox test_relative_with_cwd
with_sandbox test_missing_file_path
with_sandbox test_bash_compound_with_command_substitution
with_sandbox test_bash_variable_assignment_with_literal
with_sandbox test_invalid_json

yci_test_summary
