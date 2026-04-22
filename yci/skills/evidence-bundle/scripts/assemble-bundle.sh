#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd -P)}"

usage() {
    cat >&2 <<'EOF'
Usage: assemble-bundle.sh --evidence-stub <path> --manifest <path> [--profile-json <path>] [--customer <name>] [--data-root <path>] [--output-dir <path>] [--adapter <regime>]
EOF
    exit 1
}

err() {
    local id="$1"
    local msg="$2"
    local code="${3:-1}"
    printf '[%s] %s\n' "$id" "$msg" >&2
    exit "$code"
}

evidence_stub=""
manifest_path=""
profile_json_path=""
customer=""
output_dir=""
adapter_override=""
declare -a data_root_args=()
temp_profile_json=""
workdir=""

cleanup() {
    if [[ -n "${temp_profile_json}" && -f "${temp_profile_json}" ]]; then
        rm -f "${temp_profile_json}"
    fi
    if [[ -n "${workdir}" && -d "${workdir}" ]]; then
        rm -rf "${workdir}"
    fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --evidence-stub) evidence_stub="${2:-}"; shift 2 ;;
        --manifest) manifest_path="${2:-}"; shift 2 ;;
        --profile-json) profile_json_path="${2:-}"; shift 2 ;;
        --customer) customer="${2:-}"; shift 2 ;;
        --data-root) data_root_args=(--data-root "${2:-}"); shift 2 ;;
        --output-dir) output_dir="${2:-}"; shift 2 ;;
        --adapter) adapter_override="${2:-}"; shift 2 ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
done

[[ -n "${evidence_stub}" && -n "${manifest_path}" ]] || usage
[[ -f "${evidence_stub}" ]] || err "eb-manifest-invalid" "Evidence stub not found: ${evidence_stub}" 3
[[ -f "${manifest_path}" ]] || err "eb-manifest-invalid" "Manifest not found: ${manifest_path}" 3

resolved_data_root="$("${PLUGIN_ROOT}/skills/_shared/scripts/resolve-data-root.sh" "${data_root_args[@]}")"

if [[ -z "${profile_json_path}" ]]; then
    if [[ -z "${customer}" ]]; then
        customer="$("${PLUGIN_ROOT}/skills/customer-profile/scripts/resolve-customer.sh" "${data_root_args[@]}")" || \
            err "eb-profile-load-failed" "Could not resolve active customer" 2
    fi
    temp_profile_json="$(mktemp)"
    profile_json_path="${temp_profile_json}"
    "${PLUGIN_ROOT}/skills/customer-profile/scripts/load-profile.sh" "${resolved_data_root}" "${customer}" > "${profile_json_path}" || \
        err "eb-profile-load-failed" "Could not load profile for customer ${customer}" 2
fi

profile_json_path="$(cd "$(dirname "${profile_json_path}")" && pwd -P)/$(basename "${profile_json_path}")"

adapter_export_args=(--export --profile-json-path "${profile_json_path}")
if [[ -n "${adapter_override}" ]]; then
    adapter_export_args+=(--regime "${adapter_override}")
fi
eval "$("${PLUGIN_ROOT}/skills/_shared/scripts/load-compliance-adapter.sh" "${adapter_export_args[@]}")" || \
    err "eb-adapter-invalid" "Could not resolve compliance adapter" 4

workdir="$(mktemp -d)"
bundle_json="${workdir}/bundle.json"
manifest_json="${workdir}/manifest.json"

python3 - "${evidence_stub}" "${manifest_path}" "${profile_json_path}" "${bundle_json}" "${manifest_json}" "${YCI_ADAPTER_REGIME}" <<'PY'
import json
import os
import sys
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError as exc:
    raise SystemExit(f"pyyaml required: {exc}")

stub_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
profile_path = Path(sys.argv[3])
bundle_path = Path(sys.argv[4])
manifest_json_path = Path(sys.argv[5])
adapter_regime = sys.argv[6]


def load_structured(path: Path):
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".json":
        return json.loads(text)
    return yaml.safe_load(text)


stub = load_structured(stub_path) or {}
manifest = load_structured(manifest_path) or {}
profile = json.loads(profile_path.read_text(encoding="utf-8"))

if not isinstance(stub, dict) or not isinstance(manifest, dict) or not isinstance(profile, dict):
    raise SystemExit("stub, manifest, and profile must be mappings")

rollback_plan = manifest.get("rollback_plan", "")
rollback_rel = stub.get("rollback_plan_path", "")
if rollback_rel:
    rollback_candidate = (stub_path.parent / rollback_rel).resolve()
    if rollback_candidate.exists():
        rollback_plan = rollback_candidate.read_text(encoding="utf-8").strip()

tenant_scope = manifest.get("tenant_scope") or []
if isinstance(tenant_scope, str):
    tenant_scope = [tenant_scope]

approvals = manifest.get("approvals") or []
pre_state = manifest.get("pre_state") or []
post_state = manifest.get("post_state") or []

bundle = dict(stub)
bundle["rollback_plan"] = rollback_plan
bundle["pre_check_artifacts"] = stub.get("pre_check_artifacts") or pre_state
bundle["post_check_artifacts"] = stub.get("post_check_artifacts") or post_state
bundle["approvals"] = approvals
bundle["operator_identity"] = manifest.get("operator_identity", "")
bundle["tenant_scope"] = tenant_scope
bundle["tenant_scope_summary"] = ", ".join(tenant_scope)
bundle["customer_id"] = profile.get("customer", {}).get("id", stub.get("customer_id", ""))
bundle["engagement_id"] = profile.get("engagement", {}).get("id", "")
bundle["git_commit_range"] = manifest.get("git", {}).get("commit_range", "")
bundle["diff_path"] = manifest.get("git", {}).get("diff_path", "")
bundle["generated_at"] = manifest.get("timestamps", {}).get("generated_at", stub.get("timestamp_utc", ""))
bundle["executed_at"] = manifest.get("timestamps", {}).get("executed_at", stub.get("timestamp_utc", ""))
bundle["compliance_regime"] = adapter_regime
bundle["signature_method"] = profile.get("compliance", {}).get("signing", {}).get("method", "")
bundle["signature_key_ref"] = profile.get("compliance", {}).get("signing", {}).get("key_ref", "")
bundle["signature_identity"] = profile.get("compliance", {}).get("signing", {}).get("identity", "")
bundle["signature_pubkey"] = profile.get("compliance", {}).get("signing", {}).get("pubkey", "")

diff_path = bundle["diff_path"]
if diff_path:
    diff_candidate = Path(diff_path)
    if not diff_candidate.is_absolute():
        diff_candidate = (manifest_path.parent / diff_candidate).resolve()
    if diff_candidate.exists():
        bundle["diff_excerpt"] = diff_candidate.read_text(encoding="utf-8").strip()[:4000]
        bundle["diff_path"] = str(diff_candidate)

if adapter_regime == "hipaa":
    bundle["baa_reference"] = profile.get("compliance", {}).get("baa_reference") or \
        manifest.get("hipaa", {}).get("baa_reference_override", "")
    bundle["phi_redaction_status"] = "applied"
elif adapter_regime == "pci":
    bundle["cde_boundary_attestation"] = manifest.get("pci", {}).get("cde_boundary_attestation", "")
    bundle["pan_redaction_status"] = "applied"
elif adapter_regime == "soc2":
    bundle["control_mappings"] = manifest.get("soc2", {}).get("control_mappings") or []

bundle_path.write_text(json.dumps(bundle, indent=2, sort_keys=True), encoding="utf-8")
manifest_json_path.write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
PY

schema_args=()
template_path="${YCI_ADAPTER_DIR}/evidence-template.md"
if [[ -f "${YCI_ADAPTER_DIR}/evidence-schema.json" ]]; then
    schema_args=(--schema "${YCI_ADAPTER_DIR}/evidence-schema.json")
fi

python3 "${SCRIPT_DIR}/validate-bundle.py" \
    --bundle-json "${bundle_json}" \
    "${schema_args[@]}" || err "eb-validation-failed" "Bundle validation failed" 5

mapfile -t bundle_meta < <(
    python3 - "${bundle_json}" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1], encoding="utf-8"))
timestamp = payload.get(
    "timestamp_utc",
    payload.get("timestamp", payload.get("created_at", "")),
)
timestamp_text = str(timestamp) if timestamp is not None else ""
timestamp_slug = ""
if timestamp_text:
    timestamp_slug = (
        timestamp_text.replace(":", "")
        .replace("-", "")
        .replace("T", "-")
        .replace("Z", "")
    )
print(payload["change_id"])
print(timestamp_slug)
print(payload["customer_id"])
PY
)
change_id="${bundle_meta[0]:-}"
timestamp_slug="${bundle_meta[1]:-}"
customer_id="${bundle_meta[2]:-}"

if [[ -z "${change_id}" || -z "${customer_id}" ]]; then
    printf '[eb-validation-failed] Missing bundle metadata for output path (change_id=%s customer_id=%s timestamp_slug=%s)\n' \
        "${change_id:-}" "${customer_id:-}" "${timestamp_slug:-}" >&2
    exit 5
fi

if [[ -z "${output_dir}" ]]; then
    output_dir="${resolved_data_root}/artifacts/${customer_id}/evidence-bundle/${change_id}-${timestamp_slug}"
fi
mkdir -p "${output_dir}"

rendered_path="${output_dir}/evidence.md"
python3 "${SCRIPT_DIR}/render-bundle.py" \
    --bundle-json "${bundle_json}" \
    --template "${template_path}" \
    --output "${rendered_path}" || err "eb-render-failed" "Template rendering failed" 6

cp "${bundle_json}" "${output_dir}/bundle.json"
cp "${manifest_json}" "${output_dir}/manifest.json"

python3 - "${profile_json_path}" <<'PY' > "${workdir}/signing.json"
import json
import sys
profile = json.load(open(sys.argv[1]))
print(json.dumps(profile.get("compliance", {}).get("signing") or {}, indent=2, sort_keys=True))
PY

"${SCRIPT_DIR}/sign-bundle.sh" \
    --artifact "${rendered_path}" \
    --signing-json "${workdir}/signing.json" \
    --output "${output_dir}/evidence.md.sig" \
    --metadata "${output_dir}/signature.json" || err "eb-signing-failed" "Signing failed" 8

printf '%s\n' "${rendered_path}"
