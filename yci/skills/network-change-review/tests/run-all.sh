#!/usr/bin/env bash
# yci network-change-review test runner.
# Discovers test_*.sh in this directory, runs each, aggregates pass/fail counts,
# exits non-zero on any failure.
#
# Usage:
#   run-all.sh               # run every test
#   run-all.sh --verbose     # show per-assertion output
#   run-all.sh test_foo.sh   # run a specific test file

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HELPERS="${TESTS_DIR}/helpers.sh"
if [[ ! -f "$HELPERS" || ! -r "$HELPERS" ]]; then
    printf 'run-all.sh: missing or unreadable helpers: %s\n' "$HELPERS" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$HELPERS"

VERBOSE=0
FILTER=()
for arg in "$@"; do
    case "$arg" in
        --verbose|-v) VERBOSE=1 ;;
        test_*.sh)    FILTER+=("$arg") ;;
        *)            printf 'unknown arg: %s\n' "$arg" >&2; exit 1 ;;
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

for tf in "${test_files[@]}"; do
    path="${TESTS_DIR}/${tf}"
    if [[ ! -f "$path" ]]; then
        printf 'run-all.sh: test file not found: %s\n' "$path" >&2
        exit 1
    fi
    if [[ ! -r "$path" ]]; then
        printf 'run-all.sh: test file not readable: %s\n' "$path" >&2
        exit 1
    fi
    if [[ ! -x "$path" ]]; then
        printf 'run-all.sh: test file not executable: %s\n' "$path" >&2
        exit 1
    fi
done

if [ "${#test_files[@]}" -eq 0 ]; then
    printf 'no tests found in %s\n' "$TESTS_DIR"
    exit 0
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
