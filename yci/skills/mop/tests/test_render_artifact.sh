#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helpers.sh"

RENDER="${SKILL_ROOT}/scripts/render-artifact.sh"
TMP_BASE="$(mktemp -d -t yci-mop-render-XXXX)"
trap 'rm -rf "${TMP_BASE}"' EXIT

cat > "${TMP_BASE}/profile.json" <<'EOF'
{
  "customer": {"id": "widget-corp"},
  "compliance": {"regime": "commercial"},
  "deliverable": {"header_template": "header.md"},
  "safety": {
    "default_posture": "review",
    "change_window_required": true,
    "scope_enforcement": "block"
  }
}
EOF

cat > "${TMP_BASE}/header.md" <<'EOF'
## Widget Corp
EOF

cat > "${TMP_BASE}/change.json" <<'EOF'
{
  "change_id": "mop-test-001",
  "summary": "Raise MTU on dc1-edge-01.",
  "pre_change_markdown": "```sh\nshow running-config\n```",
  "apply_markdown": "```text\ninterface Gi0/0\n mtu 9000\n```",
  "post_change_markdown": "```sh\nshow interface status\n```"
}
EOF

cat > "${TMP_BASE}/blast-radius.md" <<'EOF'
**Impact level:** medium
EOF

cat > "${TMP_BASE}/rollback.txt" <<'EOF'
no mtu 9000
EOF

cat > "${TMP_BASE}/catalog.json" <<'EOF'
{
  "pre_check": [{"id": "pre-1", "source": "adapter", "category": "adapter", "description": "Confirm maintenance window is open."}],
  "post_check": [{"id": "post-1", "source": "adapter", "category": "adapter", "description": "Confirm service health is normal."}]
}
EOF

output_path="${TMP_BASE}/mop.md"
(
  cd "$TMP_BASE" || exit
  bash "$RENDER" \
    --profile "${TMP_BASE}/profile.json" \
    --change-json "${TMP_BASE}/change.json" \
    --compliance-regime commercial \
    --blast-radius-markdown "${TMP_BASE}/blast-radius.md" \
    --rollback "${TMP_BASE}/rollback.txt" \
    --rollback-confidence low \
    --catalog "${TMP_BASE}/catalog.json" \
    --output "$output_path"
)

rendered="$(cat "$output_path")"
assert_file_exists "$output_path" "rendered file exists"
assert_contains "## Method of Procedure" "$rendered" "template heading"
assert_contains "Abort unless a human operator explicitly promotes the posture" "$rendered" "abort criteria derived"
assert_contains "Rollback confidence" "$rendered" "rollback callout rendered"
assert_contains "low-confidence rollback path" "$rendered" "low-confidence abort text rendered"

medium_output_path="${TMP_BASE}/mop-medium.md"
(
  cd "$TMP_BASE" || exit
  bash "$RENDER" \
    --profile "${TMP_BASE}/profile.json" \
    --change-json "${TMP_BASE}/change.json" \
    --compliance-regime commercial \
    --blast-radius-markdown "${TMP_BASE}/blast-radius.md" \
    --rollback "${TMP_BASE}/rollback.txt" \
    --rollback-confidence medium \
    --catalog "${TMP_BASE}/catalog.json" \
    --output "$medium_output_path"
)
medium_rendered="$(cat "$medium_output_path")"
assert_contains "Rollback confidence:** medium" "$medium_rendered" "medium rollback callout rendered"
assert_contains "medium-confidence rollback path" "$medium_rendered" "medium-confidence abort text rendered"

python3 - "${TMP_BASE}/profile.json" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
data["deliverable"]["header_template"] = "../outside.md"
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh)
PYEOF
printf 'outside\n' > "${TMP_BASE}/outside.md"

set +e
invalid_output="$(
  bash "$RENDER" \
    --profile "${TMP_BASE}/profile.json" \
    --change-json "${TMP_BASE}/change.json" \
    --compliance-regime commercial \
    --blast-radius-markdown "${TMP_BASE}/blast-radius.md" \
    --rollback "${TMP_BASE}/rollback.txt" \
    --rollback-confidence low \
    --catalog "${TMP_BASE}/catalog.json" \
    --output "${TMP_BASE}/should-not-render.md" \
    2>&1
)"
invalid_rc=$?
set -e
assert_exit_code 6 "$invalid_rc" "path traversal header template rejected"
assert_contains "mop-branding-template-missing" "$invalid_output" "path traversal emits template missing error"
summary
