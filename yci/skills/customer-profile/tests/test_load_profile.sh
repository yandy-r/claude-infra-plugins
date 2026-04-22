#!/usr/bin/env bash
# Tests for load-profile.sh.
# Covers: happy path, missing file, malformed YAML, missing required keys,
# invalid enum values, unknown key warning, pyyaml-missing guard.
#
# load-profile.sh lives in the B5.1 worktree; tests reference it by path via
# SCRIPTS_DIR and tolerate its absence with a diagnostic.
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

LOADER="${YCI_SCRIPTS_DIR}/load-profile.sh"

_loader_missing_diagnostic() {
    if [ ! -f "$LOADER" ]; then
        printf 'DIAGNOSTIC: load-profile.sh not found at %s\n' "$LOADER" >&2
        printf '  (expected after B5.1 merges)\n' >&2
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Happy path — well-formed full profile, all required fields present
# ---------------------------------------------------------------------------
test_load_happy_path() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "load_happy: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/acme.yaml" <<'EOF'
customer:
  id: acme
  display_name: "ACME Co"
engagement:
  id: eng-001
  type: implementation
  sow_ref: SOW-1
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: hipaa
  evidence_schema_version: 1
inventory:
  adapter: manual
approval:
  adapter: manual
deliverable:
  format: [markdown]
  header_template: "Deliv {c}"
  handoff_format: git-repo
safety:
  default_posture: review
  change_window_required: false
  scope_enforcement: warn
EOF
    local out rc
    out="$("$LOADER" "$sb/real" acme 2>"$sb/err")"; rc=$?
    assert_exit 0 "$rc" "load_happy: exit 0"
    assert_contains "$out" "\"customer\"" "load_happy: JSON has customer key"
    assert_contains "$out" "\"acme\"" "load_happy: JSON has id value"
    assert_contains "$out" "\"engagement\"" "load_happy: JSON has engagement"
}

# ---------------------------------------------------------------------------
# Happy path with change_window (change_window_required: true)
# ---------------------------------------------------------------------------
test_load_happy_with_change_window() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "load_cw: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/bigbank.yaml" <<'EOF'
customer:
  id: bigbank
  display_name: "Big Bank"
engagement:
  id: eng-002
  type: ongoing
  sow_ref: SOW-2
  scope_tags: [core, net]
  start_date: "2026-02-01"
  end_date: "2027-01-31"
compliance:
  regime: sox
  evidence_schema_version: 1
inventory:
  adapter: netbox
  endpoint: https://netbox.bigbank.internal
approval:
  adapter: github-pr
deliverable:
  format: [markdown, pdf]
  header_template: "Report {c}"
  handoff_format: zip
safety:
  default_posture: dry-run
  change_window_required: true
  scope_enforcement: block
change_window:
  adapter: ical
  source: https://calendar.bigbank.internal/change-windows.ics
  timezone: America/Chicago
EOF
    local out rc
    out="$("$LOADER" "$sb/real" bigbank 2>"$sb/err")"; rc=$?
    assert_exit 0 "$rc" "load_cw: exit 0"
    assert_contains "$out" "change_window" "load_cw: JSON has change_window"
}

# ---------------------------------------------------------------------------
# Missing file → exit 1 with loader-missing-file error
# ---------------------------------------------------------------------------
test_missing_file() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "missing_file: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    local rc
    "$LOADER" "$sb/real" nonexistent >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 1 "$rc" "missing_file: exit 1"
    assert_contains "$(cat "$sb/err")" "profile not found" "missing_file: error phrase"
}

# ---------------------------------------------------------------------------
# Malformed YAML → exit 2 with loader-malformed-yaml error
# ---------------------------------------------------------------------------
test_malformed_yaml() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "malformed_yaml: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    printf 'customer:\n  id: broken\n  bad: [unclosed\n' > "$sb/real/profiles/broken.yaml"
    local rc
    "$LOADER" "$sb/real" broken >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 2 "$rc" "malformed_yaml: exit 2"
    assert_contains "$(cat "$sb/err")" "malformed YAML" "malformed_yaml: error phrase"
}

# ---------------------------------------------------------------------------
# Missing required top-level key (customer section absent) → exit 2
# ---------------------------------------------------------------------------
test_missing_required_key_customer() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "missing_customer: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/no-customer.yaml" <<'EOF'
engagement:
  id: eng-001
  type: discovery
  sow_ref: SOW-0
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: commercial
  evidence_schema_version: 1
inventory:
  adapter: manual
approval:
  adapter: manual
deliverable:
  format: [markdown]
  header_template: "Deliv"
  handoff_format: zip
safety:
  default_posture: dry-run
  change_window_required: false
  scope_enforcement: off
EOF
    local rc
    "$LOADER" "$sb/real" no-customer >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 2 "$rc" "missing_customer: exit 2"
    assert_contains "$(cat "$sb/err")" "missing required field" "missing_customer: error phrase"
}

# ---------------------------------------------------------------------------
# Missing nested required key (engagement.sow_ref absent) → exit 2
# ---------------------------------------------------------------------------
test_missing_required_key_engagement() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "missing_sow: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/no-sow.yaml" <<'EOF'
customer:
  id: no-sow
  display_name: "No SOW Co"
engagement:
  id: eng-001
  type: design
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: none
  evidence_schema_version: 1
inventory:
  adapter: manual
approval:
  adapter: none
deliverable:
  format: [markdown]
  header_template: "Deliv"
  handoff_format: zip
safety:
  default_posture: dry-run
  change_window_required: false
  scope_enforcement: warn
EOF
    local rc
    "$LOADER" "$sb/real" no-sow >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 2 "$rc" "missing_sow: exit 2"
    assert_contains "$(cat "$sb/err")" "missing required field" "missing_sow: error phrase"
    assert_contains "$(cat "$sb/err")" "sow_ref" "missing_sow: field name in error"
}

# ---------------------------------------------------------------------------
# Missing nested required key (safety.scope_enforcement absent) → exit 2
# ---------------------------------------------------------------------------
test_missing_required_key_safety() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "missing_scope_enforcement: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/no-scope.yaml" <<'EOF'
customer:
  id: no-scope
  display_name: "No Scope Co"
engagement:
  id: eng-001
  type: design
  sow_ref: SOW-X
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: none
  evidence_schema_version: 1
inventory:
  adapter: manual
approval:
  adapter: none
deliverable:
  format: [markdown]
  header_template: "Deliv"
  handoff_format: zip
safety:
  default_posture: dry-run
  change_window_required: false
EOF
    local rc
    "$LOADER" "$sb/real" no-scope >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 2 "$rc" "missing_scope_enforcement: exit 2"
    assert_contains "$(cat "$sb/err")" "missing required field" "missing_scope_enforcement: error phrase"
}

# ---------------------------------------------------------------------------
# Invalid enum: compliance.regime → exit 2
# ---------------------------------------------------------------------------
test_invalid_enum_regime() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "invalid_regime: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/bad-regime.yaml" <<'EOF'
customer:
  id: bad-regime
  display_name: "Bad Regime Co"
engagement:
  id: eng-001
  type: implementation
  sow_ref: SOW-1
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: fips-140
  evidence_schema_version: 1
inventory:
  adapter: manual
approval:
  adapter: manual
deliverable:
  format: [markdown]
  header_template: "Deliv"
  handoff_format: zip
safety:
  default_posture: dry-run
  change_window_required: false
  scope_enforcement: warn
EOF
    local rc
    "$LOADER" "$sb/real" bad-regime >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 2 "$rc" "invalid_regime: exit 2"
    assert_contains "$(cat "$sb/err")" "invalid value" "invalid_regime: error phrase"
}

# ---------------------------------------------------------------------------
# Invalid enum: engagement.type → exit 2
# ---------------------------------------------------------------------------
test_invalid_enum_engagement_type() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "invalid_eng_type: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/bad-type.yaml" <<'EOF'
customer:
  id: bad-type
  display_name: "Bad Type Co"
engagement:
  id: eng-001
  type: consulting
  sow_ref: SOW-1
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: commercial
  evidence_schema_version: 1
inventory:
  adapter: manual
approval:
  adapter: manual
deliverable:
  format: [markdown]
  header_template: "Deliv"
  handoff_format: zip
safety:
  default_posture: dry-run
  change_window_required: false
  scope_enforcement: warn
EOF
    local rc
    "$LOADER" "$sb/real" bad-type >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 2 "$rc" "invalid_eng_type: exit 2"
    assert_contains "$(cat "$sb/err")" "invalid value" "invalid_eng_type: error phrase"
}

# ---------------------------------------------------------------------------
# Invalid enum: safety.default_posture → exit 2
# ---------------------------------------------------------------------------
test_invalid_enum_posture() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "invalid_posture: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/bad-posture.yaml" <<'EOF'
customer:
  id: bad-posture
  display_name: "Bad Posture Co"
engagement:
  id: eng-001
  type: implementation
  sow_ref: SOW-1
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: commercial
  evidence_schema_version: 1
inventory:
  adapter: manual
approval:
  adapter: manual
deliverable:
  format: [markdown]
  header_template: "Deliv"
  handoff_format: zip
safety:
  default_posture: yolo
  change_window_required: false
  scope_enforcement: warn
EOF
    local rc
    "$LOADER" "$sb/real" bad-posture >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 2 "$rc" "invalid_posture: exit 2"
    assert_contains "$(cat "$sb/err")" "invalid value" "invalid_posture: error phrase"
}

# ---------------------------------------------------------------------------
# Invalid enum: safety.scope_enforcement → exit 2
# ---------------------------------------------------------------------------
test_invalid_enum_scope_enforcement() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "invalid_enforcement: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/bad-enforcement.yaml" <<'EOF'
customer:
  id: bad-enforcement
  display_name: "Bad Enforcement Co"
engagement:
  id: eng-001
  type: implementation
  sow_ref: SOW-1
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: commercial
  evidence_schema_version: 1
inventory:
  adapter: manual
approval:
  adapter: manual
deliverable:
  format: [markdown]
  header_template: "Deliv"
  handoff_format: zip
safety:
  default_posture: dry-run
  change_window_required: false
  scope_enforcement: maybe
EOF
    local rc
    "$LOADER" "$sb/real" bad-enforcement >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 2 "$rc" "invalid_enforcement: exit 2"
    assert_contains "$(cat "$sb/err")" "invalid value" "invalid_enforcement: error phrase"
}

# ---------------------------------------------------------------------------
# Invalid enum: deliverable.handoff_format → exit 2
# ---------------------------------------------------------------------------
test_invalid_enum_handoff_format() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "invalid_handoff: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/bad-handoff.yaml" <<'EOF'
customer:
  id: bad-handoff
  display_name: "Bad Handoff Co"
engagement:
  id: eng-001
  type: implementation
  sow_ref: SOW-1
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: commercial
  evidence_schema_version: 1
inventory:
  adapter: manual
approval:
  adapter: manual
deliverable:
  format: [markdown]
  header_template: "Deliv"
  handoff_format: usb-drive
safety:
  default_posture: dry-run
  change_window_required: false
  scope_enforcement: warn
EOF
    local rc
    "$LOADER" "$sb/real" bad-handoff >"$sb/out" 2>"$sb/err"
    rc=$?
    assert_exit 2 "$rc" "invalid_handoff: exit 2"
    assert_contains "$(cat "$sb/err")" "invalid value" "invalid_handoff: error phrase"
}

# ---------------------------------------------------------------------------
# Unknown top-level key → exit 0 but warning on stderr
# ---------------------------------------------------------------------------
test_unknown_key_warning() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "unknown_key: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/extra-key.yaml" <<'EOF'
customer:
  id: extra-key
  display_name: "Extra Key Co"
engagement:
  id: eng-001
  type: implementation
  sow_ref: SOW-1
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: soc2
  evidence_schema_version: 1
inventory:
  adapter: manual
approval:
  adapter: manual
deliverable:
  format: [markdown]
  header_template: "Deliv"
  handoff_format: git-repo
safety:
  default_posture: review
  change_window_required: false
  scope_enforcement: warn
future_field_unknown: some_value
EOF
    local out rc
    out="$("$LOADER" "$sb/real" extra-key 2>"$sb/err")"; rc=$?
    assert_exit 0 "$rc" "unknown_key: exit 0 (loaded successfully)"
    assert_contains "$out" "extra-key" "unknown_key: profile loaded"
    assert_contains "$(cat "$sb/err")" "unknown" "unknown_key: warning on stderr"
}

# ---------------------------------------------------------------------------
# Optional compliance.signing subtree validation
# ---------------------------------------------------------------------------
test_signing_subtree_minisign() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "signing_minisign: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/signing-minisign.yaml" <<'EOF'
customer:
  id: signing-minisign
  display_name: "Signing Minisign"
engagement:
  id: eng-001
  type: implementation
  sow_ref: SOW-1
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: hipaa
  evidence_schema_version: 1
  baa_reference: BAA-1
  signing:
    method: minisign
    key_ref: vault://ops/acme/minisign
    pubkey: RWQeXAMPLEPUBKEY
inventory:
  adapter: manual
approval:
  adapter: manual
deliverable:
  format: [markdown]
  header_template: "Deliv"
  handoff_format: git-repo
safety:
  default_posture: review
  change_window_required: false
  scope_enforcement: warn
EOF
    local out rc
    out="$("$LOADER" "$sb/real" signing-minisign 2>"$sb/err")"; rc=$?
    assert_exit 0 "$rc" "signing_minisign: exit 0"
    assert_contains "$out" "\"signing\"" "signing_minisign: JSON has signing subtree"
    assert_contains "$out" "\"method\": \"minisign\"" "signing_minisign: method retained"
}

test_signing_subtree_ssh_requires_identity() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "signing_ssh_missing_identity: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/signing-ssh.yaml" <<'EOF'
customer:
  id: signing-ssh
  display_name: "Signing SSH"
engagement:
  id: eng-001
  type: implementation
  sow_ref: SOW-1
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: soc2
  evidence_schema_version: 1
  signing:
    method: ssh-keygen-y-sign
    key_ref: vault://ops/acme/ssh-signing
inventory:
  adapter: manual
approval:
  adapter: manual
deliverable:
  format: [markdown]
  header_template: "Deliv"
  handoff_format: git-repo
safety:
  default_posture: review
  change_window_required: false
  scope_enforcement: warn
EOF
    local rc
    "$LOADER" "$sb/real" signing-ssh >"$sb/out" 2>"$sb/err"; rc=$?
    assert_exit 2 "$rc" "signing_ssh_missing_identity: exit 2"
    assert_contains "$(cat "$sb/err")" "compliance.signing.identity" "signing_ssh_missing_identity: identity required"
}

test_signing_subtree_invalid_method() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "signing_invalid_method: skipped (loader absent)"; return 0; }
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/signing-invalid.yaml" <<'EOF'
customer:
  id: signing-invalid
  display_name: "Signing Invalid"
engagement:
  id: eng-001
  type: implementation
  sow_ref: SOW-1
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: commercial
  evidence_schema_version: 1
  signing:
    method: sigstore
    key_ref: vault://ops/acme/sigstore
inventory:
  adapter: manual
approval:
  adapter: manual
deliverable:
  format: [markdown]
  header_template: "Deliv"
  handoff_format: git-repo
safety:
  default_posture: review
  change_window_required: false
  scope_enforcement: warn
EOF
    local rc
    "$LOADER" "$sb/real" signing-invalid >"$sb/out" 2>"$sb/err"; rc=$?
    assert_exit 2 "$rc" "signing_invalid_method: exit 2"
    assert_contains "$(cat "$sb/err")" "compliance.signing.method" "signing_invalid_method: method validation"
}

# ---------------------------------------------------------------------------
# All valid enum round-trips: compliance.regime values
# ---------------------------------------------------------------------------
_mk_profile() {
    local sb="$1" id="$2" regime="$3" posture="$4" eng_type="$5" handoff="$6" enforcement="$7"
    mkdir -p "$sb/real/profiles"
    cat > "$sb/real/profiles/${id}.yaml" <<EOF
customer:
  id: ${id}
  display_name: "${id} Co"
engagement:
  id: eng-001
  type: ${eng_type}
  sow_ref: SOW-1
  scope_tags: [net]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: ${regime}
  evidence_schema_version: 1
inventory:
  adapter: manual
approval:
  adapter: manual
deliverable:
  format: [markdown]
  header_template: "Deliv"
  handoff_format: "${handoff}"
safety:
  default_posture: "${posture}"
  change_window_required: false
  scope_enforcement: "${enforcement}"
EOF
}

test_enum_roundtrip_hipaa() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "enum_hipaa: skipped (loader absent)"; return 0; }
    _mk_profile "$sb" hipaa-co hipaa review implementation git-repo warn
    local rc
    "$LOADER" "$sb/real" hipaa-co >"$sb/out" 2>"$sb/err"; rc=$?
    assert_exit 0 "$rc" "enum_hipaa: exit 0"
}

test_enum_roundtrip_pci() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "enum_pci: skipped (loader absent)"; return 0; }
    _mk_profile "$sb" pci-co pci dry-run discovery zip block
    local rc
    "$LOADER" "$sb/real" pci-co >"$sb/out" 2>"$sb/err"; rc=$?
    assert_exit 0 "$rc" "enum_pci: exit 0"
}

test_enum_roundtrip_iso27001() {
    local sb="$1"
    _loader_missing_diagnostic || { _yci_test_report PASS "enum_iso: skipped (loader absent)"; return 0; }
    _mk_profile "$sb" iso-co iso27001 apply ongoing confluence off
    local rc
    "$LOADER" "$sb/real" iso-co >"$sb/out" 2>"$sb/err"; rc=$?
    assert_exit 0 "$rc" "enum_iso: exit 0"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    if [ ! -f "$LOADER" ]; then
        printf 'DIAGNOSTIC: load-profile.sh not found at %s\n' "$LOADER" >&2
        printf '  (expected after B5.1 merges)\n' >&2
    fi

    with_sandbox test_load_happy_path
    with_sandbox test_load_happy_with_change_window
    with_sandbox test_missing_file
    with_sandbox test_malformed_yaml
    with_sandbox test_missing_required_key_customer
    with_sandbox test_missing_required_key_engagement
    with_sandbox test_missing_required_key_safety
    with_sandbox test_invalid_enum_regime
    with_sandbox test_invalid_enum_engagement_type
    with_sandbox test_invalid_enum_posture
    with_sandbox test_invalid_enum_scope_enforcement
    with_sandbox test_invalid_enum_handoff_format
    with_sandbox test_unknown_key_warning
    with_sandbox test_signing_subtree_minisign
    with_sandbox test_signing_subtree_ssh_requires_identity
    with_sandbox test_signing_subtree_invalid_method
    with_sandbox test_enum_roundtrip_hipaa
    with_sandbox test_enum_roundtrip_pci
    with_sandbox test_enum_roundtrip_iso27001
    yci_test_summary
}

main
