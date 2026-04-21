#!/usr/bin/env bash
# review.sh — yci:network-change-review top-level orchestrator.
#
# Implements the 22-step composition pipeline in references/composition-contract.md.
# This is THE script that /yci:review <change> invokes.
#
# Usage: review.sh --change <path> [OPTIONS]
#
# Flags:
#   --change <path>      (required) change file (diff, YAML, or playbook)
#   --data-root <path>   override data root (else $YCI_DATA_ROOT or ~/.config/yci)
#   --customer <name>    override active customer (else resolved via env/dotfile/state)
#   --adapter <regime>   compliance adapter override (else from profile)
#   --format <format>    deliverable format override (else from profile.deliverable.format)
#   --output-dir <path>  override final artifact directory
#   --change-plan <path> pre-generated change plan markdown (from ycc:planner subagent)
#   --diff-review <path> pre-generated diff review markdown (from yci:change-reviewer subagent)
#   -h, --help           show this help and exit 0
#
# Stdout:  final artifact path (one line) on success
# Stderr:  yci-ncr: [step N/22] progress; [ncr-<id>] errors
# Exit:    0 success | 2 setup | 3 input shape | 4 sanitizer | 5 composed | 6 render | 7 isolation
#
# Note: shell scripts cannot invoke Agent tools. ycc:planner and yci:change-reviewer
# integrations happen at the SKILL.md prompt layer. Pass their output files here via
# --change-plan and --diff-review; omitting either inserts a placeholder block.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd -P)}"
TOTAL_STEPS=22

step() { printf 'yci-ncr: [step %s/%s] %s\n' "$1" "$TOTAL_STEPS" "$2" >&2; }

err() {
  local id="$1" msg="$2" code="$3"
  printf '[%s] %s\n' "$id" "$msg" >&2
  exit "$code"
}

usage() {
  cat >&2 <<'EOF'
Usage: review.sh --change <path> [OPTIONS]

Required:
  --change <path>      Change file (unified-diff, structured-yaml, or playbook)

Options:
  --data-root <path>   Override data root (else $YCI_DATA_ROOT or ~/.config/yci)
  --customer <name>    Override active customer (else resolved from env/dotfile/state)
  --adapter <regime>   Compliance adapter override (else from profile)
  --format <format>    Deliverable format override (else from profile.deliverable.format)
  --output-dir <path>  Override final artifact directory
  --change-plan <path> Pre-generated change plan markdown (from ycc:planner)
  --diff-review <path> Pre-generated diff review markdown (from yci:change-reviewer)
  -h, --help           Show this help and exit 0

Exit codes (references/error-messages.md):
  0 success — artifact path on stdout
  2 setup/configuration  3 input shape  4 sanitizer
  5 composed skill fail  6 render env   7 isolation gate

Stderr: [ncr-<id>] <message>  (ID prefix is stable for automated parsing)
EOF
}

# ── Step 1 — Parse flags; validate --change ──────────────────────────────────
step 1 "Parsing flags and validating required inputs"

change_path="" data_root_flag="" customer_flag=""
adapter_flag="" format_flag=""   output_dir_flag=""
change_plan_path="" diff_review_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --change)       change_path="${2:?--change requires a path}";       shift 2 ;;
    --data-root)    data_root_flag="${2:?--data-root requires a path}"; shift 2 ;;
    --customer)     customer_flag="${2:?--customer requires a name}";   shift 2 ;;
    --adapter)      adapter_flag="${2:?--adapter requires a regime}";   shift 2 ;;
    --format)       format_flag="${2:?--format requires a value}";      shift 2 ;;
    --output-dir)   output_dir_flag="${2:?--output-dir requires a path}"; shift 2 ;;
    --change-plan)  change_plan_path="${2:?--change-plan requires a path}"; shift 2 ;;
    --diff-review)  diff_review_path="${2:?--diff-review requires a path}"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *)              usage >&2; err "ncr-diff-unsupported-shape" "Unknown flag: $1" 3 ;;
  esac
done

[[ -n "$change_path" ]] || err "ncr-diff-unsupported-shape" "--change is required. Run --help for usage." 3
[[ -e "$change_path" ]] || err "ncr-diff-unsupported-shape" "Change file not found: ${change_path}" 3
[[ -r "$change_path" ]] || err "ncr-diff-unsupported-shape" "Change file not readable: ${change_path}" 3
change_path="$(cd "$(dirname "$change_path")" && pwd -P)/$(basename "$change_path")"

# ── Step 2 — Create workdir; register EXIT trap ──────────────────────────────
step 2 "Creating temporary working directory"

workdir="$(mktemp -d -t yci-ncr-XXXX)"
export NCR_WORKDIR="$workdir"

cleanup() {
  if [[ "${YCI_KEEP_WORKDIR:-0}" == "1" ]]; then
    printf 'yci-ncr: keeping workdir for debug: %s\n' "$workdir" >&2
  else
    rm -rf "$workdir"
  fi
}
trap cleanup EXIT

# ── Step 3 — Resolve data root ───────────────────────────────────────────────
step 3 "Resolving data root"

# shellcheck source=/dev/null
source "${PLUGIN_ROOT}/skills/_shared/scripts/resolve-data-root.sh"

if [[ -n "$data_root_flag" ]]; then
  data_root="$(yci_resolve_data_root --data-root "$data_root_flag")"
else
  data_root="$(yci_resolve_data_root)"
fi
export YCI_DATA_ROOT_RESOLVED="$data_root"

# ── Step 4 — Resolve active customer ─────────────────────────────────────────
step 4 "Resolving active customer"

if [[ -n "$customer_flag" ]]; then
  customer="$(YCI_CUSTOMER="$customer_flag" bash "${PLUGIN_ROOT}/skills/customer-profile/scripts/resolve-customer.sh" \
    --data-root "$data_root" 2>&1)" \
    || err "ncr-customer-unresolved" "Invalid or unresolved customer (--customer). Use a valid id (see resolve-customer.sh)." 2
else
  customer="$(bash "${PLUGIN_ROOT}/skills/customer-profile/scripts/resolve-customer.sh" \
    --data-root "$data_root" 2>&1)" \
    || err "ncr-customer-unresolved" "No active customer. Run /yci:switch <customer> first." 2
fi
[[ -n "$customer" ]] \
  || err "ncr-customer-unresolved" "No active customer. Run /yci:switch <customer> first." 2
export YCI_ACTIVE_CUSTOMER="$customer"

# ── Step 5 — Load customer profile ───────────────────────────────────────────
step 5 "Loading customer profile for '${customer}'"

if ! bash "${PLUGIN_ROOT}/skills/customer-profile/scripts/load-profile.sh" \
    "$data_root" "$customer" \
    > "${workdir}/profile.json" 2>"${workdir}/profile-load.err"; then
  err "ncr-profile-load-failed" "Failed to load profile: $(cat "${workdir}/profile-load.err" 2>/dev/null)" 2
fi

# ── Step 6 — Stage branding asset (header_template path fix-up) ──────────────
step 6 "Staging branding assets"

header_template_raw="$(python3 -c "
import json, sys
p = json.load(open(sys.argv[1]))
print(p.get('deliverable', {}).get('header_template', ''))
" "${workdir}/profile.json" 2>/dev/null)" || header_template_raw=""

if [[ -n "$header_template_raw" ]] && [[ "$header_template_raw" == */* || "$header_template_raw" == *.md ]]; then
  template_basename="$(basename "$header_template_raw")"
  source_path="${data_root}/profiles/${header_template_raw}"
  if [[ -f "$source_path" ]]; then
    cp "$source_path" "${workdir}/${template_basename}"
    python3 - "${workdir}/profile.json" "$template_basename" <<'PYEOF'
import json, sys
path, basename = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = json.load(fh)
data.setdefault("deliverable", {})["header_template"] = basename
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
PYEOF
  fi
fi

# ── Step 7 — Load compliance adapter ─────────────────────────────────────────
step 7 "Loading compliance adapter"

if [[ -n "$adapter_flag" ]]; then
  adapter_args=("--export" "--regime" "$adapter_flag")
else
  adapter_args=("--export" "--profile-json-path" "${workdir}/profile.json")
fi

adapter_exports="$(bash "${PLUGIN_ROOT}/skills/_shared/scripts/load-compliance-adapter.sh" \
  "${adapter_args[@]}" 2>&1)" \
  || err "ncr-adapter-unresolvable" "Failed to resolve compliance adapter: ${adapter_exports}" 2

eval "$adapter_exports"
export YCI_ADAPTER_DIR YCI_ADAPTER_REGIME YCI_ADAPTER_HAS_SCHEMA
export YCI_ACTIVE_REGIME="${YCI_ADAPTER_REGIME:-}"
[[ -n "${YCI_ADAPTER_DIR:-}" ]] \
  || err "ncr-adapter-unresolvable" "YCI_ADAPTER_DIR is empty after adapter load" 2

# ── Step 8 — Input preflight: cross-customer identifier scan ─────────────────
# Sanitizing the raw input would redact the hostnames parse-change.sh needs to
# resolve targets. Instead we do a fast detect-only preflight: load every
# OTHER customer's profile under <data-root>/profiles/, extract their
# customer_id / hostname_suffix / ipv4_ranges, and grep the input for any
# match. If found, fail fast with ncr-cross-customer-leak-detected (AC3).
# The full artifact is still sanitized + double-checked post-render.
step 8 "Preflight: scanning input for foreign-customer identifiers"

preflight_exit=0
bash "${PLUGIN_ROOT}/skills/network-change-review/scripts/preflight-cross-customer.sh" \
  --data-root "$data_root" \
  --customer "$customer" \
  --change "$change_path" \
  > "${workdir}/preflight.out" 2>"${workdir}/preflight.err" || preflight_exit=$?
if [[ $preflight_exit -eq 7 ]]; then
  err "ncr-cross-customer-leak-detected" \
    "Foreign-customer identifiers detected in raw change input — refusing to proceed. $(< "${workdir}/preflight.err")" 7
elif [[ $preflight_exit -eq 1 ]]; then
  err "ncr-adapter-unresolvable" \
    "Preflight configuration error: $(< "${workdir}/preflight.err")" 2
elif [[ $preflight_exit -ne 0 ]]; then
  err "ncr-adapter-unresolvable" "Preflight failed: $(< "${workdir}/preflight.err")" 2
fi

# ── Step 9 — Parse and normalize the (unmodified) change ─────────────────────
step 9 "Parsing and normalizing change file"

inventory_root_rel="$(python3 -c "
import json, sys
p = json.load(open(sys.argv[1]))
print(p.get('inventory', {}).get('root', ''))
" "${workdir}/profile.json" 2>/dev/null)" || inventory_root_rel=""

if [[ -n "$inventory_root_rel" ]]; then
  profiles_dir="${data_root}/profiles"
  if   [[ "${inventory_root_rel}" = /* ]];                               then export YCI_INVENTORY_ROOT="$inventory_root_rel"
  elif [[ -d "${profiles_dir}/${inventory_root_rel}" ]];                 then export YCI_INVENTORY_ROOT="${profiles_dir}/${inventory_root_rel}"
  else                                                                        export YCI_INVENTORY_ROOT="${data_root}/${inventory_root_rel}"
  fi
else
  export YCI_INVENTORY_ROOT=""
fi

if ! bash "${PLUGIN_ROOT}/skills/network-change-review/scripts/parse-change.sh" \
     --input "$change_path" \
     --output "${workdir}/change.json" \
     2>"${workdir}/parse.err"; then
  parse_err="$(< "${workdir}/parse.err")"
  printf '%s\n' "$parse_err" >&2
  # parse-change.sh emits ncr-* exit codes directly; propagate.
  # Determine exit code from parse.err content; default to 3.
  if grep -q "ncr-targets-unresolvable" "${workdir}/parse.err" 2>/dev/null; then exit 3; fi
  exit 3
fi

# ── Step 10 — Derive rollback ─────────────────────────────────────────────────
step 10 "Deriving rollback plan"

rollback_confidence="high"
set +e
cat "${workdir}/change.json" \
  | bash "${PLUGIN_ROOT}/skills/network-change-review/scripts/derive-rollback.sh" \
      --output "${workdir}/rollback.txt" \
      2>"${workdir}/rollback.err"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  rollback_err="$(< "${workdir}/rollback.err")"
  printf '%s\n' "$rollback_err" >&2
  exit "$rc"
fi

if grep -q "MANUAL DERIVATION REQUIRED" "${workdir}/rollback.txt" 2>/dev/null \
   || grep -qi "Confidence: low" "${workdir}/rollback.txt" 2>/dev/null \
   || grep -q "ncr-rollback-ambiguous" "${workdir}/rollback.err" 2>/dev/null; then
  rollback_confidence="low"
  printf 'yci-ncr: rollback confidence low — warning callout will appear in artifact\n' >&2
fi

# ── Step 11 — Build blast-radius input payload ────────────────────────────────
step 11 "Building blast-radius input payload"

if [[ -n "${YCI_INVENTORY_ROOT:-}" ]] && [[ -d "${YCI_INVENTORY_ROOT}" ]]; then
  inventory_json="$(bash "${PLUGIN_ROOT}/skills/blast-radius/scripts/adapter-file.sh" \
    "${YCI_INVENTORY_ROOT}" 2>/dev/null)" || inventory_json="{}"
else
  inventory_json='{"adapter":"file","root":"","tenants":[],"services":[],"devices":[],"sites":[],"dependencies":[]}'
  printf 'yci-ncr: warning: YCI_INVENTORY_ROOT not set or missing; blast-radius confidence will be low\n' >&2
fi

python3 - "${workdir}/change.json" "$customer" \
  "${inventory_json}" "${workdir}/blast-radius-payload.json" <<'PYEOF'
import json, sys, hashlib, datetime
from datetime import timezone

change_path, customer, inv_json_str, out_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(change_path) as fh:
    change_data = json.load(fh)
inventory = json.loads(inv_json_str)
if not change_data.get("change_id"):
    raw = change_data.get("raw", "")
    cid = hashlib.sha256(raw.encode()).hexdigest()[:8]
    ts = datetime.datetime.now(timezone.utc).strftime("%Y%m%d-%H%M")
    change_data["change_id"] = f"{cid}-{ts}"
payload = {"inventory": inventory, "change": change_data, "customer": customer}
with open(out_path, "w") as fh:
    json.dump(payload, fh, indent=2)
PYEOF

# ── Step 12 — Run blast-radius reasoner ──────────────────────────────────────
step 12 "Running blast-radius reasoner"

if ! cat "${workdir}/blast-radius-payload.json" \
   | bash "${PLUGIN_ROOT}/skills/blast-radius/scripts/reason.sh" \
       > "${workdir}/blast-radius-label.json" \
       2>"${workdir}/br-reason.err"; then
  err "ncr-blast-radius-failed" \
    "Blast radius reasoner failed: $(< "${workdir}/br-reason.err")" 5
fi

# ── Step 13 — Render blast-radius markdown ────────────────────────────────────
step 13 "Rendering blast-radius markdown"

if ! cat "${workdir}/blast-radius-label.json" \
   | YCI_ACTIVE_REGIME="${YCI_ADAPTER_REGIME:-}" \
     bash "${PLUGIN_ROOT}/skills/blast-radius/scripts/render-markdown.sh" \
       > "${workdir}/blast-radius.md" \
       2>"${workdir}/br-render.err"; then
  err "ncr-blast-radius-failed" \
    "Blast radius markdown render failed: $(< "${workdir}/br-render.err")" 5
fi

# ── Step 14 — Emit change-plan slot ──────────────────────────────────────────
step 14 "Preparing change-plan section"

if [[ -n "$change_plan_path" ]]; then
  [[ -f "$change_plan_path" ]] \
    || err "ncr-adapter-template-missing" "change-plan file not found: ${change_plan_path}" 6
  cp "$change_plan_path" "${workdir}/change-plan.md"
else
  cat > "${workdir}/change-plan.md" <<'PLACEHOLDER'
> **Change Plan** — Expected to be populated by `ycc:planner` subagent. The orchestrator
> was invoked without a pre-generated plan. The SKILL.md prompt layer is responsible for
> spawning `ycc:planner` and passing `--change-plan <path>` to this orchestrator.
PLACEHOLDER
fi

# ── Step 15 — Emit diff-review slot ──────────────────────────────────────────
step 15 "Preparing diff-review section"

if [[ -n "$diff_review_path" ]]; then
  [[ -f "$diff_review_path" ]] \
    || err "ncr-adapter-template-missing" "diff-review file not found: ${diff_review_path}" 6
  cp "$diff_review_path" "${workdir}/diff-review.md"
else
  cat > "${workdir}/diff-review.md" <<'PLACEHOLDER'
> **Diff Review** — Expected to be populated by `yci:change-reviewer` subagent. The orchestrator
> was invoked without a pre-generated diff review. The SKILL.md prompt layer is responsible for
> spawning `yci:change-reviewer` and passing `--diff-review <path>` to this orchestrator.
PLACEHOLDER
fi

# ── Step 16 — Build check catalogs ───────────────────────────────────────────
step 16 "Building pre-check and post-check catalogs"

if ! bash "${PLUGIN_ROOT}/skills/network-change-review/scripts/build-check-catalogs.sh" \
     --adapter-dir "${YCI_ADAPTER_DIR}" \
     --blast-radius-label "${workdir}/blast-radius-label.json" \
     --output "${workdir}/catalog.json" \
     2>"${workdir}/catalog.err"; then
  err "ncr-adapter-unresolvable" \
    "Failed to build check catalogs: $(< "${workdir}/catalog.err")" 2
fi

# ── Step 17 — Render evidence stub ───────────────────────────────────────────
step 17 "Rendering evidence stub"

if ! bash "${PLUGIN_ROOT}/skills/network-change-review/scripts/render-evidence-stub.sh" \
     --profile "${workdir}/profile.json" \
     --change "${workdir}/change.json" \
     --blast-radius-label "${workdir}/blast-radius-label.json" \
     --rollback-confidence "${rollback_confidence}" \
     --rollback-plan-path "./rollback.txt" \
     --output "${workdir}/evidence-stub.yaml" \
     2>"${workdir}/evidence-stub.err"; then
  err "ncr-profile-load-failed" \
    "Evidence stub render failed: $(< "${workdir}/evidence-stub.err")" 2
fi

# ── Step 18 — Render the final artifact ──────────────────────────────────────
step 18 "Rendering final artifact (draft)"

# catalog.json holds both pre_check and post_check; pass it for both flags.
# render-artifact.sh's load_catalog_array() handles the combined-object shape.
set +e
bash "${PLUGIN_ROOT}/skills/network-change-review/scripts/render-artifact.sh" \
     --profile "${workdir}/profile.json" \
     --adapter-dir "${YCI_ADAPTER_DIR}" \
     --change-plan "${workdir}/change-plan.md" \
     --diff-review "${workdir}/diff-review.md" \
     --blast-radius-markdown "${workdir}/blast-radius.md" \
     --rollback "${workdir}/rollback.txt" \
     --rollback-confidence "${rollback_confidence}" \
     --pre-check-catalog "${workdir}/catalog.json" \
     --post-check-catalog "${workdir}/catalog.json" \
     --evidence-stub "${workdir}/evidence-stub.yaml" \
     --output "${workdir}/artifact-draft.md" \
     2>"${workdir}/render.err"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  render_err="$(< "${workdir}/render.err")"
  printf '%s\n' "$render_err" >&2
  exit "$rc"
fi

# ── Step 19 — Sanitize rendered artifact (post-render, pass 2) ───────────────
step 19 "Sanitizing rendered artifact (sanitizer pass 2)"

if ! YCI_DATA_ROOT="$data_root" \
   YCI_CUSTOMER="$customer" \
   bash "${PLUGIN_ROOT}/skills/_shared/telemetry-sanitizer/scripts/pre-write-artifact.sh" \
     --data-root "$data_root" \
     --output "${workdir}/artifact-sanitized.md" \
     < "${workdir}/artifact-draft.md" \
     2>"${workdir}/sanitize2.err"; then
  err "ncr-sanitizer-input-rejected" \
    "Post-render sanitizer rejected artifact: $(< "${workdir}/sanitize2.err")" 4
fi

# ── Step 20 — Belt-and-suspenders customer-isolation check ───────────────────
step 20 "Running customer-isolation check"

isolation_payload_path="${workdir}/isolation-payload.json"
python3 - "$customer" "${workdir}/artifact-sanitized.md" "$isolation_payload_path" <<'PYEOF'
import json, sys
customer, artifact_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
payload = {
    "tool_name": "Write",
    "tool_input": {"file_path": artifact_path, "content": open(artifact_path).read()},
}
with open(out_path, "w") as fh:
    json.dump(payload, fh)
PYEOF

# shellcheck source=/dev/null
source "${PLUGIN_ROOT}/skills/_shared/customer-isolation/detect.sh"

isolation_decision="$(
  YCI_ACTIVE_CUSTOMER="$customer" \
  YCI_DATA_ROOT_RESOLVED="$data_root" \
  isolation_check_payload --payload-file "$isolation_payload_path"
)"

decision_value="$(python3 -c "
import json, sys
print(json.loads(sys.argv[1]).get('decision', 'deny'))
" "$isolation_decision" 2>/dev/null || echo "deny")"

if [[ "$decision_value" == "deny" ]]; then
  rm -f "${workdir}/artifact-sanitized.md"
  err "ncr-cross-customer-leak-detected" \
    "Cross-customer identifier leak detected; artifact discarded." 7
fi

# ── Step 21 — Compute final artifact directory ────────────────────────────────
step 21 "Computing final output directory"

change_id_ts="$(python3 - "${workdir}/evidence-stub.yaml" <<'PYEOF'
import sys, re
text = open(sys.argv[1]).read()
m = re.search(r'^change_id:\s*(.+)$', text, re.MULTILINE)
print(m.group(1).strip() if m else "unknown")
PYEOF
)"

timestamp="$(date -u +%Y%m%d-%H%M%S)"

if [[ -n "$output_dir_flag" ]]; then
  output_dir="$output_dir_flag"
elif [[ -n "${YCI_OUTPUT_DIR_OVERRIDE:-}" ]]; then
  output_dir="${YCI_OUTPUT_DIR_OVERRIDE}"
else
  output_dir="${data_root}/artifacts/${customer}/network-change-review/${change_id_ts}-${timestamp}"
fi

# ── Step 22 — Write artifact and supporting files to disk ─────────────────────
step 22 "Writing artifact to disk"

mkdir -p "$output_dir"
final_artifact="${output_dir}/review.md"
cp "${workdir}/artifact-sanitized.md" "$final_artifact"

for support_file in rollback.txt catalog.json evidence-stub.yaml blast-radius-label.json; do
  [[ -f "${workdir}/${support_file}" ]] && cp "${workdir}/${support_file}" "${output_dir}/${support_file}"
done

# Print the final artifact path to stdout — exactly one line.
printf '%s\n' "$final_artifact"
