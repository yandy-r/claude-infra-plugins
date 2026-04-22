#!/usr/bin/env bash
# yci change-window-gate test runner.
# Discovers test_*.sh in this directory, runs each in a fresh tmp sandbox,
# aggregates pass/fail counts, exits non-zero on any failure.
#
# Usage:
#   run-all.sh               # run every test
#   run-all.sh --verbose     # show per-assertion output
#   run-all.sh -f <pattern>  # run tests matching basename glob
#   run-all.sh test_foo.sh   # run a specific test file

set -uo pipefail  # intentional: no -e here; tests handle their own failures

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${TESTS_DIR}/helpers.sh"

VERBOSE=0
FILTER=()
i=0
args=("$@")
while [ "$i" -lt "${#args[@]}" ]; do
    arg="${args[$i]}"
    case "$arg" in
        --verbose|-v)
            VERBOSE=1
            ;;
        -f)
            i=$((i + 1))
            [ "$i" -ge "${#args[@]}" ] && { printf '-f requires a pattern\n' >&2; exit 2; }
            FILTER+=("${args[$i]}")
            ;;
        test_*.sh)
            FILTER+=("$arg")
            ;;
        *)
            printf 'unknown arg: %s\n' "$arg" >&2; exit 2
            ;;
    esac
    i=$((i + 1))
done
export YCI_TEST_VERBOSE=$VERBOSE

if [ "${#FILTER[@]}" -eq 0 ]; then
    mapfile -t test_files < <(
        find "$TESTS_DIR" -maxdepth 1 -type f -name 'test_*.sh' -printf '%f\n' 2>/dev/null \
            | sort
    )
else
    # Expand glob patterns against actual files
    test_files=()
    for pattern in "${FILTER[@]}"; do
        mapfile -t matched < <(
            find "$TESTS_DIR" -maxdepth 1 -type f -name "$pattern" -printf '%f\n' 2>/dev/null \
                | sort
        )
        if [ "${#matched[@]}" -eq 0 ]; then
            printf 'warning: no test files match pattern: %s\n' "$pattern" >&2
        else
            test_files+=("${matched[@]}")
        fi
    done
fi

pass=0; fail=0; files_run=0
for tf in "${test_files[@]}"; do
    files_run=$((files_run + 1))
    printf '=== %s ===\n' "$tf"
    if bash "${TESTS_DIR}/${tf}"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
    fi
done

printf '\n'
printf 'tests: %d files  pass=%d  fail=%d\n' "$files_run" "$pass" "$fail"
[ "$fail" -eq 0 ]
