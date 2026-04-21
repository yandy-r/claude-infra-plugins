#!/usr/bin/env bash
# yci blast-radius test runner.
# Discovers test_*.sh in this directory, runs each, aggregates pass/fail counts,
# exits non-zero on any failure.
#
# Usage:
#   run-all.sh               # run every test
#   run-all.sh --verbose     # show per-assertion output
#   run-all.sh test_foo.sh   # run a specific test file

set -uo pipefail  # intentional: no -e here; tests handle their own failures

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${TESTS_DIR}/helpers.sh"

VERBOSE=0
FILTER=()
for arg in "$@"; do
    case "$arg" in
        --verbose|-v) VERBOSE=1 ;;
        test_*.sh)    FILTER+=("$arg") ;;
        *)            printf 'unknown arg: %s\n' "$arg" >&2; exit 2 ;;
    esac
done
export YCI_TEST_VERBOSE=$VERBOSE

if [ "${#FILTER[@]}" -eq 0 ]; then
    mapfile -t test_files < <(
        find "$TESTS_DIR" -maxdepth 1 -type f -name 'test_*.sh' -printf '%f\n' 2>/dev/null \
            | sort
    )
else
    test_files=("${FILTER[@]}")
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
