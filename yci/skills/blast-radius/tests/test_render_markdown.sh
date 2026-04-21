#!/usr/bin/env bash
# yci blast-radius — render-markdown.sh tests

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/helpers.sh"

RENDER="${YCI_SCRIPTS_DIR}/render-markdown.sh"
LABEL_SIMPLE="${FIXTURES_DIR}/expected-label-simple.json"
LABEL_UNKNOWN="${FIXTURES_DIR}/expected-label-unknown.json"

# --- no regime: sections present, no HIPAA/PCI -----------------------------
unset YCI_ACTIVE_REGIME
out="$(<"$LABEL_SIMPLE" "$RENDER")"
rc=$?
assert_exit 0 "$rc" "render exits 0 on valid label"
assert_contains "$out" "# Blast radius" "H1 header present"
assert_contains "$out" "widget-corp" "customer in header"
assert_contains "$out" "WIDGET-CR-2026-0421-A" "change_id in header"
assert_contains "$out" "## TL;DR" "TL;DR section present"
assert_contains "$out" "Confidence" "confidence line present"
assert_contains "$out" "## Direct devices" "direct devices section"
assert_contains "$out" "dc1-edge-01" "direct device rendered"
assert_contains "$out" "edge-router" "device role rendered"
assert_contains "$out" "## Services affected" "services section"
assert_contains "$out" "orders-api" "service rendered"
assert_contains "$out" "tier-1" "service criticality rendered"
assert_contains "$out" "## Downstream consumers" "downstream section"
assert_not_contains "$out" "## HIPAA" "no HIPAA section without regime"
assert_not_contains "$out" "## PCI" "no PCI section without regime"
assert_not_contains "$out" "## Coverage gaps" "no coverage gaps section (no gaps)"

# --- hipaa regime sets section ---------------------------------------------
out="$(YCI_ACTIVE_REGIME=hipaa "$RENDER" < "$LABEL_SIMPLE")"
assert_contains "$out" "## HIPAA" "HIPAA section appears with regime"
assert_contains "$out" "BAA" "HIPAA section mentions BAA"

# --- pci regime sets section -----------------------------------------------
out="$(YCI_ACTIVE_REGIME=pci "$RENDER" < "$LABEL_SIMPLE")"
assert_contains "$out" "## PCI" "PCI section appears with regime"
assert_contains "$out" "CDE" "PCI section mentions CDE"

# --- commercial / none omit the section ------------------------------------
out="$(YCI_ACTIVE_REGIME=none "$RENDER" < "$LABEL_SIMPLE")"
assert_not_contains "$out" "## HIPAA" "regime=none omits HIPAA"
assert_not_contains "$out" "## PCI" "regime=none omits PCI"

# --- coverage gaps render when non-empty -----------------------------------
out="$("$RENDER" < "$LABEL_UNKNOWN")"
assert_contains "$out" "## Coverage gaps" "coverage gaps section rendered"
assert_contains "$out" "unknown-device" "unknown-device gap rendered"
assert_contains "$out" "Warning" "coverage-gaps warning present"

# --- unsupported schema version --------------------------------------------
bad="$(python3 -c '
import json
d = json.load(open("'"$LABEL_SIMPLE"'"))
d["schema_version"] = 2
print(json.dumps(d))
')"
out="$(printf '%s' "$bad" | "$RENDER" 2>&1 >/dev/null)"
rc=$?
assert_exit 2 "$rc" "render exits 2 on schema_version != 1"
assert_contains "$out" "render-unsupported-version" "unsupported-version error id surfaced"

# --- empty stdin -----------------------------------------------------------
out="$(printf '' | "$RENDER" 2>&1 >/dev/null)"
rc=$?
assert_exit 1 "$rc" "render exits 1 on empty stdin"
assert_contains "$out" "render-missing-stdin" "missing-stdin error id surfaced"

yci_test_summary
