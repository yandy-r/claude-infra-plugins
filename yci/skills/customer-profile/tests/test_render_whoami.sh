#!/usr/bin/env bash
# Tests for render-whoami.sh
# Covers: full profile render, minimal profile render, missing profile error.
#
# Runtime dependencies:
#   - helpers.sh  (task 5.2) — provides with_sandbox, assert_*, yci_test_summary
#   - ${YCI_SCRIPTS_DIR}/render-whoami.sh  (task 5.1)
#
# shellcheck disable=SC1091
# set -euo pipefail (removed: tests need explicit exit-code capture)
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

FIXTURES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/fixtures" && pwd -P 2>/dev/null \
    || printf '%s' "$(dirname "${BASH_SOURCE[0]}")/fixtures")"

# ---------------------------------------------------------------------------
# _install_fixture <sandbox> <customer-id> <fixture-filename>
#   Copies a fixture YAML into the sandbox's profiles/ directory.
# ---------------------------------------------------------------------------
_install_fixture() {
    local sb="$1" name="$2" src_file="$3"
    mkdir -p "$sb/real/profiles"
    cp "$FIXTURES_DIR/$src_file" "$sb/real/profiles/$name.yaml"
}

# ---------------------------------------------------------------------------
# test_whoami_full_profile
#   Rendering a fully-populated profile must exit 0 and surface key fields.
# ---------------------------------------------------------------------------
test_whoami_full_profile() {
    local sb="$1"
    _install_fixture "$sb" acme acme-example.yaml
    local out
    out="$("${YCI_SCRIPTS_DIR}/render-whoami.sh" "$sb/real" acme)"
    rc=$?
    assert_exit 0 "$rc" "whoami full: exit 0"
    assert_contains "$out" "acme"   "whoami full: shows customer id"
    assert_contains "$out" "hipaa"  "whoami full: shows compliance regime"
    assert_contains "$out" "review" "whoami full: shows safety posture"
}

# ---------------------------------------------------------------------------
# test_whoami_minimal_profile
#   Rendering a minimal (required-fields-only) profile must exit 0 and show id.
# ---------------------------------------------------------------------------
test_whoami_minimal_profile() {
    local sb="$1"
    _install_fixture "$sb" min minimal.yaml
    local out
    out="$("${YCI_SCRIPTS_DIR}/render-whoami.sh" "$sb/real" min)"
    rc=$?
    assert_exit 0 "$rc" "whoami minimal: exit 0"
    assert_contains "$out" "min" "whoami minimal: shows customer id"
}

# ---------------------------------------------------------------------------
# test_whoami_missing_profile
#   Requesting a nonexistent profile must exit 1 and say "not found".
# ---------------------------------------------------------------------------
test_whoami_missing_profile() {
    local sb="$1"
    "${YCI_SCRIPTS_DIR}/render-whoami.sh" "$sb/real" nonexistent \
        >/dev/null 2>"$sb/err"
    rc=$?
    assert_exit 1 "$rc" "whoami missing: exit 1"
    assert_contains "$(cat "$sb/err")" "not found" "whoami missing: phrase"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    with_sandbox test_whoami_full_profile
    with_sandbox test_whoami_minimal_profile
    with_sandbox test_whoami_missing_profile
    yci_test_summary
}

main
