#!/usr/bin/env bash
# yci compliance-adapter contract constants.
#
# Sourceable library — DO NOT set -euo pipefail at file scope.
# Read by:
#   - yci/skills/_shared/scripts/load-compliance-adapter.sh   (runtime loader)
#   - scripts/validate-yci-skills.sh                          (structural validator)
#
# The contract itself is documented in yci/CONTRIBUTING.md § "What Every Adapter Should Ship".
# This file is the machine-readable mirror of that prose contract — keep them in sync.
#
# Contract summary (see CONTRIBUTING.md for the full prose):
#
#   - Every adapter ships ADAPTER.md (the single hard requirement).
#   - Every shipped adapter additionally ships evidence-template.md and
#     handoff-checklist.md.
#   - Non-exempt shipped adapters ALSO ship evidence-schema.json and at least one
#     *-redaction.rules file consumed by the telemetry-sanitizer (see
#     yci/skills/_shared/telemetry-sanitizer/scripts/load_adapter_rules.py for the
#     discovery glob and NAME:/RE: format).
#   - The only current schema/redaction-exempt regime is "none".

# shellcheck disable=SC2034
# The arrays below are read by callers after sourcing; shellcheck cannot see
# across the source boundary so it flags them as unused inside this file.

# Files every adapter directory MUST ship. The single hard requirement.
YCI_ADAPTER_REQUIRED_FILES=(
  ADAPTER.md
)

# Files every fully shipped adapter additionally ships.
YCI_ADAPTER_PHASE1_FILES=(
  evidence-template.md
  handoff-checklist.md
)

# Regimes that ship the full adapter shape today. The variable name is kept for
# validator compatibility, but it now represents all fully shipped adapters.
YCI_ADAPTER_PHASE1_REGIMES=(
  commercial
  none
  hipaa
  pci
  soc2
)

# Regimes that are exempt from evidence-schema.json. Exempt regimes are also
# allowed to omit any *-redaction.rules file (they do no redaction). The
# canonical and only current member is "none".
YCI_ADAPTER_SCHEMA_EXEMPT=(
  none
)

# Current evidence schema version shipped by the commercial adapter.
# Bump when commercial/evidence-schema.json changes shape.
YCI_ADAPTER_COMMERCIAL_SCHEMA_VERSION=1

# Current evidence schema version for the regulated adapters shipped by issue
# #34. Bump when any of those adapters' evidence-schema.json files change shape.
YCI_ADAPTER_REGULATED_SCHEMA_VERSION=1

# yci_adapter_is_schema_exempt <regime>
#
# Prints nothing. Returns 0 if <regime> is in YCI_ADAPTER_SCHEMA_EXEMPT, else 1.
# Callers SHOULD quote the argument to tolerate an empty regime.
yci_adapter_is_schema_exempt() {
  local needle="${1:-}"
  local entry
  for entry in "${YCI_ADAPTER_SCHEMA_EXEMPT[@]}"; do
    if [ "${entry}" = "${needle}" ]; then
      return 0
    fi
  done
  return 1
}

# yci_adapter_is_phase1 <regime>
#
# Prints nothing. Returns 0 if <regime> is in YCI_ADAPTER_PHASE1_REGIMES
# (i.e. ships the evidence-template.md + handoff-checklist.md pair), else 1.
yci_adapter_is_phase1() {
  local needle="${1:-}"
  local entry
  for entry in "${YCI_ADAPTER_PHASE1_REGIMES[@]}"; do
    if [ "${entry}" = "${needle}" ]; then
      return 0
    fi
  done
  return 1
}

# yci_adapter_expected_files <regime>
#
# Prints the list of files that adapter <regime> must ship, one per line.
# Always includes YCI_ADAPTER_REQUIRED_FILES; shipped regimes additionally
# require YCI_ADAPTER_PHASE1_FILES. Schema-exempt regimes still get the shipped
# files if they are on the shipped list (the exemption only applies to
# evidence-schema.json and *-redaction.rules, not to template/checklist).
yci_adapter_expected_files() {
  local regime="${1:-}"
  local file
  for file in "${YCI_ADAPTER_REQUIRED_FILES[@]}"; do
    printf '%s\n' "${file}"
  done
  if yci_adapter_is_phase1 "${regime}"; then
    for file in "${YCI_ADAPTER_PHASE1_FILES[@]}"; do
      printf '%s\n' "${file}"
    done
  fi
  return 0
}

# yci_adapter_requires_redaction_rules <regime>
#
# Returns 0 when a regime must ship at least one *-redaction.rules file.
yci_adapter_requires_redaction_rules() {
  local regime="${1:-}"
  if yci_adapter_is_schema_exempt "${regime}"; then
    return 1
  fi
  yci_adapter_is_phase1 "${regime}"
}

# yci_adapter_requires_evidence_schema <regime>
#
# Returns 0 when a regime must ship evidence-schema.json.
yci_adapter_requires_evidence_schema() {
  local regime="${1:-}"
  if yci_adapter_is_schema_exempt "${regime}"; then
    return 1
  fi
  yci_adapter_is_phase1 "${regime}"
}
