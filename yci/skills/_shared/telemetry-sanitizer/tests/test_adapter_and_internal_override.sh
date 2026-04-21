#!/usr/bin/env bash
# Adapter load + internal mode (hostname heuristic relaxed).

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${TESTS_DIR}/helpers.sh"

_preflight_sanitize_text() {
    local prof_path="$1"
    local missing=0

    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s\n' "error: required command not found: python3" >&2
        missing=1
    fi

    local san="${YCI_TELEMETRY_SCRIPTS_DIR}/sanitize_text.py"
    if [ ! -f "$san" ]; then
        printf '%s\n' "error: missing sanitize script: ${san} (sanitize_text.py)" >&2
        missing=1
    elif [ ! -x "$san" ]; then
        printf '%s\n' "error: sanitize script is not executable: ${san} (sanitize_text.py)" >&2
        missing=1
    fi

    if [ ! -r "$prof_path" ]; then
        printf '%s\n' "error: profile JSON not readable: ${prof_path} (\$prof)" >&2
        missing=1
    fi

    local fixture="${TESTS_DIR}/fixtures/known-leak-corpus.txt"
    if [ ! -r "$fixture" ]; then
        printf '%s\n' "error: fixture not readable: ${fixture} (known-leak-corpus.txt)" >&2
        missing=1
    fi

    if [ ! -e "$YCI_PLUGIN_ROOT" ]; then
        printf '%s\n' "error: YCI_PLUGIN_ROOT path does not exist: ${YCI_PLUGIN_ROOT}" >&2
        missing=1
    fi

    [ "$missing" -eq 0 ] || exit 1
}

prof="$(mktemp)"
cleanup() { rm -f "$prof"; }
trap cleanup EXIT

printf '%s' '{"customer":{"id":"acme"}}' > "$prof"

# Without HIPAA adapter rules, SSN pattern should remain (not loaded)
_preflight_sanitize_text "$prof"
out_commercial="$(python3 "${YCI_TELEMETRY_SCRIPTS_DIR}/sanitize_text.py" \
  --profile-json "$prof" \
  --yci-root "$YCI_PLUGIN_ROOT" \
  --regime none \
  --mode strict \
  "${TESTS_DIR}/fixtures/known-leak-corpus.txt")"
assert_contains "$out_commercial" "123-45-6789" "ssn_preserved_without_hipaa_adapter"

_preflight_sanitize_text "$prof"
out_hipaa="$(python3 "${YCI_TELEMETRY_SCRIPTS_DIR}/sanitize_text.py" \
  --profile-json "$prof" \
  --yci-root "$YCI_PLUGIN_ROOT" \
  --regime hipaa \
  --mode strict \
  "${TESTS_DIR}/fixtures/known-leak-corpus.txt")"
assert_not_contains "$out_hipaa" "123-45-6789" "ssn_redacted_with_hipaa_adapter"

# internal mode: generic FQDN heuristic skipped — example.com should survive
sample='see https://example.com/path for docs'
_preflight_sanitize_text "$prof"
out_int="$(printf '%s' "$sample" | python3 "${YCI_TELEMETRY_SCRIPTS_DIR}/sanitize_text.py" \
  --profile-json "$prof" \
  --yci-root "$YCI_PLUGIN_ROOT" \
  --regime none \
  --mode internal)"
assert_contains "$out_int" "example.com" "internal_mode_preserves_fqdn"

_preflight_sanitize_text "$prof"
out_strict="$(printf '%s' "$sample" | python3 "${YCI_TELEMETRY_SCRIPTS_DIR}/sanitize_text.py" \
  --profile-json "$prof" \
  --yci-root "$YCI_PLUGIN_ROOT" \
  --regime none \
  --mode strict)"
assert_not_contains "$out_strict" "example.com" "strict_mode_redacts_fqdn"

[ "${YCI_TEST_FAIL:-0}" -eq 0 ] || exit 1
exit 0
