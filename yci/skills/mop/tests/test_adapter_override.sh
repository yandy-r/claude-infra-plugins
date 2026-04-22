#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HELPERS="${SCRIPT_DIR}/helpers.sh"
if [[ ! -f "$HELPERS" || ! -r "$HELPERS" ]]; then
    printf 'test_adapter_override.sh: missing or unreadable helpers: %s\n' "$HELPERS" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$HELPERS"

RENDER="${SKILL_ROOT}/scripts/render-artifact.sh"
if [[ ! -f "$RENDER" || ! -r "$RENDER" || ! -x "$RENDER" ]]; then
    printf 'test_adapter_override.sh: render script missing or not executable: %s\n' "$RENDER" >&2
    exit 1
fi
TMP_BASE="$(mktemp -d -t yci-mop-adapter-XXXX)" || {
    printf 'test_adapter_override.sh: failed to create temp dir\n' >&2
    exit 1
}
if [[ -z "$TMP_BASE" ]]; then
    printf 'test_adapter_override.sh: mktemp returned an empty path\n' >&2
    exit 1
fi
trap 'rm -rf "${TMP_BASE}"' EXIT

cat > "${TMP_BASE}/profile.json" <<'EOF'
{
  "customer": {"id": "widget-corp"},
  "compliance": {"regime": "commercial"},
  "deliverable": {"header_template": "header.md"},
  "safety": {
    "default_posture": "review",
    "change_window_required": false,
    "scope_enforcement": "warn"
  }
}
EOF

cat > "${TMP_BASE}/header.md" <<'EOF'
## Widget Corp
EOF

cat > "${TMP_BASE}/change.json" <<'EOF'
{
  "change_id": "mop-test-override",
  "summary": "Adapter override test.",
  "pre_change_markdown": "pre",
  "apply_markdown": "apply",
  "post_change_markdown": "post"
}
EOF

cat > "${TMP_BASE}/blast-radius.md" <<'EOF'
impact
EOF

cat > "${TMP_BASE}/rollback.txt" <<'EOF'
rollback
EOF

cat > "${TMP_BASE}/catalog.json" <<'EOF'
{"pre_check":[],"post_check":[]}
EOF

output_path="${TMP_BASE}/mop.md"
(
  cd "$TMP_BASE" || exit
  bash "$RENDER" \
    --profile "${TMP_BASE}/profile.json" \
    --change-json "${TMP_BASE}/change.json" \
    --compliance-regime none \
    --blast-radius-markdown "${TMP_BASE}/blast-radius.md" \
    --rollback "${TMP_BASE}/rollback.txt" \
    --rollback-confidence high \
    --catalog "${TMP_BASE}/catalog.json" \
    --output "$output_path"
)

rendered="$(cat "$output_path")"
assert_contains '**Compliance regime:** `none`' "$rendered" "adapter override rendered"
summary
