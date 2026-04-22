#!/usr/bin/env bash
# always-open change-window adapter — check.sh
#
# Never enforces a change window. Ignores all standard flags and always emits
# {"decision":"allowed",...}. Exit 0 unconditionally for known flags.
set -euo pipefail

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ts|--source|--timezone|--warn-before-minutes)
      shift 2 ;;
    --)
      shift; break ;;
    -*)
      printf 'always-open adapter: unknown flag: %s\n' "$1" >&2
      exit 1 ;;
    *)
      shift ;;
  esac
done

printf '%s\n' '{"decision":"allowed","rationale":"always-open adapter: no change-window enforced","adapter":"always-open","window_source":null}'
