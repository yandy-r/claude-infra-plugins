#!/usr/bin/env bash
# generate-mop.sh — yci:mop top-level orchestrator.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd -P)}"
TOTAL_STEPS=17

step() { printf 'yci-mop: [step %s/%s] %s\n' "$1" "$TOTAL_STEPS" "$2" >&2; }

err() {
  local id="$1"
  local msg="$2"
  local code="${3:-2}"
  printf '[%s] %s\n' "$id" "$msg" >&2
  exit "$code"
}

usage() {
  cat >&2 <<'EOF'
Usage: generate-mop.sh --change <path> [OPTIONS]

Options:
  --data-root <path>   Override data root
  --customer <name>    Override active customer
  --adapter <regime>   Compliance adapter override
  --format <format>    Output format (markdown only in V1)
  --output-dir <path>  Override final artifact directory
  -h, --help           Show this help and exit 0
EOF
}

change_path=""
data_root_flag=""
customer_flag=""
adapter_flag=""
format_flag=""
output_dir_flag=""

step 1 "Parsing flags and validating required inputs"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --change)     change_path="${2:?--change requires a path}"; shift 2 ;;
    --data-root)  data_root_flag="${2:?--data-root requires a path}"; shift 2 ;;
    --customer)   customer_flag="${2:?--customer requires a value}"; shift 2 ;;
    --adapter)    adapter_flag="${2:?--adapter requires a value}"; shift 2 ;;
    --format)     format_flag="${2:?--format requires a value}"; shift 2 ;;
    --output-dir) output_dir_flag="${2:?--output-dir requires a path}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$change_path" && "$1" != -* ]]; then
        change_path="$1"
        shift
      else
        usage
        err "mop-change-unsupported" "Unknown flag: $1" 3
      fi
      ;;
  esac
done

[[ -n "$change_path" ]] || err "mop-change-missing" "--change is required." 3
[[ -f "$change_path" ]] || err "mop-change-missing" "Change file not found: ${change_path}" 3
[[ -r "$change_path" ]] || err "mop-change-missing" "Change file not readable: ${change_path}" 3
change_path="$(cd "$(dirname "$change_path")" && pwd -P)/$(basename "$change_path")"

step 2 "Creating temporary working directory"
workdir="$(mktemp -d -t yci-mop-XXXX)"
cleanup() {
  if [[ "${YCI_KEEP_WORKDIR:-0}" == "1" ]]; then
    printf 'yci-mop: keeping workdir for debug: %s\n' "$workdir" >&2
  else
    rm -rf "$workdir"
  fi
}
trap cleanup EXIT

step 3 "Resolving data root"
# shellcheck source=/dev/null
source "${PLUGIN_ROOT}/skills/_shared/scripts/resolve-data-root.sh"
if [[ -n "$data_root_flag" ]]; then
  data_root="$(yci_resolve_data_root --data-root "$data_root_flag")"
else
  data_root="$(yci_resolve_data_root)"
fi
export YCI_DATA_ROOT_RESOLVED="$data_root"

step 4 "Resolving active customer"
customer_err="${workdir}/resolve-customer.err"
if [[ -n "$customer_flag" ]]; then
  customer="$(YCI_CUSTOMER="$customer_flag" bash "${PLUGIN_ROOT}/skills/customer-profile/scripts/resolve-customer.sh" \
    --data-root "$data_root" 2>"$customer_err")" || {
      customer_detail="$(< "$customer_err")"
      if [[ -n "$customer_detail" ]]; then
        err "mop-change-malformed" "Invalid or unresolved customer override: ${customer_detail}" 2
      fi
      err "mop-change-malformed" "Invalid or unresolved customer override." 2
    }
else
  customer="$(bash "${PLUGIN_ROOT}/skills/customer-profile/scripts/resolve-customer.sh" \
    --data-root "$data_root" 2>"$customer_err")" || {
      customer_detail="$(< "$customer_err")"
      if [[ -n "$customer_detail" ]]; then
        err "mop-change-malformed" "No active customer. Run /yci:switch <customer> first. ${customer_detail}" 2
      fi
      err "mop-change-malformed" "No active customer. Run /yci:switch <customer> first." 2
    }
fi
export YCI_ACTIVE_CUSTOMER="$customer"

step 5 "Loading customer profile"
bash "${PLUGIN_ROOT}/skills/customer-profile/scripts/load-profile.sh" \
  "$data_root" "$customer" > "${workdir}/profile.json" 2>"${workdir}/profile.err" \
  || err "mop-change-malformed" "Failed to load profile: $(< "${workdir}/profile.err")" 2

step 6 "Resolving output format and compliance adapter"
header_template_raw="$(python3 - "${workdir}/profile.json" <<'PYEOF'
import json, sys
p = json.load(open(sys.argv[1]))
print(p.get("deliverable", {}).get("header_template", ""))
PYEOF
)"
if [[ -n "$header_template_raw" ]] && [[ "$header_template_raw" == */* || "$header_template_raw" == *.md ]]; then
  if [[ "$header_template_raw" == */* || "$header_template_raw" == *\\* || "$header_template_raw" == *".."* ]]; then
    err "mop-change-malformed" "Profile deliverable.header_template must be a simple filename under profiles/: ${header_template_raw}" 2
  fi
  profiles_root="$(cd "${data_root}/profiles" && pwd -P)" \
    || err "mop-change-malformed" "Profiles directory not found: ${data_root}/profiles" 2
  template_basename="$header_template_raw"
  source_path="${profiles_root}/${template_basename}"
  if [[ ! -f "$source_path" ]]; then
    err "mop-change-malformed" "Header template not found under profiles/: ${header_template_raw}" 2
  fi
  cp "$source_path" "${workdir}/${template_basename}"
  python3 - "${workdir}/profile.json" "$template_basename" <<'PYEOF'
import json, sys
path, basename = sys.argv[1], sys.argv[2]
data = json.load(open(path))
data.setdefault("deliverable", {})["header_template"] = basename
json.dump(data, open(path, "w"), indent=2)
PYEOF
fi

profile_formats="$(python3 - "${workdir}/profile.json" <<'PYEOF'
import json, sys
p = json.load(open(sys.argv[1]))
fmt = p.get("deliverable", {}).get("format", [])
if isinstance(fmt, list):
    print(",".join(str(x) for x in fmt))
else:
    print(str(fmt))
PYEOF
)"
requested_format="${format_flag:-markdown}"
if [[ "$requested_format" != "markdown" ]]; then
  err "mop-format-unsupported" "Only markdown output is supported in V1." 2
fi
if [[ ",${profile_formats}," != *",markdown,"* ]]; then
  err "mop-format-unsupported" "Profile deliverable.format does not include markdown." 2
fi

if [[ -n "$adapter_flag" ]]; then
  adapter_args=("--regime" "$adapter_flag")
else
  adapter_args=("--profile-json-path" "${workdir}/profile.json")
fi
adapter_env="${workdir}/adapter.env"
bash "${PLUGIN_ROOT}/skills/_shared/scripts/load-compliance-adapter.sh" \
  --export-file "$adapter_env" \
  "${adapter_args[@]}" 2>"${workdir}/adapter.err" \
  || err "mop-change-malformed" "Failed to resolve compliance adapter: $(< "${workdir}/adapter.err")" 2
# shellcheck source=/dev/null
source "$adapter_env"
export YCI_ADAPTER_DIR YCI_ADAPTER_REGIME YCI_ADAPTER_HAS_SCHEMA
export YCI_ACTIVE_REGIME="${YCI_ADAPTER_REGIME:-}"

step 7 "Preflight: scanning input for foreign-customer identifiers"
preflight_exit=0
bash "${PLUGIN_ROOT}/skills/network-change-review/scripts/preflight-cross-customer.sh" \
  --data-root "$data_root" \
  --customer "$customer" \
  --change "$change_path" \
  > "${workdir}/preflight.out" 2>"${workdir}/preflight.err" || preflight_exit=$?
if [[ $preflight_exit -eq 7 ]]; then
  err "mop-cross-customer-leak-detected" "$( < "${workdir}/preflight.err" )" 7
elif [[ $preflight_exit -ne 0 ]]; then
  err "mop-change-malformed" "Preflight failed: $(< "${workdir}/preflight.err")" 2
fi

step 8 "Normalizing change input"
bash "${PLUGIN_ROOT}/skills/mop/scripts/normalize-change.sh" \
  --input "$change_path" \
  --output "${workdir}/change.json" \
  2>"${workdir}/normalize.err" || err "mop-change-malformed" "$( < "${workdir}/normalize.err" )" 3

step 9 "Deriving rollback plan"
rollback_confidence="high"
set +e
bash "${PLUGIN_ROOT}/skills/_shared/scripts/derive-change-rollback.sh" \
  --output "${workdir}/rollback.txt" \
  < "${workdir}/change.json" \
  2>"${workdir}/rollback.err"
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
  printf '%s\n' "$( < "${workdir}/rollback.err" )" >&2
  exit "$rc"
fi
if grep -q "ncr-rollback-ambiguous" "${workdir}/rollback.err" 2>/dev/null; then
  rollback_confidence="low"
fi

step 10 "Building blast-radius payload"
inventory_root_rel="$(python3 - "${workdir}/profile.json" <<'PYEOF'
import json, sys
p = json.load(open(sys.argv[1]))
print(p.get("inventory", {}).get("root", ""))
PYEOF
)"
if [[ -n "$inventory_root_rel" ]]; then
  if [[ "$inventory_root_rel" == *".."* ]] || [[ "$inventory_root_rel" == *\\* ]]; then
    err "mop-change-malformed" "Profile inventory.root must not contain path traversal: ${inventory_root_rel}" 2
  fi
  profiles_dir="${data_root}/profiles"
  if [[ "${inventory_root_rel}" = /* ]]; then
    export YCI_INVENTORY_ROOT="$inventory_root_rel"
  elif [[ -d "${profiles_dir}/${inventory_root_rel}" ]]; then
    export YCI_INVENTORY_ROOT="${profiles_dir}/${inventory_root_rel}"
  else
    export YCI_INVENTORY_ROOT="${data_root}/${inventory_root_rel}"
  fi
else
  export YCI_INVENTORY_ROOT=""
fi

if [[ -n "${YCI_INVENTORY_ROOT:-}" ]] && [[ -d "${YCI_INVENTORY_ROOT}" ]]; then
  inventory_json="$(bash "${PLUGIN_ROOT}/skills/blast-radius/scripts/adapter-file.sh" \
    "${YCI_INVENTORY_ROOT}" 2>/dev/null)" || inventory_json='{}'
else
  inventory_json='{"adapter":"file","root":"","tenants":[],"services":[],"devices":[],"sites":[],"dependencies":[]}'
fi

python3 - "${workdir}/change.json" "$customer" "${inventory_json}" "${workdir}/blast-radius-payload.json" <<'PYEOF'
import json, sys
change_path, customer, inv_json, out_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
payload = {
    "inventory": json.loads(inv_json),
    "change": json.load(open(change_path)),
    "customer": customer,
}
json.dump(payload, open(out_path, "w"), indent=2)
PYEOF

step 11 "Running blast-radius reasoner"
bash "${PLUGIN_ROOT}/skills/blast-radius/scripts/reason.sh" \
  < "${workdir}/blast-radius-payload.json" \
  > "${workdir}/blast-radius-label.json" \
  2>"${workdir}/reason.err" || err "mop-change-malformed" "Blast-radius reasoner failed: $(< "${workdir}/reason.err")" 5

step 12 "Rendering blast-radius markdown"
cat "${workdir}/blast-radius-label.json" \
  | YCI_ACTIVE_REGIME="${YCI_ADAPTER_REGIME:-}" \
    bash "${PLUGIN_ROOT}/skills/blast-radius/scripts/render-markdown.sh" \
      > "${workdir}/blast-radius.md" \
      2>"${workdir}/br-render.err" || err "mop-change-malformed" "Blast-radius render failed: $(< "${workdir}/br-render.err")" 5

step 13 "Building pre/post check catalogs"
bash "${PLUGIN_ROOT}/skills/network-change-review/scripts/build-check-catalogs.sh" \
  --adapter-dir "${YCI_ADAPTER_DIR}" \
  --blast-radius-label "${workdir}/blast-radius-label.json" \
  --output "${workdir}/catalog.json" \
  2>"${workdir}/catalog.err" || err "mop-change-malformed" "Failed to build check catalogs: $(< "${workdir}/catalog.err")" 2

step 14 "Rendering draft MOP artifact"
bash "${PLUGIN_ROOT}/skills/mop/scripts/render-artifact.sh" \
  --profile "${workdir}/profile.json" \
  --change-json "${workdir}/change.json" \
  --compliance-regime "${YCI_ADAPTER_REGIME:-}" \
  --blast-radius-markdown "${workdir}/blast-radius.md" \
  --rollback "${workdir}/rollback.txt" \
  --rollback-confidence "${rollback_confidence}" \
  --catalog "${workdir}/catalog.json" \
  --output "${workdir}/mop-draft.md" \
  2>"${workdir}/render.err" || err "mop-render-failed" "$( < "${workdir}/render.err" )" 6

step 15 "Sanitizing rendered artifact"
YCI_DATA_ROOT="$data_root" \
YCI_CUSTOMER="$customer" \
bash "${PLUGIN_ROOT}/skills/_shared/telemetry-sanitizer/scripts/pre-write-artifact.sh" \
  --data-root "$data_root" \
  --output "${workdir}/mop-sanitized.md" \
  < "${workdir}/mop-draft.md" \
  2>"${workdir}/sanitize.err" || err "mop-cross-customer-leak-detected" "Sanitizer rejected artifact: $(< "${workdir}/sanitize.err")" 4

step 16 "Running customer-isolation check"
python3 - "$customer" "${workdir}/mop-sanitized.md" "${workdir}/isolation-payload.json" <<'PYEOF'
import json, sys
customer, artifact_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
payload = {
    "tool_name": "Write",
    "tool_input": {"file_path": artifact_path, "content": open(artifact_path).read()},
}
json.dump(payload, open(out_path, "w"))
PYEOF
# shellcheck source=/dev/null
export YCI_ROOT="${PLUGIN_ROOT}"
source "${PLUGIN_ROOT}/skills/_shared/customer-isolation/detect.sh"
isolation_decision="$(
  YCI_ACTIVE_CUSTOMER="$customer" \
  YCI_DATA_ROOT_RESOLVED="$data_root" \
  isolation_check_payload --payload-file "${workdir}/isolation-payload.json"
)"
decision_value="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("decision","deny"))' "$isolation_decision" 2>/dev/null || echo deny)"
if [[ "$decision_value" == "deny" ]]; then
  err "mop-cross-customer-leak-detected" "Cross-customer identifier leak detected; artifact discarded." 7
fi

step 17 "Writing artifact to disk"
change_id="$(python3 - "${workdir}/change.json" <<'PYEOF'
import json, re, sys
doc = json.load(open(sys.argv[1]))
raw = doc.get("change_id", "unknown")
if raw is None:
    raw = "unknown"
token = re.sub(r"[^A-Za-z0-9._-]+", "", str(raw))
if not token:
    token = "unknown"
print(token)
PYEOF
)"
packaged_input_name="$(python3 - "${workdir}/change.json" <<'PYEOF'
import json, os, re, sys

DEFAULT = "reviewed-input"
doc = json.load(open(sys.argv[1]))
meta = doc.get("metadata") or {}
raw = meta.get("artifact_input_filename", DEFAULT)
if raw is None or str(raw).strip() == "":
    print(DEFAULT)
elif ".." in str(raw) or str(raw).startswith("/"):
    print(DEFAULT)
else:
    base = os.path.basename(str(raw).replace("\\", "/"))
    if not base or not re.fullmatch(r"[A-Za-z0-9._-]+", base):
        print(DEFAULT)
    else:
        print(base)
PYEOF
)"
timestamp="$(date -u +%Y%m%d-%H%M%S)"
deliverable_base="$(python3 - "${workdir}/profile.json" <<'PYEOF'
import json, sys
p = json.load(open(sys.argv[1]))
print(p.get("deliverable", {}).get("path", ""))
PYEOF
)"

# shellcheck source=/dev/null
source "${PLUGIN_ROOT}/skills/_shared/customer-isolation/scripts/path-match.sh"
data_root_canon="$(path_canonicalize "$data_root")"
[[ -n "$data_root_canon" ]] || err "mop-change-malformed" "Cannot canonicalize data root: ${data_root}" 2

if [[ -n "$output_dir_flag" ]]; then
  output_dir="$(path_canonicalize "$output_dir_flag")"
  [[ -n "$output_dir" ]] || err "mop-change-malformed" "Cannot canonicalize --output-dir: ${output_dir_flag}" 2
elif [[ -n "$deliverable_base" ]]; then
  if [[ "$deliverable_base" = /* ]]; then
    candidate="${deliverable_base}/mop/${change_id}-${timestamp}"
  else
    candidate="${data_root_canon}/${deliverable_base}/mop/${change_id}-${timestamp}"
  fi
  output_dir="$(path_canonicalize "$candidate")"
  [[ -n "$output_dir" ]] || err "mop-change-malformed" "Cannot canonicalize MOP output path (deliverable.path)." 2
  path_is_under "$output_dir" "$data_root" || err "mop-change-malformed" "MOP output directory escapes data root (deliverable.path): ${output_dir}" 2
else
  candidate="${data_root_canon}/artifacts/${customer}/mop/${change_id}-${timestamp}"
  output_dir="$(path_canonicalize "$candidate")"
  [[ -n "$output_dir" ]] || err "mop-change-malformed" "Cannot canonicalize MOP output path." 2
  path_is_under "$output_dir" "$data_root" || err "mop-change-malformed" "MOP output directory escapes data root: ${output_dir}" 2
fi

mkdir -p "$output_dir"
cp "${workdir}/mop-sanitized.md" "${output_dir}/mop.md"
cp "$change_path" "${output_dir}/${packaged_input_name}"
for support_file in change.json rollback.txt blast-radius-label.json catalog.json; do
  cp "${workdir}/${support_file}" "${output_dir}/${support_file}"
done

final_artifact="$(path_canonicalize "${output_dir}/mop.md")"
[[ -n "$final_artifact" ]] || err "mop-change-malformed" "Cannot canonicalize final artifact path." 2
[[ -f "$final_artifact" ]] || err "mop-change-malformed" "Final artifact missing after write: ${output_dir}/mop.md" 2

printf '%s\n' "$final_artifact"
