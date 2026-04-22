#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HELPERS="${TESTS_DIR}/helpers.sh"
if [[ ! -r "${HELPERS}" ]]; then
    printf 'run-all.sh: missing or unreadable helpers.sh at %s\n' "${HELPERS}" >&2
    exit 1
fi
source "${HELPERS}"

VERBOSE=0
FILTER=()
for arg in "$@"; do
    case "$arg" in
        --verbose|-v) VERBOSE=1 ;;
        test_*.sh) FILTER+=("$arg") ;;
        *) printf 'unknown arg: %s\n' "$arg" >&2; exit 1 ;;
    esac
done
export YCI_TEST_VERBOSE="${VERBOSE}"

if [ "${#FILTER[@]}" -eq 0 ]; then
    mapfile -t test_files < <(find "${TESTS_DIR}" -maxdepth 1 -type f -name 'test_*.sh' -printf '%f\n' | sort)
else
    test_files=("${FILTER[@]}")
fi

pass=0
fail=0
for tf in "${test_files[@]}"; do
    printf '=== %s ===\n' "${tf}"
    if bash "${TESTS_DIR}/${tf}"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
    fi
done

printf '\n'
printf 'tests: %d files  pass=%d  fail=%d\n' "${#test_files[@]}" "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
