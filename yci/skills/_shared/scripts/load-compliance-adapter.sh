#!/usr/bin/env bash
# yci — resolve a customer profile's compliance.regime to the matching adapter
# directory on disk. Source to expose yci_load_compliance_adapter(), or run directly.
#
# Usage: load-compliance-adapter.sh [--export | --export-file PATH] [--profile-json-path PATH | --regime REGIME]
#   --profile-json-path PATH  Read profile JSON from file (mutually exclusive with --regime).
#   --regime REGIME           Use this regime directly (bypasses JSON parsing).
#   --export                  Emit shell-safe export lines for YCI_ADAPTER_* variables.
#   --export-file PATH        Write shell-safe export lines to PATH for later sourcing.
#   Default input: stdin (profile JSON).
#
# Exit codes: 0 success | 1 usage error | 2 unknown/empty regime | 3 dir missing | 4 incomplete

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve CLAUDE_PLUGIN_ROOT — walk up from this script until "yci/" is found.
# ---------------------------------------------------------------------------
_yci_find_plugin_root() {
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
    CLAUDE_PLUGIN_ROOT="$(_yci_find_plugin_root)"
fi

# Source profile-schema.sh — provides YCI_COMPLIANCE_REGIMES.
# shellcheck source=/dev/null
. "${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/profile-schema.sh"

# Source adapter-schema.sh — provides the contract constants and helpers.
# Falls back to built-in defaults mirroring adapter-schema.sh exactly, so the
# loader remains safe if the library is ever missing.
_ADAPTER_SCHEMA_LIB="${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/adapter-schema.sh"
if [ -r "${_ADAPTER_SCHEMA_LIB}" ]; then
    # shellcheck source=/dev/null
    . "${_ADAPTER_SCHEMA_LIB}"
else
    printf 'yci: warning: adapter-schema.sh not found; using built-in defaults\n' >&2
    YCI_ADAPTER_REQUIRED_FILES=(ADAPTER.md)
    YCI_ADAPTER_PHASE1_FILES=(evidence-template.md handoff-checklist.md)
    YCI_ADAPTER_PHASE1_REGIMES=(commercial none)
    YCI_ADAPTER_SCHEMA_EXEMPT=(none)
fi

_YCI_ADAPTER_ROOT="${CLAUDE_PLUGIN_ROOT}/skills/_shared/compliance-adapters"

# Helper: return 0 if needle is in the remaining args.
_yci_in_array() {
    local needle="$1"; shift
    local item
    for item in "$@"; do [ "$item" = "$needle" ] && return 0; done
    return 1
}

# ---------------------------------------------------------------------------
# yci_load_compliance_adapter [--export] [--profile-json-path PATH] [--regime REGIME]
# ---------------------------------------------------------------------------
yci_load_compliance_adapter() {
    local do_export=0
    local export_file_path=""
    local profile_json_path=""
    local regime_direct=""

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
            --regime)
                [ -z "${2:-}" ] && { printf 'yci: --regime requires a value\n' >&2; return 1; }
                regime_direct="$2"; shift 2 ;;
            --regime=*)
                regime_direct="${1#*=}"; shift ;;
            --) shift; break ;;
            -*) printf 'yci: unknown flag: %s\n' "$1" >&2; return 1 ;;
            *)  printf 'yci: unexpected argument: %s\n' "$1" >&2; return 1 ;;
        esac
    done

    if [ "$do_export" -eq 1 ] && [ -n "$export_file_path" ]; then
        printf 'yci: both --export and --export-file supplied; pick one\n' >&2
        return 1
    fi

    if [ -n "$profile_json_path" ] && [ -n "$regime_direct" ]; then
        printf 'yci: both --profile-json-path and --regime supplied; pick one\n' >&2
        return 1
    fi

    local regime=""

    if [ -n "$regime_direct" ]; then
        regime="$regime_direct"
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

        regime="$(printf '%s\n' "$json_input" | \
            python3 -c \
            'import json,sys; d=json.load(sys.stdin); print(d.get("compliance",{}).get("regime",""))' \
            2>&1)" || {
            printf 'yci: failed to parse profile JSON: %s\n' "$regime" >&2
            return 1
        }

        if [ -z "$regime" ]; then
            printf 'yci: profile JSON has no .compliance.regime field\n' >&2
            return 2
        fi
    fi

    if ! _yci_in_array "$regime" "${YCI_COMPLIANCE_REGIMES[@]}"; then
        local valid_list
        valid_list="$(printf '%s, ' "${YCI_COMPLIANCE_REGIMES[@]}")"
        valid_list="${valid_list%, }"
        printf 'yci: unknown compliance regime '\''%s'\'' (valid: %s)\n' "$regime" "$valid_list" >&2
        return 2
    fi

    local adapter_dir="${_YCI_ADAPTER_ROOT}/${regime}"

    if [ ! -d "$adapter_dir" ]; then
        printf 'yci: compliance adapter not installed: %s\n' "$adapter_dir" >&2
        return 3
    fi

    adapter_dir="$(cd "$adapter_dir" && pwd -P)"

    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if [ ! -f "${adapter_dir}/${f}" ]; then
            printf 'yci: adapter at %s is incomplete: missing %s\n' "$adapter_dir" "$f" >&2
            return 4
        fi
    done < <(yci_adapter_expected_files "$regime")

    if yci_adapter_requires_evidence_schema "$regime"; then
        if [ ! -f "${adapter_dir}/evidence-schema.json" ]; then
            printf 'yci: adapter at %s is incomplete: missing evidence-schema.json\n' "$adapter_dir" >&2
            return 4
        fi
    fi

    if yci_adapter_requires_redaction_rules "$regime"; then
        local first_rule=""
        IFS= read -r first_rule < <(find "${adapter_dir}" -maxdepth 1 -type f -name '*-redaction.rules' -print -quit)
        if [ -z "${first_rule}" ]; then
            printf 'yci: adapter at %s is incomplete: missing *-redaction.rules\n' "$adapter_dir" >&2
            return 4
        fi
    fi

    local has_schema=0
    [ -f "${adapter_dir}/evidence-schema.json" ] && has_schema=1

    if [ -n "$export_file_path" ]; then
        if ! {
            printf 'export YCI_ADAPTER_DIR=%q\n' "$adapter_dir"
            printf 'export YCI_ADAPTER_REGIME=%q\n' "$regime"
            printf 'export YCI_ADAPTER_HAS_SCHEMA=%q\n' "$has_schema"
        } > "$export_file_path"; then
            printf 'yci: cannot write export file: %s\n' "$export_file_path" >&2
            return 1
        fi
        chmod 0600 "$export_file_path" 2>/dev/null || true
        return 0
    fi

    if [ "$do_export" -eq 1 ]; then
        printf 'export YCI_ADAPTER_DIR=%q\n' "$adapter_dir"
        printf 'export YCI_ADAPTER_REGIME=%q\n' "$regime"
        printf 'export YCI_ADAPTER_HAS_SCHEMA=%q\n' "$has_schema"
    else
        printf '%s\n' "$adapter_dir"
    fi
}

# Standalone entry point — skipped when sourced (mirrors resolve-data-root.sh idiom).
if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
    yci_load_compliance_adapter "$@"
fi
