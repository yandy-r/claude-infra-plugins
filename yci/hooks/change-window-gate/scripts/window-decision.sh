#!/usr/bin/env bash
# yci — change-window-gate: window decision orchestrator.
#
# Sourceable library. Exports:
#   cwg_decide <profile_json_path> [ts_iso8601]
#
# Returns a change-window decision as a JSON object on stdout:
#   {"decision":"allowed|warning|blocked","rationale":"...","adapter":"...","window_source":...}
#
# Always exits 0. The JSON decision is the output; a "blocked" decision is the
# failure signal, not a non-zero exit code.
#
# No `set -euo pipefail` at file scope — this is a sourceable library.

# ---------------------------------------------------------------------------
# Resolve CLAUDE_PLUGIN_ROOT at source/load time.
# At runtime the harness sets CLAUDE_PLUGIN_ROOT; when invoked directly from
# the CLI we derive it: two levels up from yci/hooks/change-window-gate/scripts/
# lands at yci/.
# ---------------------------------------------------------------------------
CWG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Three levels up from yci/hooks/change-window-gate/scripts/ → yci/
CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$(dirname "$CWG_SCRIPT_DIR")")")}"

# ---------------------------------------------------------------------------
# Private helper: emit a blocked decision JSON.
# Usage: _cwg_emit_blocked <rationale> [adapter] [window_source]
# ---------------------------------------------------------------------------
_cwg_emit_blocked() {
    local rationale="${1:-unknown error}"
    local adapter="${2:-unknown}"
    local window_source="${3:-null}"
    python3 -c '
import json, sys
rationale = sys.argv[1]
adapter   = sys.argv[2]
ws_raw    = sys.argv[3]
window_source = None if ws_raw == "null" else ws_raw
print(json.dumps({
    "decision": "blocked",
    "rationale": rationale,
    "adapter":   adapter,
    "window_source": window_source,
}))
' "$rationale" "$adapter" "$window_source"
}

# ---------------------------------------------------------------------------
# cwg_decide <profile_json_path> [ts_iso8601]
# ---------------------------------------------------------------------------
cwg_decide() {
    local profile_json_path="${1:-}"
    local ts="${2:-}"

    if [[ -z "$ts" ]]; then
        ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi

    # ------------------------------------------------------------------
    # Step 1: YCI_CWG_OVERRIDE short-circuit.
    # ------------------------------------------------------------------
    if [[ "${YCI_CWG_OVERRIDE:-}" == "1" ]]; then
        printf '%s\n' '{"decision":"allowed","rationale":"YCI_CWG_OVERRIDE=1 acknowledged","adapter":"override","window_source":null}'
        return 0
    fi

    # ------------------------------------------------------------------
    # Step 2: Resolve adapter via dispatcher; write to a temp env file.
    # ------------------------------------------------------------------
    local tmp_env
    tmp_env="$(mktemp /tmp/cwg-$$.XXXXXX.env)"
    # Clean up temp file on function exit regardless of success/failure.
    # shellcheck disable=SC2064
    trap "rm -f '$tmp_env'" RETURN

    local dispatcher_stderr dispatcher_rc
    dispatcher_stderr="$(
        "${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/load-change-window-adapter.sh" \
            --profile-json-path "$profile_json_path" \
            --export-file "$tmp_env" \
            2>&1
    )" && dispatcher_rc=0 || dispatcher_rc=$?

    if [[ "$dispatcher_rc" -ne 0 ]]; then
        _cwg_emit_blocked \
            "cwg-adapter-load-failed: ${dispatcher_stderr:-exit code ${dispatcher_rc}}" \
            "unknown" \
            "null"
        return 0
    fi

    # Source the env file to get YCI_CW_ADAPTER_DIR and YCI_CW_ADAPTER_NAME.
    # shellcheck source=/dev/null
    source "$tmp_env"
    rm -f "$tmp_env"
    trap - RETURN

    # ------------------------------------------------------------------
    # Step 3: Extract change_window.source and change_window.timezone
    #         from the profile JSON.
    # ------------------------------------------------------------------
    local cw_fields source tz
    if ! cw_fields="$(python3 -c '
import json, sys, pathlib
d = json.loads(pathlib.Path(sys.argv[1]).read_text())
cw = d.get("change_window") or {}
print(cw.get("source") or "")
print(cw.get("timezone") or "UTC")
' "$profile_json_path" 2>&1)"; then
        _cwg_emit_blocked \
            "cwg-profile-load-error: ${cw_fields}" \
            "${YCI_CW_ADAPTER_NAME:-unknown}" \
            "null"
        return 0
    fi

    source="$(printf '%s\n' "$cw_fields" | sed -n '1p')"
    tz="$(printf '%s\n' "$cw_fields" | sed -n '2p')"

    # ------------------------------------------------------------------
    # Step 4: Invoke the adapter's check.sh.
    # ------------------------------------------------------------------
    local adapter_stdout adapter_stderr adapter_rc

    # Capture stdout and stderr separately; avoid set -e killing us on non-zero.
    local adapter_out_file adapter_err_file
    adapter_out_file="$(mktemp /tmp/cwg-adapter-out-$$.XXXXXX)"
    adapter_err_file="$(mktemp /tmp/cwg-adapter-err-$$.XXXXXX)"

    "${YCI_CW_ADAPTER_DIR}/scripts/check.sh" \
        --ts "$ts" \
        --source "$source" \
        --timezone "$tz" \
        >"$adapter_out_file" 2>"$adapter_err_file" && adapter_rc=0 || adapter_rc=$?

    adapter_stdout="$(< "$adapter_out_file")"
    adapter_stderr="$(< "$adapter_err_file")"
    rm -f "$adapter_out_file" "$adapter_err_file"

    # ------------------------------------------------------------------
    # Step 5: Validate adapter output.
    # ------------------------------------------------------------------
    if [[ "$adapter_rc" -eq 0 ]] && [[ -n "$adapter_stdout" ]]; then
        local validate_result
        if validate_result="$(printf '%s\n' "$adapter_stdout" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
assert d.get("decision") in ("allowed", "warning", "blocked"), "bad decision: " + repr(d.get("decision"))
print("ok")
' 2>&1)"; then
            # Valid — emit adapter JSON verbatim.
            printf '%s\n' "$adapter_stdout"
            return 0
        else
            _cwg_emit_blocked \
                "cwg-adapter-error: malformed adapter output: ${validate_result}" \
                "${YCI_CW_ADAPTER_NAME:-unknown}" \
                "null"
            return 0
        fi
    fi

    # Adapter non-zero exit or empty stdout.
    local err_summary
    if [[ -n "$adapter_stderr" ]]; then
        err_summary="$adapter_stderr"
    else
        err_summary="exit code ${adapter_rc}"
    fi

    _cwg_emit_blocked \
        "cwg-adapter-error: ${err_summary}" \
        "${YCI_CW_ADAPTER_NAME:-unknown}" \
        "null"
    return 0
}

# ---------------------------------------------------------------------------
# CLI entry point — skipped when sourced.
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    profile="${1:-}"
    ts="${2:-}"
    if [[ -z "$profile" ]]; then
        printf 'usage: %s <profile-json-path> [ts-iso8601]\n' "$0" >&2
        exit 1
    fi
    cwg_decide "$profile" "$ts"
fi
