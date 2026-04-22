---
description: Produce a dual-branded Method of Procedure deliverable for the active customer from a reviewed change input.
argument-hint: '<change-path> [--data-root <path>] [--customer <name>] [--adapter <regime>] [--format <fmt>] [--output-dir <path>]'
allowed-tools:
  - Read
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/mop/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/*.sh:*)
  - Bash(test:*)
---

# /yci:mop

Produce a dual-branded Method of Procedure deliverable for the active customer.
This includes pre-change state capture, apply commands, post-change validation,
rollback commands, abort criteria, and blast-radius context. No change is
applied automatically.

## Instructions

Load and follow the `yci:mop` skill with $ARGUMENTS.
