#!/usr/bin/env bash
# Sourceable contract library for the yci change-window adapter family.
#
# Declares the canonical list of shipped adapters, deferred adapters, and the
# required per-adapter file list. Consumed by `load-change-window-adapter.sh`
# and by `scripts/validate.sh` under `validate_change_window_adapters()`.
#
# Sourceable library — DO NOT set -euo pipefail at file scope.

# shellcheck disable=SC2034
# The arrays below are read by callers after sourcing; shellcheck cannot see
# across the source boundary so it flags them as unused inside this file.

# Files every change-window adapter directory MUST ship.
YCI_CW_ADAPTER_REQUIRED_FILES=(
  ADAPTER.md
  scripts/check.sh
)

# Adapters shipped and supported today. Alphabetical for deterministic listings.
YCI_CW_ADAPTERS_SHIPPED=(
  always-open
  ical
  json-schedule
  none
)

# Adapters named in PRD §5.4 but not yet implemented. The loader emits a useful
# error rather than crashing when one of these is requested.
YCI_CW_ADAPTERS_DEFERRED=(
  servicenow-cab
)

# yci_cw_adapter_is_shipped <adapter-name>
#
# Prints nothing. Returns 0 if <adapter-name> is in YCI_CW_ADAPTERS_SHIPPED,
# else 1.
yci_cw_adapter_is_shipped() {
  local needle="${1:-}"
  local entry
  for entry in "${YCI_CW_ADAPTERS_SHIPPED[@]}"; do
    if [ "${entry}" = "${needle}" ]; then
      return 0
    fi
  done
  return 1
}

# yci_cw_adapter_is_deferred <adapter-name>
#
# Prints nothing. Returns 0 if <adapter-name> is in YCI_CW_ADAPTERS_DEFERRED,
# else 1.
yci_cw_adapter_is_deferred() {
  local needle="${1:-}"
  local entry
  for entry in "${YCI_CW_ADAPTERS_DEFERRED[@]}"; do
    if [ "${entry}" = "${needle}" ]; then
      return 0
    fi
  done
  return 1
}

# yci_cw_adapter_expected_files
#
# Prints each required file from YCI_CW_ADAPTER_REQUIRED_FILES, one per line.
yci_cw_adapter_expected_files() {
  local file
  for file in "${YCI_CW_ADAPTER_REQUIRED_FILES[@]}"; do
    printf '%s\n' "${file}"
  done
  return 0
}
