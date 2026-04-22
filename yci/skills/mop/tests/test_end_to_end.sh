#!/usr/bin/env bash
# Exit on error so setup and generated-artifact failures stop the test immediately.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helpers.sh"

GENERATE="${SKILL_ROOT}/scripts/generate-mop.sh"
CHANGES_DIR="${FIXTURES_ROOT}/changes"
PROFILES_DIR="${FIXTURES_ROOT}/profiles"
INVENTORY_ROOT="${PLUGIN_ROOT}/skills/blast-radius/tests/fixtures/inventory-widgetcorp"
TMP_ROOT="$(mktemp -d -t yci-mop-e2e-XXXX)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

mkdir -p "${TMP_ROOT}/profiles"
cp "${PROFILES_DIR}/widget-corp-header.md" "${TMP_ROOT}/profiles/widget-corp-header.md"
python3 - "${PROFILES_DIR}/widget-corp.yaml" "${TMP_ROOT}/profiles/widget-corp.yaml" "$INVENTORY_ROOT" <<'PYEOF'
from pathlib import Path
import sys

src = Path(sys.argv[1]).read_text()
inventory_root = Path(sys.argv[3]).resolve()
src = src.replace("../../../../blast-radius/tests/fixtures/inventory-widgetcorp", str(inventory_root))
Path(sys.argv[2]).write_text(src)
PYEOF

artifact_path="$(bash "$GENERATE" --data-root "$TMP_ROOT" --customer widget-corp "${CHANGES_DIR}/iosxe.cli")"
assert_file_exists "$artifact_path" "end-to-end artifact exists"
rendered="$(cat "$artifact_path")"
assert_contains "## Method of Procedure" "$rendered" "end-to-end heading"
assert_contains "Raise MTU on dc1-edge-01 uplink" "$rendered" "end-to-end summary"
assert_contains "MANUAL-ROLLBACK-REQUIRED" "$rendered" "end-to-end rollback markers"
assert_contains "Rollback confidence" "$rendered" "end-to-end low-confidence callout"

terraform_artifact="$(bash "$GENERATE" --data-root "$TMP_ROOT" --customer widget-corp "${CHANGES_DIR}/terraform-plan.json")"
assert_file_exists "$terraform_artifact" "terraform artifact exists"
terraform_rendered="$(cat "$terraform_artifact")"
terraform_dir="$(dirname "$terraform_artifact")"
assert_contains "reviewed-input-plan-json" "$terraform_rendered" "terraform packaged input reference"
assert_contains "pre-change-tfstate" "$terraform_rendered" "terraform safe pre-state filename"
assert_contains "regenerated-plan-json" "$terraform_rendered" "terraform regenerated filename"
assert_file_exists "${terraform_dir}/reviewed-input-plan-json" "terraform packaged input exists"

python3 - "${TMP_ROOT}/profiles/widget-corp.yaml" <<'PYEOF'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("header_template: widget-corp-header.md", "header_template: ../outside.md")
path.write_text(text)
PYEOF
printf 'outside\n' > "${TMP_ROOT}/outside.md"

set +e
invalid_output="$(bash "$GENERATE" --data-root "$TMP_ROOT" --customer widget-corp "${CHANGES_DIR}/iosxe.cli" 2>&1)"
invalid_rc=$?
set -e
assert_exit_code 2 "$invalid_rc" "generate-mop rejects header template traversal"
assert_contains "deliverable.header_template must be a simple filename under profiles/" "$invalid_output" "generate-mop emits traversal error"
summary
