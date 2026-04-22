#!/usr/bin/env bash
# yci — json-schedule change-window adapter entry point.
#
# Reads a JSON blackout-calendar file, compares a proposed UTC timestamp
# against the blackout list, and emits a one-line JSON decision.
#
# Usage:
#   check.sh --ts <iso8601-utc> --source <path> [--timezone <tz>] [--warn-before-minutes <int>]
#
# Flags:
#   --ts <iso8601>           Required. Proposed change timestamp in UTC ISO-8601.
#   --source <path>          Required. Path to the JSON blackout-calendar file.
#   --timezone <tz>          Optional. IANA timezone for human-readable rationale. Default: UTC.
#   --warn-before-minutes N  Optional. Override warn_before_minutes from the calendar file.
#
# Output (stdout): exactly one JSON line:
#   {"decision":"allowed|warning|blocked","rationale":"<string>","adapter":"json-schedule","window_source":"<abs-path>"}
#
# Exit codes:
#   0 — decision emitted successfully
#   2 — source missing / unreadable / malformed JSON / schema violation
#   3 — runtime error (e.g. python3 not found)

set -euo pipefail

_TS=""
_SOURCE=""
_TIMEZONE="UTC"
_WARN_BEFORE_MINUTES=""

# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
    case "$1" in
        --ts)
            [ -z "${2:-}" ] && { printf 'json-schedule adapter: --ts requires a value\n' >&2; exit 2; }
            _TS="$2"; shift 2 ;;
        --ts=*)
            _TS="${1#*=}"; shift ;;
        --source)
            [ -z "${2:-}" ] && { printf 'json-schedule adapter: --source requires a value\n' >&2; exit 2; }
            _SOURCE="$2"; shift 2 ;;
        --source=*)
            _SOURCE="${1#*=}"; shift ;;
        --timezone)
            [ -z "${2:-}" ] && { printf 'json-schedule adapter: --timezone requires a value\n' >&2; exit 2; }
            _TIMEZONE="$2"; shift 2 ;;
        --timezone=*)
            _TIMEZONE="${1#*=}"; shift ;;
        --warn-before-minutes)
            [ -z "${2:-}" ] && { printf 'json-schedule adapter: --warn-before-minutes requires a value\n' >&2; exit 2; }
            _WARN_BEFORE_MINUTES="$2"; shift 2 ;;
        --warn-before-minutes=*)
            _WARN_BEFORE_MINUTES="${1#*=}"; shift ;;
        --)
            shift; break ;;
        -*)
            printf 'json-schedule adapter: unknown flag: %s\n' "$1" >&2; exit 2 ;;
        *)
            printf 'json-schedule adapter: unexpected argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Required flag validation
# ---------------------------------------------------------------------------
if [ -z "$_TS" ]; then
    printf 'json-schedule adapter: --ts is required\n' >&2
    exit 2
fi

if [ -z "$_SOURCE" ]; then
    printf 'json-schedule adapter: --source is required\n' >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Source file existence check
# ---------------------------------------------------------------------------
if [ ! -f "$_SOURCE" ] || [ ! -r "$_SOURCE" ]; then
    printf 'json-schedule adapter: source file not found or unreadable: %s\n' "$_SOURCE" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Resolve python3
# ---------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
    printf 'json-schedule adapter: python3 not found in PATH\n' >&2
    exit 3
fi

# ---------------------------------------------------------------------------
# Delegate to schedule_eval.py
# ---------------------------------------------------------------------------
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
_EVAL_PY="${_SCRIPT_DIR}/schedule_eval.py"

if [ ! -f "$_EVAL_PY" ]; then
    printf 'json-schedule adapter: schedule_eval.py not found at %s\n' "$_EVAL_PY" >&2
    exit 3
fi

_ARGS=(--ts "$_TS" --source "$_SOURCE" --timezone "$_TIMEZONE")
if [ -n "$_WARN_BEFORE_MINUTES" ]; then
    _ARGS+=(--warn-before-minutes "$_WARN_BEFORE_MINUTES")
fi

exec python3 "$_EVAL_PY" "${_ARGS[@]}"
