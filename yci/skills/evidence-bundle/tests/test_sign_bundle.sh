#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SIGNER="${SCRIPTS_DIR}/sign-bundle.sh"

test_minisign_path() {
    local sb rc
    sb="$(mktemp -d)"
    trap 'rm -rf "${sb}"' RETURN
    printf 'hello\n' > "${sb}/artifact.md"
    printf '{}' > "${sb}/key"
    cat > "${sb}/signing.json" <<EOF
{"method":"minisign","key_ref":"${sb}/key","pubkey":"PUB"}
EOF

    PATH="${FIXTURES_DIR}/bin:${PATH}" "${SIGNER}" \
        --artifact "${sb}/artifact.md" \
        --signing-json "${sb}/signing.json" \
        --output "${sb}/artifact.md.sig" \
        --metadata "${sb}/signature.json"
    rc=$?
    assert_exit 0 "${rc}" "sign_bundle: minisign exits 0"
    assert_file_exists "${sb}/artifact.md.sig" "sign_bundle: minisign signature exists"
    assert_file_exists "${sb}/signature.json" "sign_bundle: minisign metadata exists"
}

test_ssh_path() {
    local sb rc
    sb="$(mktemp -d)"
    trap 'rm -rf "${sb}"' RETURN
    printf 'hello\n' > "${sb}/artifact.md"
    printf '{}' > "${sb}/key"
    cat > "${sb}/signing.json" <<EOF
{"method":"ssh-keygen-y-sign","key_ref":"${sb}/key","identity":"ops@example.com","pubkey":"SSH-PUB"}
EOF

    PATH="${FIXTURES_DIR}/bin:${PATH}" "${SIGNER}" \
        --artifact "${sb}/artifact.md" \
        --signing-json "${sb}/signing.json" \
        --output "${sb}/artifact.md.sig" \
        --metadata "${sb}/signature.json"
    rc=$?
    assert_exit 0 "${rc}" "sign_bundle: ssh exits 0"
    assert_file_exists "${sb}/artifact.md.sig" "sign_bundle: ssh signature exists"
    assert_file_exists "${sb}/signature.json" "sign_bundle: ssh metadata exists"
}

test_minisign_path
test_ssh_path
yci_test_summary
