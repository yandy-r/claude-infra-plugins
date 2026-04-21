---
description: Produce a dual-branded network change review deliverable (blast radius, rollback plan, pre/post checks, evidence stub) for the active customer.
argument-hint: '<change-path> [--data-root <path>] [--customer <name>] [--format <fmt>]'
allowed-tools:
  - Read
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/network-change-review/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/*.sh:*)
  - Bash(cat:*)
  - Bash(test:*)
---

# /yci:review

Produce a dual-branded network change review deliverable for the active customer.
This includes blast-radius analysis, rollback plan, pre/post check catalogs, and a
compliance-regime evidence stub. No change is applied — the output is a reviewable
artifact the operator can hand to the customer.

## What it does

- Resolves the active customer profile (env var, dotfile, or `state.json`).
- Validates the change path argument against the active customer's scope tags.
- Invokes `yci:network-change-review` to produce the full review artifact.
- Tags the artifact with the active customer id, engagement id, and compliance
  regime.
- Writes the artifact to the deliverable path defined in the profile
  (default: `$YCI_DATA_ROOT/artifacts/<customer>/network-change-review/<change_id>-<timestamp>/`,
  matching `yci:network-change-review` / `SKILL.md`).

## Arguments

- `<change-path>` — required. Path to the diff, config file, or change directory
  to review (e.g., `changes/proposed-acl-update.diff`).
- `--data-root <path>` — optional. Overrides `$YCI_DATA_ROOT` and the
  `~/.config/yci/` default.
- `--customer <name>` — optional. Overrides the active customer for this run only
  (does NOT persist to `state.json`).
- `--format <fmt>` — optional. Output format override. Valid values: `markdown`
  (default), `json`. Profile's `deliverable.format` is authoritative when not
  passed.

## Active customer resolution

The active customer is resolved in precedence order:

1. `--customer <name>` flag (session-scoped, this run only).
2. `$YCI_CUSTOMER` env var (session-scoped).
3. `.yci-customer` dotfile (walk-up from CWD).
4. `<data-root>/state.json` `.active` field (what `/yci:switch` writes).
5. Refuse with a clear error if none resolves.

## Instructions

Load and follow the `yci:network-change-review` skill with $ARGUMENTS.
