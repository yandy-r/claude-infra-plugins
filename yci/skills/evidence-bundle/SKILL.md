---
name: evidence-bundle
description: Assemble a signed, compliance-adaptive evidence bundle for the active customer from an evidence stub plus supplemental execution metadata. Use when the user runs /yci:evidence, needs a handoff-ready evidence pack, or wants to package approvals, diffs, pre/post state, operator identity, and tenant scope under the active compliance adapter.
argument-hint: '--evidence-stub <path> --manifest <path> [--profile-json <path>] [--customer <name>] [--data-root <path>] [--output-dir <path>] [--adapter <regime>]'
allowed-tools:
  - Read
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/evidence-bundle/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/*.sh:*)
  - Bash(cat|mkdir|test|python3|cp|date:*)
---

# evidence-bundle

Produces a signed evidence pack for the active `yci` customer. The bundle is
adapter-driven: the active profile's `compliance.regime` selects the template,
schema, and redaction rules, while the active profile's `compliance.signing`
subtree selects the signing backend (`minisign` or `ssh-keygen -Y sign`).

## Inputs

- `--evidence-stub <path>` — required. YAML emitted by
  `yci:network-change-review` or a fixture-compatible equivalent.
- `--manifest <path>` — required. YAML or JSON supplemental evidence manifest.
  See `references/input-schema.md`.
- `--profile-json <path>` — optional. Preloaded profile JSON from
  `load-profile.sh`. When omitted, the skill resolves the active customer and
  loads the profile itself.
- `--customer <name>` / `--data-root <path>` — optional. Used when
  `--profile-json` is omitted.
- `--output-dir <path>` — optional. Defaults to
  `<data-root>/artifacts/<customer>/evidence-bundle/<change_id>-<timestamp>/`.
- `--adapter <regime>` — optional adapter override. Defaults to
  `profile.compliance.regime`.

## What it does

1. Resolves the active profile and compliance adapter.
2. Loads the evidence stub and supplemental manifest.
3. Hydrates `rollback_plan` from `rollback_plan_path`.
4. Merges approvals, commit range, diff metadata, pre/post state, operator
   identity, timestamps, and tenant scope into a canonical bundle JSON.
5. Validates the bundle against the adapter schema.
6. Renders the adapter template to `evidence.md`.
7. Signs the rendered artifact and writes signature sidecars.

## Outputs

The output directory contains:

- `bundle.json` — canonical merged evidence payload
- `manifest.json` — normalized manifest copy
- `evidence.md` — rendered adapter template
- `evidence.md.sig` — detached signature
- `signature.json` — signer metadata

Stdout prints exactly one line: the absolute path to `evidence.md`.

## Instructions

Invoke `scripts/assemble-bundle.sh` with the user arguments. Do not write files
outside the resolved customer-scoped output directory.
