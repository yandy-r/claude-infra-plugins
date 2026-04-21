#!/usr/bin/env bash
# Tests for init-profile.sh
# Covers: file creation, overwrite guard, --force, id validation, reserved-id
#         guard, --data-root, file mode (0600), profiles-dir mode (0700).
#
# Runtime dependencies:
#   - helpers.sh  (task 5.2) — provides with_sandbox, assert_*, yci_test_summary
#   - ${YCI_SCRIPTS_DIR}/init-profile.sh  (task 5.1)
#
# shellcheck disable=SC1091
# set -euo pipefail (removed: tests need explicit exit-code capture)
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# ---------------------------------------------------------------------------
# test_init_creates_from_template
#   init-profile.sh should create <data-root>/profiles/<id>.yaml and exit 0.
# ---------------------------------------------------------------------------
test_init_creates_from_template() {
    local sb="$1"
    "${YCI_SCRIPTS_DIR}/init-profile.sh" "$sb/real" acme-test
    rc=$?
    assert_exit 0 "$rc" "init: exit 0"
    assert_contains "$(ls "$sb/real/profiles/" 2>/dev/null || true)" \
        "acme-test.yaml" "init: file created"
    # file must be 0600
    local mode
    mode="$(stat -c %a "$sb/real/profiles/acme-test.yaml" 2>/dev/null \
        || stat -f %A "$sb/real/profiles/acme-test.yaml")"
    assert_eq "$mode" "600" "init: file mode 0600"
}

# ---------------------------------------------------------------------------
# test_init_refuses_overwrite
#   A second init without --force must exit 1 and mention "already exists".
# ---------------------------------------------------------------------------
test_init_refuses_overwrite() {
    local sb="$1"
    "${YCI_SCRIPTS_DIR}/init-profile.sh" "$sb/real" acme-test >/dev/null
    "${YCI_SCRIPTS_DIR}/init-profile.sh" "$sb/real" acme-test 2>"$sb/err"
    rc=$?
    assert_exit 1 "$rc" "init overwrite: exit 1"
    assert_contains "$(cat "$sb/err")" "already exists" "init overwrite: phrase"
}

# ---------------------------------------------------------------------------
# test_init_force_overwrites
#   --force should allow overwriting an existing profile (exit 0).
# ---------------------------------------------------------------------------
test_init_force_overwrites() {
    local sb="$1"
    "${YCI_SCRIPTS_DIR}/init-profile.sh" "$sb/real" acme-test >/dev/null
    "${YCI_SCRIPTS_DIR}/init-profile.sh" "$sb/real" acme-test --force
    rc=$?
    assert_exit 0 "$rc" "init --force: exit 0"
}

# ---------------------------------------------------------------------------
# test_init_rejects_uppercase
#   Uppercase IDs must be rejected with exit 1 and contain "invalid".
# ---------------------------------------------------------------------------
test_init_rejects_uppercase() {
    local sb="$1"
    "${YCI_SCRIPTS_DIR}/init-profile.sh" "$sb/real" ACME 2>"$sb/err"
    rc=$?
    assert_exit 1 "$rc" "init uppercase: exit 1"
    assert_contains "$(cat "$sb/err")" "invalid" "init uppercase: phrase"
}

# ---------------------------------------------------------------------------
# test_init_rejects_leading_hyphen
#   IDs beginning with '-' must be rejected with exit 1.
# ---------------------------------------------------------------------------
test_init_rejects_leading_hyphen() {
    local sb="$1"
    "${YCI_SCRIPTS_DIR}/init-profile.sh" "$sb/real" -acme 2>"$sb/err"
    rc=$?
    assert_exit 1 "$rc" "init leading-hyphen: exit 1"
    assert_contains "$(cat "$sb/err")" "invalid" "init leading-hyphen: phrase"
}

# ---------------------------------------------------------------------------
# test_init_rejects_reserved
#   IDs starting with '_' must be rejected unless --allow-reserved is passed.
# ---------------------------------------------------------------------------
test_init_rejects_reserved() {
    local sb="$1"
    "${YCI_SCRIPTS_DIR}/init-profile.sh" "$sb/real" _internal 2>"$sb/err"
    rc=$?
    assert_exit 1 "$rc" "init reserved: exit 1 without --allow-reserved"
    assert_contains "$(cat "$sb/err")" "reserved" "init reserved: phrase"
    # with --allow-reserved it should succeed
    "${YCI_SCRIPTS_DIR}/init-profile.sh" "$sb/real" _internal --allow-reserved
    rc=$?
    assert_exit 0 "$rc" "init reserved: exit 0 with --allow-reserved"
}

# ---------------------------------------------------------------------------
# test_init_respects_data_root_flag
#   Files should land under the provided data-root, not the default.
# ---------------------------------------------------------------------------
test_init_respects_data_root_flag() {
    local sb="$1"
    local alt="$sb/alternate-root"
    mkdir -p "$alt"
    "${YCI_SCRIPTS_DIR}/init-profile.sh" "$alt" flag-test
    rc=$?
    assert_exit 0 "$rc" "init alternate-root: exit 0"
    assert_file_exists "$alt/profiles/flag-test.yaml" "init alternate-root: file in alt root"
}

# ---------------------------------------------------------------------------
# test_init_profiles_dir_mode
#   The profiles/ directory must be created with mode 0700.
# ---------------------------------------------------------------------------
test_init_profiles_dir_mode() {
    local sb="$1"
    "${YCI_SCRIPTS_DIR}/init-profile.sh" "$sb/real" dirmode-test >/dev/null
    local mode
    mode="$(stat -c %a "$sb/real/profiles" 2>/dev/null \
        || stat -f %A "$sb/real/profiles")"
    assert_eq "$mode" "700" "init: profiles/ dir mode 0700"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
    with_sandbox test_init_creates_from_template
    with_sandbox test_init_refuses_overwrite
    with_sandbox test_init_force_overwrites
    with_sandbox test_init_rejects_uppercase
    with_sandbox test_init_rejects_leading_hyphen
    with_sandbox test_init_rejects_reserved
    with_sandbox test_init_respects_data_root_flag
    with_sandbox test_init_profiles_dir_mode
    yci_test_summary
}

main
