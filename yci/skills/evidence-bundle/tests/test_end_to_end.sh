#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ASSEMBLER="${SCRIPTS_DIR}/assemble-bundle.sh"
LOAD_PROFILE="${PLUGIN_ROOT}/skills/customer-profile/scripts/load-profile.sh"

make_profile_root() {
    local fixture="$1" out_root="$2" key_ref="$3"
    mkdir -p "${out_root}/profiles"
    python3 - "${fixture}" "${out_root}/profiles/test.yaml" "${key_ref}" <<'PY'
import sys
import yaml

src = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
src["compliance"]["signing"]["key_ref"] = sys.argv[3]
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    yaml.safe_dump(src, fh, sort_keys=False)
PY
}

run_case() {
    local regime="$1" fixture="$2" manifest="$3" stub="$4" signer="$5"
    local sb out profile_json bundle_json rendered
    sb="$(mktemp -d)"
    trap 'rm -rf "${sb}"' RETURN

    printf 'fake-key\n' > "${sb}/signing.key"
    make_profile_root "${fixture}" "${sb}/data-root" "${sb}/signing.key"
    profile_json="${sb}/profile.json"
    "${LOAD_PROFILE}" "${sb}/data-root" test > "${profile_json}"

    PATH="${FIXTURES_DIR}/bin:${PATH}" \
    rendered="$("${ASSEMBLER}" \
        --evidence-stub "${stub}" \
        --manifest "${manifest}" \
        --profile-json "${profile_json}" \
        --output-dir "${sb}/output")"

    assert_file_exists "${rendered}" "e2e_${regime}: rendered evidence exists"
    assert_file_exists "${sb}/output/evidence.md.sig" "e2e_${regime}: signature exists"
    assert_file_exists "${sb}/output/bundle.json" "e2e_${regime}: bundle json exists"
    bundle_json="$(cat "${sb}/output/bundle.json")"
    case "${regime}" in
        commercial)
            assert_contains "${bundle_json}" "\"git_commit_range\"" "e2e_commercial: includes commit range"
            ;;
        hipaa)
            assert_contains "${bundle_json}" "\"baa_reference\"" "e2e_hipaa: includes baa reference"
            ;;
        pci)
            assert_contains "${bundle_json}" "\"cde_boundary_attestation\"" "e2e_pci: includes cde attestation"
            ;;
        soc2)
            assert_contains "${bundle_json}" "\"control_mappings\"" "e2e_soc2: includes control mappings"
            ;;
    esac
}

run_case commercial "${FIXTURES_DIR}/profiles/commercial.yaml" "${FIXTURES_DIR}/manifests/commercial.yaml" "${FIXTURES_DIR}/stubs/commercial.yaml" minisign
run_case hipaa "${FIXTURES_DIR}/profiles/hipaa.yaml" "${FIXTURES_DIR}/manifests/hipaa.yaml" "${FIXTURES_DIR}/stubs/hipaa.yaml" ssh-keygen
run_case pci "${FIXTURES_DIR}/profiles/pci.yaml" "${FIXTURES_DIR}/manifests/pci.yaml" "${FIXTURES_DIR}/stubs/pci.yaml" minisign
run_case soc2 "${FIXTURES_DIR}/profiles/soc2.yaml" "${FIXTURES_DIR}/manifests/soc2.yaml" "${FIXTURES_DIR}/stubs/soc2.yaml" ssh-keygen
yci_test_summary
