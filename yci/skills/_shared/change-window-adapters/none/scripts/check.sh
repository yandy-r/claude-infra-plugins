#!/usr/bin/env bash
# yci change-window adapter: none
#
# Default decision: blocked. Allowed only when YCI_CWG_OVERRIDE=1.
# All scheduling flags are accepted but ignored — no schedule exists to evaluate.
#
# Exit codes: 0 success (decision emitted) | 1 usage error (unknown flag)

set -euo pipefail

# ---------------------------------------------------------------------------
# Flag parsing — consume known flags, reject unknown ones.
# ---------------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ts | --source | --timezone)
      [ -z "${2:-}" ] && { printf 'none adapter: %s requires a value\n' "$1" >&2; exit 1; }
      shift 2
      ;;
    --warn-before-minutes)
      [ -z "${2:-}" ] && { printf 'none adapter: %s requires a value\n' "$1" >&2; exit 1; }
      shift 2
      ;;
    --ts=* | --source=* | --timezone=* | --warn-before-minutes=*)
      shift
      ;;
    --)
      shift; break
      ;;
    -*)
      printf 'none adapter: unknown flag: %s\n' "$1" >&2
      exit 1
      ;;
    *)
      printf 'none adapter: unexpected argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Decision: keyed solely off YCI_CWG_OVERRIDE envvar.
# ---------------------------------------------------------------------------
if [ "${YCI_CWG_OVERRIDE:-}" = "1" ]; then
  printf '{"decision":"allowed","rationale":"none adapter: YCI_CWG_OVERRIDE=1 acknowledged","adapter":"none","window_source":null}\n'
else
  printf '{"decision":"blocked","rationale":"none adapter: explicit override required; set YCI_CWG_OVERRIDE=1 for this call","adapter":"none","window_source":null}\n'
fi

exit 0
