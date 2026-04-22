#!/usr/bin/env bash
# render-artifact.sh — render the final yci:mop markdown artifact.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: render-artifact.sh \
  --profile <path> \
  --change-json <path> \
  --compliance-regime <value> \
  --blast-radius-markdown <path> \
  --rollback <path> \
  --rollback-confidence <level> \
  --catalog <path> \
  --output <path>
EOF
}

err() {
  local id="$1"
  local msg="$2"
  local code="${3:-6}"
  printf '[%s] %s\n' "$id" "$msg" >&2
  exit "$code"
}

profile_path=""
change_json_path=""
compliance_regime=""
blast_radius_md_path=""
rollback_path=""
rollback_confidence=""
catalog_path=""
output_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)               profile_path="${2:?--profile requires a path}"; shift 2 ;;
    --change-json)           change_json_path="${2:?--change-json requires a path}"; shift 2 ;;
    --compliance-regime)     compliance_regime="${2:?--compliance-regime requires a value}"; shift 2 ;;
    --blast-radius-markdown) blast_radius_md_path="${2:?--blast-radius-markdown requires a path}"; shift 2 ;;
    --rollback)              rollback_path="${2:?--rollback requires a path}"; shift 2 ;;
    --rollback-confidence)   rollback_confidence="${2:?--rollback-confidence requires a value}"; shift 2 ;;
    --catalog)               catalog_path="${2:?--catalog requires a path}"; shift 2 ;;
    --output)                output_path="${2:?--output requires a path}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; err "mop-render-failed" "Unknown flag: $1" 6 ;;
  esac
done

[[ -f "$profile_path" ]] || err "mop-render-failed" "Profile JSON not found: ${profile_path}" 6
[[ -f "$change_json_path" ]] || err "mop-render-failed" "Change JSON not found: ${change_json_path}" 6
[[ -f "$blast_radius_md_path" ]] || err "mop-render-failed" "Blast-radius markdown not found: ${blast_radius_md_path}" 6
[[ -f "$rollback_path" ]] || err "mop-render-failed" "Rollback file not found: ${rollback_path}" 6
[[ -f "$catalog_path" ]] || err "mop-render-failed" "Catalog JSON not found: ${catalog_path}" 6
[[ -n "$output_path" ]] || err "mop-render-failed" "Missing required flag: --output" 6
[[ -n "${compliance_regime//[[:space:]]/}" ]] || err "mop-render-failed" "Missing required flag: --compliance-regime" 6

case "$rollback_confidence" in
  high|medium|low) ;;
  *) err "mop-render-failed" "Invalid --rollback-confidence value: ${rollback_confidence}" 6 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd -P)}"

mkdir -p "$(dirname "$output_path")"

export MOP_TEMPLATE_PATH="${PLUGIN_ROOT}/skills/mop/references/artifact-template.md"
export MOP_PROFILE_PATH="$profile_path"
export MOP_CHANGE_JSON_PATH="$change_json_path"
export MOP_COMPLIANCE_REGIME="$compliance_regime"
export MOP_BLAST_RADIUS_PATH="$blast_radius_md_path"
export MOP_ROLLBACK_PATH="$rollback_path"
export MOP_ROLLBACK_CONFIDENCE="$rollback_confidence"
export MOP_CATALOG_PATH="$catalog_path"
export MOP_OUTPUT_PATH="$output_path"
export MOP_CONSULTANT_BRAND_SRC="${PLUGIN_ROOT}/skills/network-change-review/references/consultant-brand.md"
export MOP_PLUGIN_ROOT="${PLUGIN_ROOT}"

python3 <<'PYEOF'
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone

with open(os.environ["MOP_PROFILE_PATH"], encoding="utf-8") as profile_file:
    profile = json.load(profile_file)
with open(os.environ["MOP_CHANGE_JSON_PATH"], encoding="utf-8") as change_file:
    change = json.load(change_file)
with open(os.environ["MOP_CATALOG_PATH"], encoding="utf-8") as catalog_file:
    catalog = json.load(catalog_file)

tpl_full = open(os.environ["MOP_TEMPLATE_PATH"], encoding="utf-8").read()
template_start = re.search(r'(?m)^## Template\s*$', tpl_full)
if not template_start:
    sys.stderr.write("[mop-render-failed] artifact-template.md has no '## Template' section\n")
    sys.exit(6)
after_heading = tpl_full[template_start.end():]
rule_m = re.search(r'(?m)^---\s*$', after_heading)
if not rule_m:
    sys.stderr.write("[mop-render-failed] artifact-template.md template opening rule missing\n")
    sys.exit(6)
template_body = after_heading[rule_m.end():].strip()

consultant_src = open(os.environ["MOP_CONSULTANT_BRAND_SRC"], encoding="utf-8").read()
parts = re.split(r'(?m)^---\s*$', consultant_src)
consultant_brand = parts[1].strip() if len(parts) >= 3 else consultant_src.strip()
yci_commit = "unknown"
try:
    yci_commit = subprocess.check_output(
        ["git", "-C", os.environ["MOP_PLUGIN_ROOT"], "rev-parse", "HEAD"],
        text=True,
        stderr=subprocess.DEVNULL,
    ).strip()
except Exception:
    pass
consultant_brand = consultant_brand.replace("{{yci_commit}}", yci_commit)

header_template = profile.get("deliverable", {}).get("header_template", "")
profile_dir = os.path.dirname(os.environ["MOP_PROFILE_PATH"])
if "/" in header_template or header_template.endswith(".md"):
    invalid_header_template = (
        os.path.isabs(header_template)
        or os.path.sep in header_template
        or (os.path.altsep is not None and os.path.altsep in header_template)
        or ".." in header_template
    )
    if invalid_header_template:
        sys.stderr.write(f"[mop-branding-template-missing] Customer branding template not found: {header_template}\n")
        sys.exit(6)
    resolved_header = os.path.join(profile_dir, header_template)
    if not os.path.isfile(resolved_header):
        sys.stderr.write(f"[mop-branding-template-missing] Customer branding template not found: {header_template}\n")
        sys.exit(6)
    customer_brand = open(resolved_header, encoding="utf-8").read().strip()
else:
    customer_brand = str(header_template).strip()

def render_checks(items):
    if not items:
        return "_No checks in this catalog._"
    return "\n".join(
        f"- **[{item.get('id', '')}]** ({item.get('source', '')}/{item.get('category', '')}) — {item.get('description', '')}"
        for item in items
    )

def as_markdown_sections(prefix, checks):
    section = str(change.get(prefix, "")).strip()
    if section and checks:
        return section + "\n\n" + checks
    if section:
        return section
    return checks

safety = profile.get("safety", {})
if not isinstance(safety, dict):
    sys.stderr.write("[mop-abort-criteria-failed] profile.safety must be a mapping\n")
    sys.exit(6)

abort_lines = []
posture = str(safety.get("default_posture", "")).strip()
if posture and posture != "apply":
    abort_lines.append(f"- Abort unless a human operator explicitly promotes the posture from `{posture}` to `apply` for this change.")
elif posture == "apply":
    abort_lines.append("- Abort if the approved apply workflow cannot be executed exactly as reviewed.")
else:
    sys.stderr.write("[mop-abort-criteria-failed] Missing safety.default_posture in profile\n")
    sys.exit(6)

if safety.get("change_window_required") is True:
    abort_lines.append("- Abort if the approved change window is not open.")
else:
    abort_lines.append("- Abort if the pre-change state cannot be captured or any pre-change checklist item fails.")

scope = str(safety.get("scope_enforcement", "")).strip()
if scope == "block":
    abort_lines.append("- Abort immediately if scope validation indicates the change exceeds the engagement scope tags.")
elif scope == "warn":
    abort_lines.append("- Abort if any scope warning cannot be positively cleared by the operator or customer approver.")
elif scope == "off":
    abort_lines.append("- Abort if the operator cannot confirm the intended customer scope before apply.")
else:
    sys.stderr.write("[mop-abort-criteria-failed] Missing or invalid safety.scope_enforcement in profile\n")
    sys.exit(6)

conf = os.environ["MOP_ROLLBACK_CONFIDENCE"]
if conf in {"low", "medium"}:
    abort_lines.append(
        f"- Abort before apply until a human operator accepts the {conf}-confidence rollback path."
    )

rollback_callout = ""
if conf in {"low", "medium"}:
    rollback_callout = (
        f"> **Rollback confidence:** {conf}\n"
        ">\n"
        "> Manual review is required before applying this change.\n"
    )

slots = {
    "customer_brand_block": customer_brand,
    "consultant_brand_block": consultant_brand,
    "change_id": str(change.get("change_id", "unknown")),
    "customer_id": str(profile.get("customer", {}).get("id", "unknown")),
    "compliance_regime": os.environ.get("MOP_COMPLIANCE_REGIME") or str(profile.get("compliance", {}).get("regime", "unknown")),
    "timestamp_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "change_summary": str(change.get("summary", "")).strip(),
    "pre_change_state": as_markdown_sections("pre_change_markdown", render_checks(catalog.get("pre_check", []))),
    "apply_commands": str(change.get("apply_markdown", "")).strip(),
    "post_change_state": as_markdown_sections("post_change_markdown", render_checks(catalog.get("post_check", []))),
    "blast_radius": open(os.environ["MOP_BLAST_RADIUS_PATH"], encoding="utf-8").read().strip(),
    "rollback_plan": open(os.environ["MOP_ROLLBACK_PATH"], encoding="utf-8").read().strip(),
    "rollback_confidence_callout": rollback_callout.strip(),
    "abort_criteria": "\n".join(abort_lines),
    "yci_commit": yci_commit,
}

for name, value in slots.items():
    template_body = template_body.replace(f"{{{{{name}}}}}", value)

open(os.environ["MOP_OUTPUT_PATH"], "w", encoding="utf-8").write(template_body.rstrip() + "\n")
PYEOF
