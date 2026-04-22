#!/usr/bin/env bash
# yci — iCal change-window adapter: bash wrapper.
#
# Parses flags, validates inputs, resolves the source path, then delegates all
# calendar evaluation logic to ical_eval.py (stdlib-only Python).
#
# Usage:
#   check.sh --ts <iso8601> --source <path> [--timezone <iana>] [--warn-before-minutes <int>]
#
# Exit codes:
#   0 — decision JSON emitted on stdout (any of: allowed, warning, blocked)
#   1 — unknown flag or missing required flag (usage error)
#   2 — adapter config error (source file missing / unreadable; propagated from ical_eval.py)
#   3 — runtime error (python3 missing; propagated from ical_eval.py)

set -euo pipefail

# ---------------------------------------------------------------------------
# Locate this script's directory so we can find ical_eval.py next to it.
# ---------------------------------------------------------------------------
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
_ICAL_EVAL="${_SCRIPT_DIR}/ical_eval.py"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
_ts=""
_source=""
_timezone="UTC"
_warn_before_minutes="60"

# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ts)
      [ -z "${2:-}" ] && { printf 'ical adapter: --ts requires a value\n' >&2; exit 1; }
      _ts="$2"; shift 2 ;;
    --ts=*)
      _ts="${1#*=}"; shift ;;
    --source)
      [ -z "${2:-}" ] && { printf 'ical adapter: --source requires a value\n' >&2; exit 1; }
      _source="$2"; shift 2 ;;
    --source=*)
      _source="${1#*=}"; shift ;;
    --timezone)
      [ -z "${2:-}" ] && { printf 'ical adapter: --timezone requires a value\n' >&2; exit 1; }
      _timezone="$2"; shift 2 ;;
    --timezone=*)
      _timezone="${1#*=}"; shift ;;
    --warn-before-minutes)
      [ -z "${2:-}" ] && { printf 'ical adapter: --warn-before-minutes requires a value\n' >&2; exit 1; }
      _warn_before_minutes="$2"; shift 2 ;;
    --warn-before-minutes=*)
      _warn_before_minutes="${1#*=}"; shift ;;
    --)
      shift; break ;;
    -*)
      printf 'ical adapter: unknown flag: %s\n' "$1" >&2; exit 1 ;;
    *)
      printf 'ical adapter: unexpected argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate required flags
# ---------------------------------------------------------------------------
if [ -z "$_ts" ]; then
  printf 'ical adapter: --ts is required\n' >&2
  exit 1
fi

if [ -z "$_source" ]; then
  printf 'ical adapter: --source is required\n' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Resolve source to absolute path and verify it exists and is readable.
# ---------------------------------------------------------------------------
# Expand a leading ~/ or bare ~ to $HOME using string prefix stripping.
# (tilde is not expanded by the shell when the value is already in a variable)
if [ "${_source#\~/}" != "$_source" ]; then
  _source="${HOME}/${_source#\~/}"
elif [ "$_source" = "~" ]; then
  _source="${HOME}"
fi

# Convert to absolute path if relative.
if [[ "$_source" != /* ]]; then
  _source="$(pwd -P)/${_source}"
fi

if [ ! -f "$_source" ] || [ ! -r "$_source" ]; then
  printf 'ical adapter: source file not found or unreadable: %s\n' "$_source" >&2
  exit 2
fi

# Canonicalize.
_source="$(cd "$(dirname "$_source")" && pwd -P)/$(basename "$_source")"

# ---------------------------------------------------------------------------
# Verify python3 is available before delegating.
# ---------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  printf 'ical adapter: python3 not found in PATH\n' >&2
  exit 3
fi

# ---------------------------------------------------------------------------
# Delegate to ical_eval.py — propagate its exit code.
# ---------------------------------------------------------------------------
exec python3 "${_ICAL_EVAL}" \
  --ts "${_ts}" \
  --source "${_source}" \
  --timezone "${_timezone}" \
  --warn-before-minutes "${_warn_before_minutes}"
