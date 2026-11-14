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
