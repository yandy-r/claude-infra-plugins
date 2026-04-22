#!/usr/bin/env bash
# `-e` is omitted deliberately because this file captures and asserts on failing commands.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helpers.sh"

ROLLBACK="${PLUGIN_ROOT}/skills/_shared/scripts/derive-change-rollback.sh"
NORMALIZE="${SKILL_ROOT}/scripts/normalize-change.sh"
CHANGES_DIR="${FIXTURES_ROOT}/changes"

test_terraform_rollback() {
    local envelope out
    envelope="$(bash "$NORMALIZE" --input "${CHANGES_DIR}/terraform-plan.json")"
    out="$(printf '%s' "$envelope" | bash "$ROLLBACK")"
    assert_contains "Restore the pre-change state snapshot using your backend's versioning or recovery mechanism." "$out" "terraform rollback path"
    assert_contains "aws_security_group_rule.allow_https" "$out" "terraform resource address"
}

test_iosxe_rollback() {
    local envelope out stderr_file stderr_text
    envelope="$(bash "$NORMALIZE" --input "${CHANGES_DIR}/iosxe.cli")"
    stderr_file="$(mktemp)"
    out="$(printf '%s' "$envelope" | bash "$ROLLBACK" 2>"$stderr_file")"
    stderr_text="$(cat "$stderr_file")"
    rm -f "$stderr_file"
    assert_contains "MANUAL-ROLLBACK-REQUIRED" "$out" "iosxe manual rollback marker"
    assert_contains "restore the prior value for \`mtu 9000\`" "$out" "iosxe mtu requires manual restore"
    assert_contains "restore the prior value for \`description uplink-to-spine\`" "$out" "iosxe description requires manual restore"
    assert_contains "ncr-rollback-ambiguous" "$stderr_text" "iosxe emits low-confidence warning"
}

test_terraform_replace_rollback() {
    local envelope out
    envelope="$(python3 <<'PYEOF'
import json

plan = {
    "resource_changes": [
        {
            "address": "aws_instance.edge",
            "change": {
                "actions": ["delete", "create"],
                "before": {"id": "i-old"},
                "after": {"id": "i-new"},
            },
        }
    ]
}
doc = {"diff_kind": "terraform-plan", "raw": json.dumps(plan), "targets": [], "summary": "replace"}
print(json.dumps(doc))
PYEOF
)"
    out="$(printf '%s' "$envelope" | bash "$ROLLBACK")"
    assert_contains "\`aws_instance.edge\` (delete,create)" "$out" "terraform replace action label"
    assert_contains "Use the state snapshot rollback path above" "$out" "terraform replacement uses snapshot rollback"
}

test_panos_rollback() {
    local envelope out
    envelope="$(bash "$NORMALIZE" --input "${CHANGES_DIR}/panos.cli")"
    out="$(printf '%s' "$envelope" | bash "$ROLLBACK")"
    assert_contains "delete network interface ethernet ethernet1/1 layer3 mtu 9000" "$out" "panos inverse command"
}

test_invalid_json_envelope() {
    local stderr_file rc stderr_text
    stderr_file="$(mktemp)"
    set +e
    printf '%s' '{invalid json' | bash "$ROLLBACK" 2>"$stderr_file"
    rc=$?
    set -e
    stderr_text="$(cat "$stderr_file")"
    rm -f "$stderr_file"
    assert_exit_code 3 "$rc" "invalid json envelope exits 3"
    assert_contains "ncr-diff-unsupported-shape" "$stderr_text" "invalid json envelope emits marker"
}

test_terraform_rollback
test_iosxe_rollback
test_terraform_replace_rollback
test_panos_rollback
test_invalid_json_envelope
summary
