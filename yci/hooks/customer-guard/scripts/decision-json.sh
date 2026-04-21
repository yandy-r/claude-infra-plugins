#!/usr/bin/env bash
# yci — Claude Code PreToolUse hook decision JSON emitter.
#
# Sourceable library. Exports:
#   emit_allow   — prints nothing (allow is default)
#   emit_deny <reason-string>
#     Prints a Claude Code hook decision JSON with permissionDecision=deny
#     and permissionDecisionReason=<escaped reason>.
#
# Centralizes the decision shape so future Claude Code hook API changes are a
# one-file edit.
#
# No `set -euo pipefail` — sourceable library.

emit_allow() {
    : # allow is default; empty stdout is interpreted as allow
}

emit_deny() {
    local reason="$1"
    # Escape for JSON using python3 — handles newlines, quotes, backslashes.
    python3 -c '
import json, sys
reason = sys.argv[1]
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }
}))
' "$reason"
}
