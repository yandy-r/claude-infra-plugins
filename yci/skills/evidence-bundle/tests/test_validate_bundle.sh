#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

VALIDATOR="${SCRIPTS_DIR}/validate-bundle.py"

test_valid_bundle() {
    local sb rc
    sb="$(mktemp -d)"
    trap 'rm -rf "${sb}"' RETURN

    cat > "${sb}/bundle.json" <<'EOF'
{
  "change_id": "chg-1",
  "change_summary": "Rotate ACL",
  "rollback_plan": "undo change",
  "approver": "ops@example.com",
  "operator_identity": "ops@example.com",
  "git_commit_range": "abc..def",
  "generated_at": "2026-04-21T15:00:00Z",
  "executed_at": "2026-04-21T14:45:00Z",
  "timestamp_utc": "2026-04-21T14:45:00Z",
  "profile_commit": "abc123",
  "approvals": ["CAB approved"],
  "pre_check_artifacts": ["pre.txt"],
  "post_check_artifacts": ["post.txt"],
  "tenant_scope": ["tenant-a"]
}
EOF

    set +e
    python3 "${VALIDATOR}" --bundle-json "${sb}/bundle.json"
    rc=$?
    set -e
    assert_exit 0 "$rc" "validate_bundle: valid bundle exits 0"
}

test_invalid_bundle() {
    local sb rc
    sb="$(mktemp -d)"
    trap 'rm -rf "${sb}"' RETURN

    cat > "${sb}/bundle.json" <<'EOF'
{"change_id":"chg-1"}
EOF

    set +e
    python3 "${VALIDATOR}" --bundle-json "${sb}/bundle.json" >"${sb}/out" 2>"${sb}/err"
    rc=$?
    set -e
    assert_exit 1 "${rc}" "validate_bundle: invalid bundle exits 1"
}

test_valid_bundle
test_invalid_bundle
yci_test_summary
