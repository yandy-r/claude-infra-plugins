#!/usr/bin/env bash
# Unit tests: core pattern redaction + known-leak corpus.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${TESTS_DIR}/helpers.sh"

prof="$(mktemp)"
cleanup() { rm -f "$prof"; }
trap cleanup EXIT

printf '%s' '{"customer":{"id":"acme-corp"}}' > "$prof"

corpus="${TESTS_DIR}/fixtures/known-leak-corpus.txt"
out="$(python3 "${YCI_TELEMETRY_SCRIPTS_DIR}/sanitize_text.py" \
  --profile-json "$prof" \
  --yci-root "$YCI_PLUGIN_ROOT" \
  --regime hipaa \
  --mode strict \
  "$corpus")"

assert_not_contains "$out" "VerySecretTokenValue123" "secrets_kv_redacted"
assert_not_contains "$out" "AKIAIOSFODNN7EXAMPLE" "aws_access_key_redacted"
assert_not_contains "$out" "123456789012" "aws_account_redacted"
assert_not_contains "$out" "10.0.0.1" "ipv4_redacted"
assert_not_contains "$out" "aa:bb:cc:dd:ee:ff" "mac_redacted"
assert_contains "$out" "[REDACTED_ASN]" "asn_redacted_marker"
assert_not_contains "$out" "12345678-1234-1234-1234-123456789abc" "azure_guid_redacted"
assert_not_contains "$out" "app.acme-corp.example.com" "customer_slug_host_redacted"
assert_not_contains "$out" "123-45-6789" "ssn_redacted_via_hipaa_adapter"
assert_not_contains "$out" "123456789" "mrn_digits_redacted"

# IPv6 compressed form from corpus
assert_not_contains "$out" "2001:db8::1" "ipv6_redacted"

[ "${YCI_TEST_FAIL:-0}" -eq 0 ] || exit 1
exit 0
