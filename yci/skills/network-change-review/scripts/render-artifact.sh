#!/usr/bin/env bash
# render-artifact.sh — yci:network-change-review artifact renderer.
#
# Reads a filled slot-map (profile, adapter dir, subagent outputs, evidence stub)
# and renders the final Network Change Review artifact to --output by substituting
# every {{slot_name}} token in artifact-template.md with the corresponding value.
#
# Usage:
#   render-artifact.sh \
#     --profile <path>               \  # profile JSON (load-profile.sh output)
#     --adapter-dir <path>           \  # resolved compliance adapter directory
#     --change-plan <path>           \  # markdown: ycc:plan subagent output
#     --diff-review <path>           \  # markdown: ycc:code-review output
#     --blast-radius-markdown <path> \  # markdown: blast-radius/render-markdown.sh output
#     --rollback <path>              \  # text: derive-rollback.sh rollback steps
#     --rollback-confidence <level>  \  # high|medium|low
#     --pre-check-catalog <path>     \  # JSON: build-check-catalogs.sh output
#     --post-check-catalog <path>    \  # JSON: build-check-catalogs.sh output
#     --evidence-stub <path>         \  # YAML: render-evidence-stub.sh output
#     --output <path>                   # where to write the rendered artifact
#
# Stdout: nothing on success (or output path for piping).
# Stderr: errors only, in [ncr-<id>] format.
# Exit codes:
#   0  success
#   1  usage / missing flag
#   6  branding or adapter template not found  (ncr-branding-template-missing /
#                                               ncr-adapter-template-missing)
#   7  post-render cross-customer isolation scan failed (ncr-cross-customer-leak-detected)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
    cat >&2 <<'EOF'
Usage: render-artifact.sh [OPTIONS]

Options:
  --profile <path>               Profile JSON (load-profile.sh output)        [required]
  --adapter-dir <path>           Resolved compliance adapter directory         [required]
  --change-plan <path>           Markdown: ycc:plan subagent output            [required]
  --diff-review <path>           Markdown: ycc:code-review output              [required]
  --blast-radius-markdown <path> Markdown: blast-radius/render-markdown.sh     [required]
  --rollback <path>              Text: derive-rollback.sh rollback steps       [required]
  --rollback-confidence <level>  high|medium|low                               [required]
  --pre-check-catalog <path>     JSON: build-check-catalogs.sh (pre_check)     [required]
  --post-check-catalog <path>    JSON: build-check-catalogs.sh (post_check)    [required]
  --evidence-stub <path>         YAML: render-evidence-stub.sh output          [required]
  --output <path>                Destination for the rendered artifact          [required]
  -h, --help                     Show this help message
EOF
    exit 1
}

err() {
    local id="$1"
    local msg="$2"
    local code="${3:-1}"
    printf '[%s] %s\n' "${id}" "${msg}" >&2
    exit "${code}"
}

# ---------------------------------------------------------------------------
# Flag parsing
# ---------------------------------------------------------------------------

profile_path=""
adapter_dir=""
change_plan_path=""
diff_review_path=""
blast_radius_md_path=""
rollback_path=""
rollback_confidence=""
pre_check_path=""
post_check_path=""
evidence_stub_path=""
output_path=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)              profile_path="$2";         shift 2 ;;
        --adapter-dir)          adapter_dir="$2";          shift 2 ;;
        --change-plan)          change_plan_path="$2";     shift 2 ;;
        --diff-review)          diff_review_path="$2";     shift 2 ;;
        --blast-radius-markdown) blast_radius_md_path="$2"; shift 2 ;;
        --rollback)             rollback_path="$2";        shift 2 ;;
        --rollback-confidence)  rollback_confidence="$2";  shift 2 ;;
        --pre-check-catalog)    pre_check_path="$2";       shift 2 ;;
        --post-check-catalog)   post_check_path="$2";      shift 2 ;;
        --evidence-stub)        evidence_stub_path="$2";   shift 2 ;;
        --output)               output_path="$2";          shift 2 ;;
        -h|--help)              usage ;;
        *) printf 'Unknown flag: %s\n' "$1" >&2; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Validation guards
# ---------------------------------------------------------------------------

[[ -n "${profile_path}"         ]] || err "ncr-profile-load-failed"        "Missing required flag: --profile"         1
[[ -n "${adapter_dir}"          ]] || err "ncr-adapter-unresolvable"        "Missing required flag: --adapter-dir"     1
[[ -n "${change_plan_path}"     ]] || err "ncr-adapter-template-missing"    "Missing required flag: --change-plan"     1
[[ -n "${diff_review_path}"     ]] || err "ncr-adapter-template-missing"    "Missing required flag: --diff-review"     1
[[ -n "${blast_radius_md_path}" ]] || err "ncr-blast-radius-failed"        "Missing required flag: --blast-radius-markdown" 1
[[ -n "${rollback_path}"        ]] || err "ncr-rollback-missing-reverse"   "Missing required flag: --rollback"        1
[[ -n "${rollback_confidence}"  ]] || err "ncr-rollback-ambiguous"         "Missing required flag: --rollback-confidence" 1
[[ -n "${pre_check_path}"       ]] || err "ncr-adapter-template-missing"   "Missing required flag: --pre-check-catalog"  1
[[ -n "${post_check_path}"      ]] || err "ncr-adapter-template-missing"   "Missing required flag: --post-check-catalog" 1
[[ -n "${evidence_stub_path}"   ]] || err "ncr-adapter-template-missing"   "Missing required flag: --evidence-stub"   1
[[ -n "${output_path}"          ]] || err "ncr-adapter-template-missing"   "Missing required flag: --output"          1

[[ -f "${profile_path}"         ]] || err "ncr-profile-load-failed"        "Profile not found: ${profile_path}"       2
[[ -d "${adapter_dir}"          ]] || err "ncr-adapter-unresolvable"        "Adapter directory not found: ${adapter_dir}" 2
[[ -f "${change_plan_path}"     ]] || err "ncr-adapter-template-missing"   "change-plan file not found: ${change_plan_path}" 6
[[ -f "${diff_review_path}"     ]] || err "ncr-adapter-template-missing"   "diff-review file not found: ${diff_review_path}" 6
[[ -f "${blast_radius_md_path}" ]] || err "ncr-blast-radius-failed"        "blast-radius-markdown not found: ${blast_radius_md_path}" 5
[[ -f "${rollback_path}"        ]] || err "ncr-rollback-missing-reverse"   "rollback file not found: ${rollback_path}" 3
[[ -f "${pre_check_path}"       ]] || err "ncr-adapter-template-missing"   "pre-check-catalog not found: ${pre_check_path}" 6
[[ -f "${post_check_path}"      ]] || err "ncr-adapter-template-missing"   "post-check-catalog not found: ${post_check_path}" 6
[[ -f "${evidence_stub_path}"   ]] || err "ncr-adapter-template-missing"   "evidence-stub not found: ${evidence_stub_path}" 6

case "${rollback_confidence}" in
    high|medium|low) ;;
    *) err "ncr-rollback-ambiguous" "Invalid --rollback-confidence value: ${rollback_confidence} (must be high|medium|low)" 1 ;;
esac

# ---------------------------------------------------------------------------
# Branding resolution
# ---------------------------------------------------------------------------

# Resolve yci_commit first — needed inside consultant-brand.md.
yci_commit="unknown"
if command -v git &>/dev/null; then
    yci_commit="$(git -C "${PLUGIN_ROOT}" rev-parse HEAD 2>/dev/null || printf 'unknown')"
fi

# Read consultant brand block and resolve {{yci_commit}}.
# consultant-brand.md contains a documentation header followed by a --- separator,
# then the actual brand block content (## Prepared by …) and a trailing ---.
# We extract only the brand block section — everything between the first and last
# bare "---" rules — so the documentation prose (which references the slot name
# literally) is not included in the substitution value.
consultant_brand_src="${PLUGIN_ROOT}/skills/network-change-review/references/consultant-brand.md"
if [[ ! -f "${consultant_brand_src}" ]]; then
    err "ncr-adapter-template-missing" "Consultant brand file not found at ${consultant_brand_src}" 6
fi
if ! consultant_brand_block="$(python3 - "${consultant_brand_src}" <<'PYEXTRACT'
import sys, re
text = open(sys.argv[1]).read()
# Find content between the first --- and last --- separators.
parts = re.split(r'(?m)^---\s*$', text)
if len(parts) < 3:
    # Fallback: use everything after the first --- if structure differs.
    m = re.search(r'(?m)^---\s*$', text)
    block = text[m.end():].strip() if m else text.strip()
else:
    # parts[0] = doc header, parts[1] = brand block, parts[2] = trailing (usually empty)
    block = parts[1].strip()
print(block)
PYEXTRACT
)"; then
    err "ncr-adapter-template-missing" "Failed to extract brand block from ${consultant_brand_src}" 6
fi
[[ -n "${consultant_brand_block}" ]] \
    || err "ncr-adapter-template-missing" "Failed to extract brand block from ${consultant_brand_src}" 6
consultant_brand_block="${consultant_brand_block//\{\{yci_commit\}\}/${yci_commit}}"

# Resolve customer brand block from profile.deliverable.header_template.
header_template="$(python3 -c "
import json, sys
try:
    p = json.load(open(sys.argv[1]))
    print(p['deliverable']['header_template'])
except Exception as e:
    sys.exit(str(e))
" "${profile_path}" 2>/dev/null)" || err "ncr-profile-load-failed" "Could not extract deliverable.header_template from ${profile_path}" 2

if [[ "${header_template}" == */* || "${header_template}" == *.md ]]; then
    # Path-like — resolve relative to the profile file's directory first
    # (portable: profiles + their assets can be dropped anywhere together),
    # then fall back to the literal path (absolute, or relative to CWD).
    profile_dir="$(cd "$(dirname "${profile_path}")" && pwd)"
    if [[ "${header_template}" = /* ]]; then
        resolved_header="${header_template}"
    elif [[ -f "${profile_dir}/${header_template}" ]]; then
        resolved_header="${profile_dir}/${header_template}"
    else
        resolved_header="${header_template}"
    fi
    if [[ ! -f "${resolved_header}" ]]; then
        err "ncr-branding-template-missing" "Customer branding template not found at ${header_template} (tried ${profile_dir}/${header_template} and literal)" 6
    fi
    customer_brand_block="$(< "${resolved_header}")"
else
    # Inline markdown string.
    customer_brand_block="${header_template}"
fi

# ---------------------------------------------------------------------------
# Main body — full slot-replacement of artifact-template.md
# ---------------------------------------------------------------------------

mkdir -p "$(dirname "${output_path}")"

# Export all inputs as env vars so the inline Python block can read them.
export NCR_TEMPLATE_PATH="${PLUGIN_ROOT}/skills/network-change-review/references/artifact-template.md"
export NCR_CUSTOMER_BRAND="${customer_brand_block}"
export NCR_CONSULTANT_BRAND="${consultant_brand_block}"
export NCR_CHANGE_PLAN_PATH="${change_plan_path}"
export NCR_DIFF_REVIEW_PATH="${diff_review_path}"
export NCR_BLAST_RADIUS_PATH="${blast_radius_md_path}"
export NCR_ROLLBACK_PATH="${rollback_path}"
export NCR_ROLLBACK_CONFIDENCE="${rollback_confidence}"
export NCR_PRE_CHECK_PATH="${pre_check_path}"
export NCR_POST_CHECK_PATH="${post_check_path}"
export NCR_EVIDENCE_STUB_PATH="${evidence_stub_path}"
export NCR_OUTPUT_PATH="${output_path}"
export NCR_PROFILE_PATH="${profile_path}"

python3 <<'PYEOF'
import os, json, sys, re, subprocess

# ── Load and extract the template half ──────────────────────────────────────
tpl_path = os.environ["NCR_TEMPLATE_PATH"]
try:
    tpl_full = open(tpl_path).read()
except OSError as exc:
    sys.stderr.write(f"[ncr-adapter-template-missing] Cannot read artifact-template.md: {exc}\n")
    sys.exit(6)

# The template half lives after the "## Template" heading.
# Locate "## Template", then find the first bare "---" rule that opens the
# template body. Capture everything from that point up to (but not including)
# the "## Rendered Example" section or end-of-file.
# We do NOT use a single regex because the template body itself contains ##
# headings and --- rules, which confuse a greedy/non-greedy single-pass match.
template_start = re.search(r'(?m)^## Template\s*$', tpl_full)
if not template_start:
    sys.stderr.write(
        "[ncr-adapter-template-missing] artifact-template.md has no '## Template' section\n"
    )
    sys.exit(6)

after_heading = tpl_full[template_start.end():]

# Find the first bare "---" rule after the heading (skips the "> Copy …" note).
rule_m = re.search(r'(?m)^---\s*$', after_heading)
if not rule_m:
    sys.stderr.write(
        "[ncr-adapter-template-missing] artifact-template.md '## Template' section has no "
        "opening '---' rule\n"
    )
    sys.exit(6)

template_raw = after_heading[rule_m.end():]

# The template runs until "## Rendered Example" or end-of-file.
end_m = re.search(r'(?m)^## Rendered Example', template_raw)
template_body = (template_raw[:end_m.start()] if end_m else template_raw).strip()

# ── Parse evidence stub YAML ─────────────────────────────────────────────────
import yaml

stub_path = os.environ["NCR_EVIDENCE_STUB_PATH"]
try:
    stub_text = open(stub_path).read()
except OSError as exc:
    sys.stderr.write(f"[ncr-adapter-template-missing] Cannot read evidence-stub: {exc}\n")
    sys.exit(6)

# Strip YAML --- fences before parsing.
stub_body = stub_text.strip()
if stub_body.startswith("---"):
    stub_body = re.sub(r'^---\s*\n', '', stub_body, count=1)
    stub_body = re.sub(r'\n---\s*$', '', stub_body)
try:
    stub = yaml.safe_load(stub_body) or {}
except yaml.YAMLError as exc:
    sys.stderr.write(f"[ncr-adapter-template-missing] Cannot parse evidence-stub YAML: {exc}\n")
    sys.exit(6)

# ── Rollback confidence callout ───────────────────────────────────────────────
conf = os.environ["NCR_ROLLBACK_CONFIDENCE"]
if conf in ("low", "medium"):
    rollback_callout = (
        f"> **⚠ Rollback Confidence: {conf}**\n"
        f">\n"
        f"> Manual review required. See the Rollback Plan section.\n"
    )
else:
    rollback_callout = ""

# ── Check catalog rendering ───────────────────────────────────────────────────
def render_checks(items):
    if not items:
        return "_No checks in this catalog._"
    lines = []
    for c in items:
        cid  = c.get("id", "")
        src  = c.get("source", "")
        cat  = c.get("category", "")
        desc = c.get("description", "")
        lines.append(f"- **[{cid}]** ({src}/{cat}) — {desc}")
    return "\n".join(lines)

def load_catalog_array(path, key):
    """Load a JSON file and return the array under `key`, or the file itself if it's an array."""
    try:
        data = json.load(open(path))
    except (OSError, json.JSONDecodeError) as exc:
        sys.stderr.write(f"[ncr-adapter-template-missing] Cannot read catalog {path}: {exc}\n")
        sys.exit(6)
    if isinstance(data, list):
        return data
    if isinstance(data, dict) and key in data:
        return data[key]
    # If the dict doesn't have the expected key, return all values merged as flat list.
    combined = []
    for v in data.values():
        if isinstance(v, list):
            combined.extend(v)
    return combined

pre_checks  = load_catalog_array(os.environ["NCR_PRE_CHECK_PATH"],  "pre_check")
post_checks = load_catalog_array(os.environ["NCR_POST_CHECK_PATH"], "post_check")

# ── Read file-based slots ─────────────────────────────────────────────────────
def read_file(env_key, slot_name):
    path = os.environ[env_key]
    try:
        return open(path).read()
    except OSError as exc:
        sys.stderr.write(f"[ncr-adapter-template-missing] Cannot read {slot_name} ({path}): {exc}\n")
        sys.exit(6)

# The evidence_stub slot: collapsible <details> + ```yaml fence (artifact-template).
raw_yaml_content = stub_text.strip()
# Remove the outer --- fences so we don't double-fence.
raw_yaml_content = re.sub(r'^---\s*\n', '', raw_yaml_content, count=1)
raw_yaml_content = re.sub(r'\n---\s*$', '', raw_yaml_content)
raw_yaml_content = raw_yaml_content.strip()
evidence_stub_block = (
    "<details>\n"
    "<summary>Evidence YAML (expand to view)</summary>\n\n"
    "```yaml\n"
    + raw_yaml_content
    + "\n```\n\n"
    "</details>\n"
)

# ── Assemble slot map ─────────────────────────────────────────────────────────
slots = {
    "customer_brand_block":       os.environ["NCR_CUSTOMER_BRAND"],
    "consultant_brand_block":     os.environ["NCR_CONSULTANT_BRAND"],
    "change_id":                  stub.get("change_id", ""),
    "timestamp_utc":              stub.get("timestamp_utc", ""),
    "customer_id":                stub.get("customer_id", ""),
    "compliance_regime":          stub.get("compliance_regime", ""),
    "change_summary":             stub.get("change_summary", ""),
    "profile_commit":             stub.get("profile_commit", "unknown"),
    "yci_commit":                 stub.get("yci_commit", "unknown"),
    "change_plan":                read_file("NCR_CHANGE_PLAN_PATH",   "--change-plan"),
    "diff_review":                read_file("NCR_DIFF_REVIEW_PATH",   "--diff-review"),
    "blast_radius":               read_file("NCR_BLAST_RADIUS_PATH",  "--blast-radius-markdown"),
    "rollback_plan":              read_file("NCR_ROLLBACK_PATH",      "--rollback"),
    "rollback_confidence_callout": rollback_callout,
    "pre_check_catalog":          render_checks(pre_checks),
    "post_check_catalog":         render_checks(post_checks),
    "evidence_stub":              evidence_stub_block,
}

# ── Perform slot replacement ──────────────────────────────────────────────────
out = template_body
for k, v in slots.items():
    out = out.replace("{{" + k + "}}", v)

# ── Detect unfilled slots ─────────────────────────────────────────────────────
unfilled = re.findall(r'\{\{[^}]+\}\}', out)
if unfilled:
    sys.stderr.write(
        f"[ncr-adapter-template-missing] Template has unfilled slots after replacement: "
        f"{sorted(set(unfilled))}\n"
    )
    sys.exit(6)

# ── Write output ──────────────────────────────────────────────────────────────
output_path = os.environ["NCR_OUTPUT_PATH"]
try:
    with open(output_path, "w") as f:
        f.write(out.strip() + "\n")
except OSError as exc:
    sys.stderr.write(f"[ncr-adapter-template-missing] Cannot write output {output_path}: {exc}\n")
    sys.exit(6)
PYEOF

# Post-render cross-customer isolation when the caller provides a resolved data root
# (same belt-and-suspenders pass as review.sh step 20). Exit 7 on deny.
if [[ -n "${YCI_DATA_ROOT_RESOLVED:-}" ]]; then
  active="${YCI_ACTIVE_CUSTOMER:-}"
  if [[ -z "$active" ]]; then
    active="$(
      python3 -c "import yaml,sys; print(yaml.safe_load(open(sys.argv[1]))['customer_id'])" \
        "${evidence_stub_path}" 2>/dev/null || true
    )"
  fi
  if [[ -n "$active" ]]; then
    _iso_payload="$(mktemp)"
    python3 - "${output_path}" "${_iso_payload}" <<'PYISO'
import json, sys
path, out_path = sys.argv[1], sys.argv[2]
payload = {
    "tool_name": "Write",
    "tool_input": {"file_path": path, "content": open(path).read()},
}
with open(out_path, "w") as fh:
    json.dump(payload, fh)
PYISO
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT}}"
    # shellcheck source=/dev/null
    source "${PLUGIN_ROOT}/skills/_shared/customer-isolation/detect.sh"
    set +e
    isolation_decision="$(
      YCI_ACTIVE_CUSTOMER="$active" \
      YCI_DATA_ROOT_RESOLVED="${YCI_DATA_ROOT_RESOLVED}" \
      isolation_check_payload --payload-file "${_iso_payload}"
    )"
    iso_rc=$?
    set -e
    rm -f "${_iso_payload}"
    if [[ "${iso_rc}" -ne 0 ]]; then
      rm -f "${output_path}"
      err "ncr-cross-customer-leak-detected" "Customer isolation check failed (internal error)." 7
    fi
    decision_value="$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get('decision','deny'))" "${isolation_decision}" 2>/dev/null || echo deny)"
    if [[ "${decision_value}" == "deny" ]]; then
      rm -f "${output_path}"
      err "ncr-cross-customer-leak-detected" "Cross-customer identifier leak detected in rendered artifact." 7
    fi
  fi
fi

printf '%s\n' "${output_path}"
