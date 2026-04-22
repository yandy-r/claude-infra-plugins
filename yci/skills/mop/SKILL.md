---
name: mop
description: Generate a customer-deliverable Method of Procedure artifact for the active customer from a reviewed change input. Produces dual-branded markdown with pre-change state capture, apply commands, post-change validation, rollback commands, abort criteria, and blast-radius context. Use when the user runs /yci:mop, asks for a MOP/runbook/method-of-procedure, or needs a change handoff document without auto-applying anything.
argument-hint: '<change-path> [--customer <name>] [--data-root <path>] [--adapter <regime>] [--format <format>] [--output-dir <path>]'
allowed-tools:
  - Read
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/mop/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/network-change-review/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/blast-radius/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/telemetry-sanitizer/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/customer-isolation/detect.sh:*)
  - Bash(cat|mkdir|test|cp|date|python3|mktemp|rm:*)
---

# mop

Produces a dual-branded, customer-deliverable Method of Procedure artifact for the
active customer. The output is markdown-first and lives under the customer's
deliverable path, never in the repository. The workflow is composition-first:
resolve the active profile, preflight the input for cross-customer leaks, normalize
the change into a bounded internal shape, derive rollback commands, run the
blast-radius reasoner, build pre/post check catalogs, render the final artifact,
sanitize it, and only then write it to disk.

## Supported inputs

- Unified diff / patch files.
- Structured YAML with `forward:` / `reverse:` blocks.
- Terraform plan JSON (`terraform show -json`-style payload).
- Vendor CLI text files with header comments declaring the vendor and target:
  - `# vendor: iosxe`
  - `# vendor: panos`
  - optional `# summary: ...`
  - optional `# change_id: ...`
  - optional repeated `# target: device=<id>` / `service=<id>` / `tenant=<id>`

Unsupported or ambiguous shapes must fail fast with the catalogued `mop-*` errors.

## Output

On success the workflow prints exactly one line to stdout: the absolute path to the
rendered `mop.md` artifact. Supporting files written alongside it:

- `change.json`
- `rollback.txt`
- `blast-radius-label.json`
- `catalog.json`

## Instructions

Invoke:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/mop/scripts/generate-mop.sh" $ARGUMENTS
```

Propagate stderr verbatim. Do not reformat script errors.
