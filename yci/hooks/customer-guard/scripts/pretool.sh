#!/usr/bin/env bash
# yci — customer-guard PreToolUse hook entrypoint.
#
# Called by Claude Code on every tool invocation. Reads a PreToolUse JSON
# payload on stdin and writes a Claude Code hook decision JSON on stdout.
# Exit 0 always (the decision is on stdout; non-zero = "hook errored" which
# Claude Code treats differently).
#
# Environment:
#   YCI_GUARD_FAIL_OPEN=1   — fail-open on resolver refusal (dev knob)
#   YCI_GUARD_DRY_RUN=1     — log would-be blocks to audit.log, emit allow
#   YCI_GUARD_STRICT=1      — fail-closed on missing tool_input fields
#
# See: yci/hooks/customer-guard/README.md for operator workflow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
YCI_ROOT="$(cd "${HOOK_ROOT}/../.." && pwd -P)"
REPO_ROOT="$(cd "${YCI_ROOT}/.." && pwd -P)"
YCC_ROOT="${REPO_ROOT}/ycc"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/decision-json.sh"

_payload_has_string_marker() {
    local payload="$1"
    local marker="$2"

    python3 - "$payload" "$marker" <<'PY'
import json
import sys


def walk(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from walk(item)
    elif isinstance(value, list):
        for item in value:
            yield from walk(item)


try:
    payload = json.loads(sys.argv[1])
except Exception:
    sys.exit(1)

marker = sys.argv[2].lower()
for value in walk(payload):
    if marker in value.lower():
        sys.exit(0)

sys.exit(1)
PY
}

_payload_is_yci_related() {
    local payload="$1"
    local extractor="${YCI_ROOT}/skills/_shared/customer-isolation/scripts/extract-paths.py"
    local path

    if _payload_has_string_marker "$payload" "/yci:"; then
        return 0
    fi
    if _payload_has_string_marker "$payload" "yci:"; then
        return 0
    fi

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$path" in
            "${YCI_ROOT}"|\
            "${YCI_ROOT}/"*|\
            "${YCI_DATA_ROOT_RESOLVED}"|\
            "${YCI_DATA_ROOT_RESOLVED}/"*)
                return 0
                ;;
        esac
    done < <(printf '%s' "$payload" | python3 "$extractor")

    return 1
}

_payload_is_ycc_related() {
    local payload="$1"
    local extractor="${YCI_ROOT}/skills/_shared/customer-isolation/scripts/extract-paths.py"
    local path

    if _payload_has_string_marker "$payload" "/ycc:"; then
        return 0
    fi
    if _payload_has_string_marker "$payload" "ycc:"; then
        return 0
    fi

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$path" in
            "${YCC_ROOT}"|\
            "${YCC_ROOT}/"*|\
            "${REPO_ROOT}/.codex-plugin/ycc"|\
            "${REPO_ROOT}/.codex-plugin/ycc/"*|\
            "${REPO_ROOT}/.cursor-plugin"|\
            "${REPO_ROOT}/.cursor-plugin/"*|\
            "${REPO_ROOT}/.opencode-plugin"|\
            "${REPO_ROOT}/.opencode-plugin/"*)
                return 0
                ;;
        esac
    done < <(printf '%s' "$payload" | python3 "$extractor")

    return 1
}

_bootstrap_marker_present() {
    local payload="$1"

    _payload_has_string_marker "$payload" "/yci:init" && return 0
    _payload_has_string_marker "$payload" "/yci:switch" && return 0

    python3 - "$payload" <<'PY'
import json
import sys


def walk(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from walk(item)
    elif isinstance(value, list):
        for item in value:
            yield from walk(item)


try:
    payload = json.loads(sys.argv[1])
except Exception:
    sys.exit(1)

for value in walk(payload):
    lowered = value.lower()
    if "yci:customer-profile" in lowered and ("init" in lowered or "switch" in lowered):
        sys.exit(0)

sys.exit(1)
PY
}

_bootstrap_payload_allowed_without_active_customer() {
    local payload="$1"
    local extractor="${YCI_ROOT}/skills/_shared/customer-isolation/scripts/extract-paths.py"
    local has_repo_bootstrap_path=0
    local has_any_path=0
    local path

    # This bootstrap lane is intentionally yci-only. It exists to let
    # /yci:init and /yci:switch establish an active customer; it must not
    # soften the no-active-customer posture for ycc or general tool calls.
    if _bootstrap_marker_present "$payload"; then
        return 0
    fi

    while IFS= read -r path; do
        [ -n "$path" ] || continue
        has_any_path=1
        case "$path" in
            "${YCI_ROOT}/commands/init.md"|\
            "${YCI_ROOT}/commands/switch.md"|\
            "${YCI_ROOT}/skills/customer-profile/SKILL.md"|\
            "${YCI_ROOT}/skills/customer-profile/"*|\
            "${YCI_ROOT}/skills/_shared/scripts/resolve-data-root.sh")
                has_repo_bootstrap_path=1
                ;;
            "${YCI_DATA_ROOT_RESOLVED}"|\
            "${YCI_DATA_ROOT_RESOLVED}/profiles"|\
            "${YCI_DATA_ROOT_RESOLVED}/profiles/"*|\
            "${YCI_DATA_ROOT_RESOLVED}/state.json"|\
            "${YCI_DATA_ROOT_RESOLVED}/.state.json."*)
                ;;
            *)
                return 1
                ;;
        esac
    done < <(printf '%s' "$payload" | python3 "$extractor")

    [ "$has_any_path" -eq 1 ] || return 1
    [ "$has_repo_bootstrap_path" -eq 1 ] || return 1
}

# ---------------------------------------------------------------------------
# 1. Read stdin payload
# ---------------------------------------------------------------------------

INPUT="$(cat)"

# ---------------------------------------------------------------------------
# 2. Resolve data root early so no-active-customer bootstrap checks can use it
# ---------------------------------------------------------------------------

RDR="${YCI_ROOT}/skills/_shared/scripts/resolve-data-root.sh"
if [ -x "$RDR" ]; then
    YCI_DATA_ROOT_RESOLVED="$(bash "$RDR" 2>/dev/null || true)"
fi
YCI_DATA_ROOT_RESOLVED="${YCI_DATA_ROOT_RESOLVED:-${YCI_DATA_ROOT:-$HOME/.config/yci}}"
export YCI_DATA_ROOT_RESOLVED

# ---------------------------------------------------------------------------
# 2.5. ycc is always exempt from customer enforcement.
# ---------------------------------------------------------------------------

if _payload_is_ycc_related "$INPUT"; then
    exit 0
fi

# ---------------------------------------------------------------------------
# 3. Resolve active customer via resolve-customer.sh
#    load-profile.sh + resolve-customer.sh live in yci/skills/customer-profile/scripts/.
# ---------------------------------------------------------------------------

RESOLVE="${YCI_ROOT}/skills/customer-profile/scripts/resolve-customer.sh"

# Capture resolver output + exit code without triggering set -e.
# bash 5.3 changed behaviour: a failing command substitution on the RHS of an
# assignment now fires `set -e` even though the assignment itself succeeds.
# The `|| ACTIVE_RC=$?` pattern suppresses that early-exit while preserving
# the exit code for the explicit check below.
ACTIVE_OUT=""; ACTIVE_RC=0
ACTIVE_OUT="$(bash "$RESOLVE" 2>&1)" || ACTIVE_RC=$?
if [ "$ACTIVE_RC" -ne 0 ]; then
    if ! _payload_is_yci_related "$INPUT"; then
        exit 0
    fi
    if _bootstrap_payload_allowed_without_active_customer "$INPUT"; then
        exit 0
    fi
    # Fail-open opt-in
    if [ "${YCI_GUARD_FAIL_OPEN:-0}" = "1" ]; then
        printf 'yci guard: resolver refused but YCI_GUARD_FAIL_OPEN=1; allowing.\n' >&2
        exit 0
    fi
    # Default: fail-closed — emit deny with guard-no-active-customer reason
    emit_deny "yci guard: no active customer; refusing to evaluate tool call fail-closed.
  set a customer with /yci:init <customer> or /yci:switch <customer>
  to allow evaluation without an active customer, set YCI_GUARD_FAIL_OPEN=1"
    exit 0
fi
# resolve-customer.sh prints the active customer id on stdout (one line)
YCI_ACTIVE_CUSTOMER="$(printf '%s' "$ACTIVE_OUT" | tr -d '[:space:]')"
export YCI_ACTIVE_CUSTOMER

# ---------------------------------------------------------------------------
# 4. Source detection library + evaluate
# ---------------------------------------------------------------------------

DETECT="${YCI_ROOT}/skills/_shared/customer-isolation/detect.sh"
# shellcheck source=/dev/null
source "$DETECT"

DECISION="$(printf '%s' "$INPUT" | isolation_check_payload)"

# ---------------------------------------------------------------------------
# 5. Decision handling
# ---------------------------------------------------------------------------

case "$DECISION" in
    *'"decision":"allow"'*)
        exit 0
        ;;
    *'"decision":"deny"'*)
        # Extract catalogued reason from the decision JSON
        REASON="$(printf '%s' "$DECISION" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
c = d.get("collision", {})
kind = c.get("kind", "?")
if kind == "path":
    active = c.get("active", "?")
    foreign = c.get("foreign", "?")
    evidence = c.get("evidence", "?")
    resolved = c.get("resolved", evidence)
    print(
        f"yci guard: cross-customer path collision.\n"
        f"  active customer:  {active}\n"
        f"  foreign customer: {foreign}\n"
        f"  offending path:   {evidence}\n"
        f"  resolved to:      {resolved}\n"
        f"To allow this path, add it to the active customer allowlist.yaml:\n"
        f"  paths:\n"
        f"    - {resolved}  # note: SOW/ticket reference required"
    )
elif kind == "token":
    active = c.get("active", "?")
    foreign = c.get("foreign", "?")
    category = c.get("category", "?")
    evidence = c.get("evidence", "?")
    print(
        f"yci guard: cross-customer identifier collision.\n"
        f"  active customer:  {active}\n"
        f"  foreign customer: {foreign}\n"
        f"  category:         {category}\n"
        f"  offending token:  {evidence}\n"
        f"To allow this token, add it to the active customer allowlist.yaml:\n"
        f"  tokens:\n"
        f"    - {evidence}  # note: SOW/ticket reference required"
    )
else:
    print("yci guard: collision (unknown kind)")
')"
        # Dry-run mode: log instead of deny
        if [ "${YCI_GUARD_DRY_RUN:-0}" = "1" ]; then
            AUDIT_DIR="${YCI_DATA_ROOT_RESOLVED}/.cache/customer-isolation"
            AUDIT_LOG="${AUDIT_DIR}/audit.log"
            mkdir -p "$AUDIT_DIR" 2>/dev/null || true
            printf '[%s] would-block: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$REASON" \
                >> "$AUDIT_LOG" 2>/dev/null || true
            printf 'YCI GUARD: DRY-RUN MODE ACTIVE — would-block logged to %s\n' "$AUDIT_LOG" >&2
            printf '  tool call would have been denied (collision detected)\n' >&2
            printf '  audit entry written to: %s\n' "$AUDIT_LOG" >&2
            printf '  set YCI_GUARD_DRY_RUN=0 or unset to enforce blocking\n' >&2
            export YCI_GUARD_DRY_RUN_HIT=1
            exit 0
        fi
        # Normal: emit deny JSON
        emit_deny "$REASON"
        exit 0
        ;;
    *)
        # Unexpected decision shape — fail-open with stderr warning
        printf 'yci guard: internal error — unexpected decision shape from isolation_check_payload\n' >&2
        printf '  got: %s\n' "$DECISION" >&2
        exit 0
        ;;
esac
