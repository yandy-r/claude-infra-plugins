#!/usr/bin/env bash
# yci — dispatcher for change-window adapters.
#
# Resolves `change_window.adapter` → `${CLAUDE_PLUGIN_ROOT}/skills/_shared/change-window-adapters/<name>/`
# and validates required files. Mirrors load-compliance-adapter.sh.
# Sourceable AND directly invokable as a CLI.
#
# Usage: load-change-window-adapter.sh [--export | --export-file PATH] [--profile-json-path PATH | --adapter NAME]
#   --profile-json-path PATH  Read profile JSON from file (mutually exclusive with --adapter).
#   --adapter NAME            Use this adapter name directly (bypasses JSON parsing).
#   --export                  Emit shell-safe export lines for YCI_CW_ADAPTER_* variables.
#   --export-file PATH        Write shell-safe export lines to PATH for later sourcing.
#   Default output: print resolved adapter directory path to stdout.
#
# Exit codes: 0 success | 1 usage error | 2 unknown/empty adapter | 3 dir missing | 4 incomplete
#             5 deferred adapter (not yet implemented in Phase 0)

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve CLAUDE_PLUGIN_ROOT — walk up from this script until "yci/" is found.
# ---------------------------------------------------------------------------
_yci_cw_find_plugin_root() {
    local dir
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    while [ "$dir" != "/" ]; do
        [ "$(basename "$dir")" = "yci" ] && printf '%s\n' "$dir" && return 0
        dir="$(dirname "$dir")"
    done
    printf 'yci: cannot locate yci plugin root from %s\n' "$(dirname "${BASH_SOURCE[0]}")" >&2
    return 1
}

if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    CLAUDE_PLUGIN_ROOT="$(_yci_cw_find_plugin_root)"
fi

# Source change-window-adapter-schema.sh — provides YCI_CW_ADAPTERS_SHIPPED,
# YCI_CW_ADAPTERS_DEFERRED, YCI_CW_ADAPTER_REQUIRED_FILES, and helpers.
# Falls back to built-in defaults mirroring change-window-adapter-schema.sh exactly,
# so the loader remains safe if the library is ever missing.
# shellcheck source=./change-window-adapter-schema.sh
_CW_ADAPTER_SCHEMA_LIB="${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/change-window-adapter-schema.sh"
if [ -r "${_CW_ADAPTER_SCHEMA_LIB}" ]; then
    # shellcheck source=/dev/null
    . "${_CW_ADAPTER_SCHEMA_LIB}"
else
    printf 'yci: warning: change-window-adapter-schema.sh not found; using built-in defaults\n' >&2
    # These arrays are defined here as fallback defaults; callers that source this file
    # read them. shellcheck can't see the external consumption.
    # shellcheck disable=SC2034
    YCI_CW_ADAPTERS_SHIPPED=(ical json-schedule always-open none)
    # shellcheck disable=SC2034
    YCI_CW_ADAPTERS_DEFERRED=(servicenow-cab)
    # shellcheck disable=SC2034
    YCI_CW_ADAPTER_REQUIRED_FILES=(ADAPTER.md scripts/check.sh)
fi

_YCI_CW_ADAPTER_ROOT="${CLAUDE_PLUGIN_ROOT}/skills/_shared/change-window-adapters"

# Helper: return 0 if needle is in the remaining args.
_yci_cw_in_array() {
    local needle="$1"; shift
    local item
    for item in "$@"; do [ "$item" = "$needle" ] && return 0; done
    return 1
}

# ---------------------------------------------------------------------------
# yci_load_change_window_adapter [--export] [--profile-json-path PATH] [--adapter NAME]
# ---------------------------------------------------------------------------
yci_load_change_window_adapter() {
    local do_export=0
    local export_file_path=""
    local profile_json_path=""
    local adapter_direct=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --export)
                do_export=1; shift ;;
            --export-file)
                [ -z "${2:-}" ] && { printf 'yci: --export-file requires a value\n' >&2; return 1; }
                export_file_path="$2"; shift 2 ;;
            --export-file=*)
                [ -z "${1#*=}" ] && { printf 'yci: --export-file requires a value\n' >&2; return 1; }
                export_file_path="${1#*=}"; shift ;;
            --profile-json-path)
                [ -z "${2:-}" ] && { printf 'yci: --profile-json-path requires a value\n' >&2; return 1; }
                profile_json_path="$2"; shift 2 ;;
            --profile-json-path=*)
                profile_json_path="${1#*=}"; shift ;;
            --adapter)
                [ -z "${2:-}" ] && { printf 'yci: --adapter requires a value\n' >&2; return 1; }
                adapter_direct="$2"; shift 2 ;;
            --adapter=*)
                adapter_direct="${1#*=}"; shift ;;
            --) shift; break ;;
            -*) printf 'yci: unknown flag: %s\n' "$1" >&2; return 1 ;;
            *)  printf 'yci: unexpected argument: %s\n' "$1" >&2; return 1 ;;
        esac
    done

    if [ "$do_export" -eq 1 ] && [ -n "$export_file_path" ]; then
        printf 'yci: both --export and --export-file supplied; pick one\n' >&2
        return 1
    fi

    if [ -n "$profile_json_path" ] && [ -n "$adapter_direct" ]; then
        printf 'yci: both --profile-json-path and --adapter supplied; pick one\n' >&2
        return 1
    fi

    local adapter=""

    if [ -n "$adapter_direct" ]; then
        adapter="$adapter_direct"
    else
        local json_input
        if [ -n "$profile_json_path" ]; then
            if [ ! -r "$profile_json_path" ]; then
                printf 'yci: cannot read profile JSON: %s\n' "$profile_json_path" >&2
                return 1
            fi
            json_input="$(< "$profile_json_path")"
        else
            json_input="$(cat)"
        fi

        # Check whether change_window block is present and extract adapter.
        # Also read safety.change_window_required for the missing-block fallback.
        local cw_parse_result
        cw_parse_result="$(printf '%s\n' "$json_input" | \
            python3 -c \
            'import json,sys
d=json.load(sys.stdin)
cw=d.get("change_window")
if cw is None:
    cw_req=d.get("safety",{}).get("change_window_required",False)
    print("MISSING_CW:" + ("true" if cw_req else "false"))
else:
    print(cw.get("adapter",""))
' \
            2>&1)" || {
            printf 'yci: failed to parse profile JSON: %s\n' "$cw_parse_result" >&2
            return 4
        }

        # Handle missing change_window block.
        if [[ "$cw_parse_result" == MISSING_CW:* ]]; then
            local cw_required="${cw_parse_result#MISSING_CW:}"
            if [ "$cw_required" = "true" ]; then
                printf 'yci: profile JSON has no change_window block but safety.change_window_required=true\n' >&2
                return 4
            else
                printf 'load-change-window-adapter: profile has no change_window block; defaulting to always-open (safety.change_window_required=false)\n' >&2
                adapter="always-open"
            fi
        else
            adapter="$cw_parse_result"
        fi

        if [ -z "$adapter" ]; then
            printf 'yci: profile JSON has no .change_window.adapter field\n' >&2
            return 2
        fi
    fi

    # Check for deferred adapters first (before the shipped-list check).
    if _yci_cw_in_array "$adapter" "${YCI_CW_ADAPTERS_DEFERRED[@]}"; then
        printf "load-change-window-adapter: adapter '%s' is deferred (PRD §11.4); not yet implemented in Phase 0. See yci/CONTRIBUTING.md.\n" "$adapter" >&2
        return 5
    fi

    if ! _yci_cw_in_array "$adapter" "${YCI_CW_ADAPTERS_SHIPPED[@]}"; then
        local valid_list
        valid_list="$(printf '%s, ' "${YCI_CW_ADAPTERS_SHIPPED[@]}" "${YCI_CW_ADAPTERS_DEFERRED[@]}")"
        valid_list="${valid_list%, }"
        printf 'yci: unknown change-window adapter '\''%s'\'' (valid: %s)\n' "$adapter" "$valid_list" >&2
        return 2
    fi

    local adapter_dir="${_YCI_CW_ADAPTER_ROOT}/${adapter}"

    if [ ! -d "$adapter_dir" ]; then
        printf 'yci: change-window adapter not installed: %s\n' "$adapter_dir" >&2
        return 3
    fi

    adapter_dir="$(cd "$adapter_dir" && pwd -P)"

    local f missing_files=()
    for f in "${YCI_CW_ADAPTER_REQUIRED_FILES[@]}"; do
        if [ ! -f "${adapter_dir}/${f}" ]; then
            missing_files+=("$f")
        fi
    done

    if [ "${#missing_files[@]}" -gt 0 ]; then
        local mf
        for mf in "${missing_files[@]}"; do
            printf 'yci: adapter at %s is incomplete: missing %s\n' "$adapter_dir" "$mf" >&2
        done
        return 4
    fi

    if [ -n "$export_file_path" ]; then
        if ! {
            printf 'export YCI_CW_ADAPTER_DIR=%q\n' "$adapter_dir"
            printf 'export YCI_CW_ADAPTER_NAME=%q\n' "$adapter"
        } > "$export_file_path"; then
            printf 'yci: cannot write export file: %s\n' "$export_file_path" >&2
            return 1
        fi
        chmod 0600 "$export_file_path" 2>/dev/null || true
        return 0
    fi

    if [ "$do_export" -eq 1 ]; then
        printf 'export YCI_CW_ADAPTER_DIR=%q\n' "$adapter_dir"
        printf 'export YCI_CW_ADAPTER_NAME=%q\n' "$adapter"
    else
        printf '%s\n' "$adapter_dir"
    fi
}

# Standalone entry point — skipped when sourced (mirrors resolve-data-root.sh idiom).
if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
    yci_load_change_window_adapter "$@"
fi
