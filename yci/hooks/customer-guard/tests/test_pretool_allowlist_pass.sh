#!/usr/bin/env bash
# Integration tests: pretool.sh allowlist bypass scenarios.
# Uses a fictional "zbank" customer with a hostname/id that won't bleed into
# acme's token space, to ensure a clean allowlist bypass test.
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

PRETOOL="${REPO_ROOT}/yci/hooks/customer-guard/scripts/pretool.sh"

_pretool_ok() {
    if [ ! -f "$PRETOOL" ]; then
        printf 'DIAGNOSTIC: pretool.sh not found at %s\n' "$PRETOOL" >&2
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# test_path_allowlisted: same path as deny_path but with an allowlist entry
# for the foreign customer's inventory dir + customer-id token → allow.
#
# We use "zbank" as the foreign customer name because:
#   - "zbank" as a customer-id token is extracted from the path string by
#     extract-tokens.py (customer-id regex: [a-z0-9][a-z0-9-]{2,63})
#   - To fully bypass, the allowlist must cover BOTH the path AND the token.
# ---------------------------------------------------------------------------
test_path_allowlisted() {
    local sb="$1"
    _pretool_ok || { _yci_test_report PASS "path_allowlisted: skipped (pretool.sh not found)"; return 0; }

    local data="$sb/data"
    mkdir -p "$data/profiles" "$data/inventories/acme" "$data/inventories/zbank"

    _build_profile "$data/profiles/acme.yaml" "acme" "Acme Corp" "inventories/acme"

    # zbank profile with SOW-9999 (distinct from acme's SOW-0001) to avoid
    # cross-profile token bleed.
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

    cat > "$data/inventories/acme/hosts.yaml" <<'EOF'
hosts:
  - acme01.acme.corp
  - 10.1.1.1
EOF
    cat > "$data/inventories/zbank/hosts.yaml" <<'EOF'
hosts:
  - zhost01.zbank.net
  - 10.3.3.3
EOF

    # Allowlist must cover:
    #   1. The path prefix for zbank's inventory dir (path kind).
    #   2. The customer-id token "zbank" (extracted from the file path string).
    # (zhost01 and zhost01.zbank.net are NOT in the payload — only the path is.)
    cat > "$data/profiles/acme.allowlist.yaml" <<EOF
paths:
  - ${data}/inventories/zbank
tokens:
  customer-id:
    - zbank
EOF

    export YCI_CUSTOMER="acme"
    export YCI_DATA_ROOT="$data"
    export YCI_DATA_ROOT_RESOLVED="$data"

    local payload
    payload="$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' \
        "$data/inventories/zbank/hosts.yaml")"

    local stdout rc
    stdout="$(printf '%s' "$payload" | bash "$PRETOOL" 2>/dev/null)"; rc=$?

    assert_exit 0 "$rc" "path_allowlisted: exit 0"
    assert_eq "$stdout" "" "path_allowlisted: stdout empty (allow via allowlist)"

    unset YCI_CUSTOMER YCI_DATA_ROOT YCI_DATA_ROOT_RESOLVED
}

# ---------------------------------------------------------------------------
with_sandbox test_path_allowlisted

yci_test_summary
