#!/usr/bin/env bash
# yci — change-window-gate PreToolUse hook entrypoint.
#
# Called by Claude Code on every tool invocation (after customer-guard). Reads a
# PreToolUse JSON payload on stdin and writes a Claude Code hook decision JSON
# on stdout when blocking; exit 0 with empty stdout means allow.
#
# Decision flow:
#   1. Short-circuit allow on YCI_CWG_OVERRIDE=1.
#   2. Resolve data root + active customer.
#   3. No active customer: allow read-only calls silently, allow init-class
#      calls with an advisory, block artifact creation (D7), block other
#      destructive ops conservatively.
#   4. Active customer: classify via destructive-classifier.sh — allow
#      reads/queries.
#   5. Load customer profile JSON.
#   6. Delegate window decision to window-decision.sh.
#   7. Dispatch: allowed → exit 0; warning → stderr + exit 0;
#      blocked → deny JSON (or dry-run log + exit 0).
#
# Environment knobs:
#   YCI_CWG_OVERRIDE=1   — short-circuit allow (bypass all checks)
#   YCI_CWG_DRY_RUN=1    — log would-be blocks; always allow
#
# Exit 0 always — the deny JSON on stdout is the refusal signal.

set -uo pipefail  # intentionally no -e — aggregates decision logic

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd -P)}"

# ---------------------------------------------------------------------------
# 1. Read stdin payload
# ---------------------------------------------------------------------------

payload="$(cat)"

# ---------------------------------------------------------------------------
# 2. Short-circuit on YCI_CWG_OVERRIDE=1
# ---------------------------------------------------------------------------

if [[ "${YCI_CWG_OVERRIDE:-}" == "1" ]]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# 3. Extract tool_name and tool_input from payload
# ---------------------------------------------------------------------------

tool_name="$(python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("tool_name",""))' <<< "$payload")"
tool_input="$(python3 -c 'import json,sys; d=json.loads(sys.stdin.read()); print(json.dumps(d.get("tool_input",{})))' <<< "$payload")"

# ---------------------------------------------------------------------------
# 4. Resolve data root
# ---------------------------------------------------------------------------

# shellcheck source=../../../skills/_shared/scripts/resolve-data-root.sh
source "${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/resolve-data-root.sh"
data_root=""; data_root_rc=0
data_root="$(yci_resolve_data_root 2>/dev/null)" || data_root_rc=$?
if [[ "$data_root_rc" -ne 0 ]]; then
    data_root="${YCI_DATA_ROOT:-${HOME}/.config/yci}"
fi

# ---------------------------------------------------------------------------
# 5. Resolve active customer (subprocess — resolve-customer.sh is standalone)
# ---------------------------------------------------------------------------

RESOLVE="${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/resolve-customer.sh"
active_customer=""; resolve_rc=0
active_customer="$(bash "$RESOLVE" --data-root "$data_root" 2>/dev/null)" || resolve_rc=$?
if [[ "$resolve_rc" -ne 0 ]]; then
    active_customer=""
fi
active_customer="$(printf '%s' "$active_customer" | tr -d '[:space:]')"

# ---------------------------------------------------------------------------
# 6. No active customer — purpose-classify and decide
# ---------------------------------------------------------------------------

if [[ -z "$active_customer" ]]; then
    case "$tool_name" in
        Read|Grep|Glob|WebFetch|WebSearch)
            exit 0
            ;;
    esac

    # shellcheck source=./purpose-classifier.sh
    source "${SCRIPT_DIR}/purpose-classifier.sh"

    if cwg_is_init_path "$tool_name" "$tool_input"; then
        # Init path — allow with stderr advisory
        printf 'yci change-window-gate: no active profile; allowing init-class call (%s). Run /yci:switch <id> to establish a profile.\n' "$tool_name" >&2
        exit 0
    fi

    # shellcheck source=./destructive-classifier.sh
    source "${SCRIPT_DIR}/destructive-classifier.sh"
    if ! cwg_is_destructive "$tool_name" "$tool_input"; then
        exit 0
    fi

    # shellcheck source=../../customer-guard/scripts/decision-json.sh
    source "${CLAUDE_PLUGIN_ROOT}/hooks/customer-guard/scripts/decision-json.sh"

    if cwg_is_artifact_creation "$tool_name" "$tool_input"; then
        # Destructive + no profile + artifact creation — deny (D7)
        emit_deny "cwg-no-profile-cannot-create: cannot enforce a change window without an active customer profile; run /yci:switch <id> first"
        exit 0
    fi

    # Default: destructive + no profile + not-init-not-artifact → block conservatively
    emit_deny "cwg-no-profile-destructive-write: destructive operation ($tool_name) requires an active customer profile; run /yci:switch <id> first"
    exit 0
fi

# ---------------------------------------------------------------------------
# 7. Active customer: classify destructive — allow reads/queries
# ---------------------------------------------------------------------------

# shellcheck source=./destructive-classifier.sh
source "${SCRIPT_DIR}/destructive-classifier.sh"
if ! cwg_is_destructive "$tool_name" "$tool_input"; then
    exit 0
fi

# ---------------------------------------------------------------------------
# 8. Load profile JSON (subprocess — load-profile.sh is standalone)
# ---------------------------------------------------------------------------

LOAD_PROFILE="${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/load-profile.sh"
profile_json_path="$(mktemp)"
trap 'rm -f "$profile_json_path"' EXIT

load_rc=0
bash "$LOAD_PROFILE" "$data_root" "$active_customer" > "$profile_json_path" 2>/dev/null || load_rc=$?
if [[ "$load_rc" -ne 0 ]]; then
    # shellcheck source=../../customer-guard/scripts/decision-json.sh
    source "${CLAUDE_PLUGIN_ROOT}/hooks/customer-guard/scripts/decision-json.sh"
    emit_deny "cwg-profile-load-error: could not load profile '$active_customer'"
    exit 0
fi

# ---------------------------------------------------------------------------
# 9. Delegate to window-decision
# ---------------------------------------------------------------------------

# shellcheck source=./window-decision.sh
source "${SCRIPT_DIR}/window-decision.sh"
decision_json="$(cwg_decide "$profile_json_path")"
decision="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["decision"])' <<< "$decision_json")"
rationale="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["rationale"])' <<< "$decision_json")"

# ---------------------------------------------------------------------------
# 10. Dispatch on decision
# ---------------------------------------------------------------------------

case "$decision" in
    allowed)
        exit 0
        ;;
    warning)
        printf 'yci change-window-gate [WARNING]: %s\n' "$rationale" >&2
        exit 0
        ;;
    blocked)
        if [[ "${YCI_CWG_DRY_RUN:-}" == "1" ]]; then
            printf 'yci change-window-gate [DRY-RUN-BLOCKED]: %s\n' "$rationale" >&2
            # Audit log append (best-effort; never fail the hook on log failure)
            log_dir="${data_root}/logs"
            mkdir -p "$log_dir" 2>/dev/null || true
            printf '%s  dry-run-blocked  %s  %s\n' \
                "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$tool_name" "$rationale" \
                >> "${log_dir}/change-window-gate.audit.log" 2>/dev/null || true
            exit 0
        fi
        # shellcheck source=../../customer-guard/scripts/decision-json.sh
        source "${CLAUDE_PLUGIN_ROOT}/hooks/customer-guard/scripts/decision-json.sh"
        emit_deny "cwg-destructive-in-blackout: $rationale"
        exit 0
        ;;
    *)
        # Unexpected decision value — fail closed
        # shellcheck source=../../customer-guard/scripts/decision-json.sh
        source "${CLAUDE_PLUGIN_ROOT}/hooks/customer-guard/scripts/decision-json.sh"
        emit_deny "cwg-internal-error: unexpected decision value '$decision' from window-decision; failing closed"
        exit 0
        ;;
esac
