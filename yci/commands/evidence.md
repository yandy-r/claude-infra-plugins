---
description: Assemble a signed evidence bundle for the active customer from an evidence stub plus supplemental execution metadata.
argument-hint: '--evidence-stub <path> --manifest <path> [--customer <name>] [--data-root <path>] [--output-dir <path>] [--adapter <regime>]'
allowed-tools:
  - Read
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/evidence-bundle/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/*.sh:*)
  - Bash(test:*)
---

# /yci:evidence

Package a compliance-shaped evidence bundle for the active customer. This wraps
`yci:evidence-bundle`, which validates the merged payload against the active
adapter schema, renders the adapter template, and signs the final markdown
artifact.

## Instructions

Load and follow the `yci:evidence-bundle` skill with $ARGUMENTS.
