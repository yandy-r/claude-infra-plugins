#!/usr/bin/env bash
# Hook end-to-end: read-only tools must always exit 0 with empty stdout.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# ---------------------------------------------------------------------------
# Helper: send payload, assert exits 0 + empty stdout
# ---------------------------------------------------------------------------
_assert_read_only_allowed() {
    local payload="$1" name="$2"
    local sandbox
    sandbox="$(setup_test_sandbox "read-tools")"
    export YCI_DATA_ROOT="$sandbox"
    unset YCI_CWG_OVERRIDE YCI_CWG_DRY_RUN

    local out rc=0
    out="$(printf '%s' "$payload" | bash "${YCI_CWG_SCRIPTS_DIR}/pretool.sh" 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "${name}:exit"
    assert_eq "$out" "" "${name}:stdout-empty"

    teardown_test_sandbox "$sandbox"
}

test_read_tool_allows() {
    _assert_read_only_allowed \
        '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foo"}}' \
        "hook read-only: Read"

    _assert_read_only_allowed \
        '{"tool_name":"Grep","tool_input":{"pattern":"foo","path":"/tmp"}}' \
        "hook read-only: Grep"

    _assert_read_only_allowed \
        '{"tool_name":"Glob","tool_input":{"pattern":"**/*.txt"}}' \
        "hook read-only: Glob"

    _assert_read_only_allowed \
        '{"tool_name":"WebFetch","tool_input":{"url":"https://example.com"}}' \
        "hook read-only: WebFetch"

    _assert_read_only_allowed \
        '{"tool_name":"Bash","tool_input":{"command":"ls /tmp"}}' \
        "hook read-only: Bash ls"

    _assert_read_only_allowed \
        '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \
        "hook read-only: Bash git status"
}

# ---------------------------------------------------------------------------
with_sandbox test_read_tool_allows

yci_test_summary
