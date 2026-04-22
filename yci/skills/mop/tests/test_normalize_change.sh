#!/usr/bin/env bash
# Exit on error so normalization failures stop the test deterministically.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helpers.sh"

NORMALIZE="${SKILL_ROOT}/scripts/normalize-change.sh"
CHANGES_DIR="${FIXTURES_ROOT}/changes"

test_unified_diff() {
    local out
    out="$(bash "$NORMALIZE" --input "${CHANGES_DIR}/unified-diff.patch")"
    assert_json_field "$out" "diff_kind" "unified-diff" "unified diff kind"
    assert_contains "git apply --check" "$out" "unified diff apply block"
}

test_terraform_plan() {
    local out
    out="$(bash "$NORMALIZE" --input "${CHANGES_DIR}/terraform-plan.json")"
    assert_json_field "$out" "diff_kind" "terraform-plan" "terraform kind"
    assert_contains "terraform apply tfplan" "$out" "terraform apply block"
    assert_contains "terraform state pull > pre-change-tfstate" "$out" "terraform pre-state block"
}

test_iosxe_cli() {
    local out
    out="$(bash "$NORMALIZE" --input "${CHANGES_DIR}/iosxe.cli")"
    assert_json_field "$out" "diff_kind" "vendor-cli" "iosxe kind"
    assert_contains '"vendor": "iosxe"' "$out" "iosxe metadata"
    assert_contains "interface GigabitEthernet0/0" "$out" "iosxe body preserved"
}

test_panos_cli() {
    local out
    out="$(bash "$NORMALIZE" --input "${CHANGES_DIR}/panos.cli")"
    assert_json_field "$out" "diff_kind" "vendor-cli" "panos kind"
    assert_contains '"vendor": "panos"' "$out" "panos metadata"
    assert_contains "set network interface ethernet" "$out" "panos body preserved"
}

test_structured_yaml() {
    local out
    out="$(bash "$NORMALIZE" --input "${CHANGES_DIR}/structured-with-reverse.yaml")"
    assert_json_field "$out" "diff_kind" "structured-yaml" "structured yaml kind"
    assert_contains "network 10.100.1.0" "$out" "structured yaml forward block"
}

test_unified_diff
test_terraform_plan
test_iosxe_cli
test_panos_cli
test_structured_yaml
summary
