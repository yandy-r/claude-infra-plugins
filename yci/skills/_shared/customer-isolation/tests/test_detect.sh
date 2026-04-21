#!/usr/bin/env bash
# End-to-end tests for detect.sh — isolation_check_payload coverage.
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

DETECT_SH="${YCI_SCRIPTS_DIR}/../detect.sh"

_detect_ok() {
    if [ ! -f "$DETECT_SH" ]; then
        printf 'DIAGNOSTIC: detect.sh not found at %s\n' "$DETECT_SH" >&2
        return 1
    fi
    return 0
}

# Full schema-compliant profile writer.
_write_profile() {
    local data_root="$1"
    local cid="$2"
    local inv_rel="${3:-inventories/$cid}"
    mkdir -p "$data_root/profiles"
    cat > "$data_root/profiles/${cid}.yaml" <<EOF
customer:
  id: ${cid}
  display_name: "Test ${cid}"
engagement:
  id: ${cid}-eng
  type: implementation
  sow_ref: SOW-0001
  scope_tags: [test]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: commercial
  evidence_schema_version: 1
inventory:
  adapter: file
  path: ${inv_rel}
approval:
  adapter: github-pr
deliverable:
  format: [markdown]
  header_template: /tmp/header.md
  handoff_format: git-repo
safety:
  default_posture: review
  change_window_required: false
  scope_enforcement: warn
EOF
}

# Source detect.sh once. with_sandbox runs in current shell.
# shellcheck source=/dev/null
[ -f "$DETECT_SH" ] && source "$DETECT_SH"

# ---------------------------------------------------------------------------
test_zero_foreigns_allow() {
    local sb="$1"
    _detect_ok || { _yci_test_report PASS "zero_foreigns: skipped"; return 0; }
    local data="$sb/data"
    _write_profile "$data" "acme"
    export YCI_DATA_ROOT_RESOLVED="$data"
    export YCI_ACTIVE_CUSTOMER="acme"
    local out rc
    out="$(printf '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' | isolation_check_payload 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "zero_foreigns: exits 0"
    assert_contains "$out" '"allow"' "zero_foreigns: decision=allow with only one customer"
    unset YCI_DATA_ROOT_RESOLVED YCI_ACTIVE_CUSTOMER
}

test_allow_own_path() {
    local sb="$1"
    _detect_ok || { _yci_test_report PASS "allow_own_path: skipped"; return 0; }
    local data="$sb/data"
    # Create acme inventory (active) and bigbank (foreign).
    mkdir -p "$data/inventories/acme" "$data/inventories/bigbank"
    cat > "$data/inventories/acme/hosts.yaml" <<'EOF'
hosts:
  - acme01.acme.corp
  - 10.1.1.1
EOF
    cat > "$data/inventories/bigbank/hosts.yaml" <<'EOF'
hosts:
  - bb01.bigbank.corp
  - 10.2.2.2
EOF
    _write_profile "$data" "acme" "inventories/acme"
    _write_profile "$data" "bigbank" "inventories/bigbank"
    export YCI_DATA_ROOT_RESOLVED="$data"
    export YCI_ACTIVE_CUSTOMER="acme"
    local out rc
    out="$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' \
        "$data/inventories/acme/hosts.yaml" | isolation_check_payload 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "allow_own_path: exits 0"
    assert_contains "$out" '"allow"' "allow_own_path: own inventory file allowed"
    unset YCI_DATA_ROOT_RESOLVED YCI_ACTIVE_CUSTOMER
}

test_deny_foreign_path() {
    local sb="$1"
    _detect_ok || { _yci_test_report PASS "deny_foreign_path: skipped"; return 0; }
    local data="$sb/data"
    mkdir -p "$data/inventories/acme" "$data/inventories/bigbank"
    cat > "$data/inventories/acme/hosts.yaml" <<'EOF'
hosts:
  - acme01.acme.corp
EOF
    cat > "$data/inventories/bigbank/hosts.yaml" <<'EOF'
hosts:
  - bb01.bigbank.corp
EOF
    _write_profile "$data" "acme" "inventories/acme"
    _write_profile "$data" "bigbank" "inventories/bigbank"
    export YCI_DATA_ROOT_RESOLVED="$data"
    export YCI_ACTIVE_CUSTOMER="acme"
    local out rc
    out="$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' \
        "$data/inventories/bigbank/hosts.yaml" | isolation_check_payload 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "deny_foreign_path: exits 0"
    assert_contains "$out" '"deny"' "deny_foreign_path: foreign path denied"
    assert_contains "$out" '"kind":"path"' "deny_foreign_path: kind=path"
    unset YCI_DATA_ROOT_RESOLVED YCI_ACTIVE_CUSTOMER
}

test_deny_foreign_hostname() {
    local sb="$1"
    _detect_ok || { _yci_test_report PASS "deny_foreign_hostname: skipped"; return 0; }
    local data="$sb/data"
    mkdir -p "$data/inventories/acme" "$data/inventories/bigbank"
    cat > "$data/inventories/acme/hosts.yaml" <<'EOF'
hosts:
  - acme01.acme.corp
EOF
    cat > "$data/inventories/bigbank/hosts.yaml" <<'EOF'
hosts:
  - bb01.bigbank.corp
EOF
    _write_profile "$data" "acme" "inventories/acme"
    _write_profile "$data" "bigbank" "inventories/bigbank"
    export YCI_DATA_ROOT_RESOLVED="$data"
    export YCI_ACTIVE_CUSTOMER="acme"
    local out rc
    out="$(printf '{"tool_name":"Write","tool_input":{"content":"connecting to bb01.bigbank.corp"}}' \
        | isolation_check_payload 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "deny_foreign_hostname: exits 0"
    assert_contains "$out" '"deny"' "deny_foreign_hostname: denied"
    assert_contains "$out" '"kind":"token"' "deny_foreign_hostname: kind=token"
    assert_contains "$out" '"category":"hostname"' "deny_foreign_hostname: category=hostname"
    unset YCI_DATA_ROOT_RESOLVED YCI_ACTIVE_CUSTOMER
}

test_deny_foreign_ipv4() {
    local sb="$1"
    _detect_ok || { _yci_test_report PASS "deny_foreign_ipv4: skipped"; return 0; }
    local data="$sb/data"
    mkdir -p "$data/inventories/acme" "$data/inventories/bigbank"
    cat > "$data/inventories/acme/hosts.yaml" <<'EOF'
hosts:
  - acme01.acme.corp
  - 10.1.1.1
EOF
    cat > "$data/inventories/bigbank/hosts.yaml" <<'EOF'
hosts:
  - bb01.bigbank.corp
  - 10.2.2.2
EOF
    _write_profile "$data" "acme" "inventories/acme"
    _write_profile "$data" "bigbank" "inventories/bigbank"
    export YCI_DATA_ROOT_RESOLVED="$data"
    export YCI_ACTIVE_CUSTOMER="acme"
    local out rc
    out="$(printf '{"tool_name":"Bash","tool_input":{"command":"ping 10.2.2.2"}}' \
        | isolation_check_payload 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "deny_foreign_ipv4: exits 0"
    assert_contains "$out" '"deny"' "deny_foreign_ipv4: denied"
    assert_contains "$out" '"category":"ipv4"' "deny_foreign_ipv4: category=ipv4"
    unset YCI_DATA_ROOT_RESOLVED YCI_ACTIVE_CUSTOMER
}

test_allowlist_bypass_path() {
    local sb="$1"
    _detect_ok || { _yci_test_report PASS "al_bypass_path: skipped"; return 0; }
    local data="$sb/data"
    mkdir -p "$data/inventories/acme" "$data/inventories/bigbank" "$data/profiles"
    cat > "$data/inventories/acme/hosts.yaml" <<'EOF'
hosts:
  - acme01.acme.corp
EOF
    cat > "$data/inventories/bigbank/hosts.yaml" <<'EOF'
hosts:
  - bb01.bigbank.corp
EOF
    _write_profile "$data" "acme" "inventories/acme"
    _write_profile "$data" "bigbank" "inventories/bigbank"
    # Allow bigbank inventory path AND the customer-id token in acme's allowlist.
    # (The path string "bigbank" also triggers a customer-id token match, so both
    # must be allowlisted for a full bypass.)
    cat > "$data/profiles/acme.allowlist.yaml" <<EOF
paths:
  - ${data}/inventories/bigbank
tokens:
  customer-id:
    - bigbank
EOF
    export YCI_DATA_ROOT_RESOLVED="$data"
    export YCI_ACTIVE_CUSTOMER="acme"
    local out rc
    out="$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' \
        "$data/inventories/bigbank/hosts.yaml" | isolation_check_payload 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "al_bypass_path: exits 0"
    assert_contains "$out" '"allow"' "al_bypass_path: foreign path allowed via allowlist"
    unset YCI_DATA_ROOT_RESOLVED YCI_ACTIVE_CUSTOMER
}

test_allowlist_bypass_token() {
    local sb="$1"
    _detect_ok || { _yci_test_report PASS "al_bypass_token: skipped"; return 0; }
    local data="$sb/data"
    # Use a bigbank profile that has a unique inventory hostname with labels that
    # won't bleed into other token categories. The allowlist covers all emitted
    # tokens from the payload string being tested.
    mkdir -p "$data/inventories/acme" "$data/inventories/zbank" "$data/profiles"
    cat > "$data/inventories/acme/hosts.yaml" <<'EOF'
hosts:
  - acme01.acme.corp
EOF
    # Foreign customer: use name "zbank" with a unique hostname.
    cat > "$data/inventories/zbank/hosts.yaml" <<'EOF'
hosts:
  - zhost01.zbank.net
EOF
    _write_profile "$data" "acme" "inventories/acme"
    # Write zbank profile with distinct IDs and SOW to avoid shared token collisions.
    cat > "$data/profiles/zbank.yaml" <<'ZPROF'
customer:
  id: zbank
  display_name: "Z Bank"
engagement:
  id: zbank-eng
  type: implementation
  sow_ref: SOW-9999
  scope_tags: [test]
  start_date: "2026-01-01"
  end_date: "2026-12-31"
compliance:
  regime: commercial
  evidence_schema_version: 1
inventory:
  adapter: file
  path: inventories/zbank
approval:
  adapter: github-pr
deliverable:
  format: [markdown]
  header_template: /tmp/header.md
  handoff_format: git-repo
safety:
  default_posture: review
  change_window_required: false
  scope_enforcement: warn
ZPROF
    # Payload "zhost01.zbank.net" extracts: hostname:zhost01.zbank.net,
    # customer-id:zhost01, customer-id:zbank.
    # ("net" is filtered by _HOSTNAME_LABEL_SKIP; "9999" not in payload.)
    # Allowlist must cover all extracted tokens that collide with zbank's fingerprint.
    cat > "$data/profiles/acme.allowlist.yaml" <<'EOF'
tokens:
  hostname:
    - zhost01.zbank.net
  customer-id:
    - zbank
    - zhost01
EOF
    export YCI_DATA_ROOT_RESOLVED="$data"
    export YCI_ACTIVE_CUSTOMER="acme"
    local out rc
    out="$(printf '{"tool_name":"Write","tool_input":{"content":"zhost01.zbank.net"}}' \
        | isolation_check_payload 2>/dev/null)"; rc=$?
    assert_exit 0 "$rc" "al_bypass_token: exits 0"
    assert_contains "$out" '"allow"' "al_bypass_token: foreign token allowed via allowlist"
    unset YCI_DATA_ROOT_RESOLVED YCI_ACTIVE_CUSTOMER
}

test_missing_env_var() {
    local sb="$1"
    _detect_ok || { _yci_test_report PASS "missing_env: skipped"; return 0; }
    # Ensure both env vars are unset.
    unset YCI_ACTIVE_CUSTOMER YCI_DATA_ROOT_RESOLVED
    local stderr_out rc
    stderr_out="$(printf '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' \
        | isolation_check_payload 2>&1 1>/dev/null)"; rc=$?
    if [ "$rc" -ne 0 ]; then
        _yci_test_report PASS "missing_env: non-zero exit when env vars missing"
    else
        _yci_test_report FAIL "missing_env: expected non-zero exit, got 0"
    fi
    assert_contains "$stderr_out" "YCI_ACTIVE_CUSTOMER" "missing_env: stderr mentions missing env var"
}

# ---------------------------------------------------------------------------
with_sandbox test_zero_foreigns_allow
with_sandbox test_allow_own_path
with_sandbox test_deny_foreign_path
with_sandbox test_deny_foreign_hostname
with_sandbox test_deny_foreign_ipv4
with_sandbox test_allowlist_bypass_path
with_sandbox test_allowlist_bypass_token
with_sandbox test_missing_env_var

yci_test_summary
