#!/usr/bin/env bash
# Adapter load + internal mode (hostname heuristic relaxed).

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${TESTS_DIR}/helpers.sh"

prof="$(mktemp)"
cleanup() { rm -f "$prof"; }
trap cleanup EXIT

printf '%s' '{"customer":{"id":"acme"}}' > "$prof"

# Without HIPAA adapter rules, SSN pattern should remain (not loaded)
out_commercial="$(python3 "${YCI_TELEMETRY_SCRIPTS_DIR}/sanitize_text.py" \
  --profile-json "$prof" \
  --yci-root "$YCI_PLUGIN_ROOT" \
  --regime none \
  --mode strict \
  "${TESTS_DIR}/fixtures/known-leak-corpus.txt")"
assert_contains "$out_commercial" "123-45-6789" "ssn_preserved_without_hipaa_adapter"

out_hipaa="$(python3 "${YCI_TELEMETRY_SCRIPTS_DIR}/sanitize_text.py" \
  --profile-json "$prof" \
  --yci-root "$YCI_PLUGIN_ROOT" \
  --regime hipaa \
  --mode strict \
  "${TESTS_DIR}/fixtures/known-leak-corpus.txt")"
assert_not_contains "$out_hipaa" "123-45-6789" "ssn_redacted_with_hipaa_adapter"

# internal mode: generic FQDN heuristic skipped — example.com should survive
sample='see https://example.com/path for docs'
out_int="$(printf '%s' "$sample" | python3 "${YCI_TELEMETRY_SCRIPTS_DIR}/sanitize_text.py" \
  --profile-json "$prof" \
  --yci-root "$YCI_PLUGIN_ROOT" \
  --regime none \
  --mode internal)"
assert_contains "$out_int" "example.com" "internal_mode_preserves_fqdn"

out_strict="$(printf '%s' "$sample" | python3 "${YCI_TELEMETRY_SCRIPTS_DIR}/sanitize_text.py" \
  --profile-json "$prof" \
  --yci-root "$YCI_PLUGIN_ROOT" \
  --regime none \
  --mode strict)"
assert_not_contains "$out_strict" "example.com" "strict_mode_redacts_fqdn"

[ "${YCI_TEST_FAIL:-0}" -eq 0 ] || exit 1
exit 0
