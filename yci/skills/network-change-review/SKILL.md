---
name: network-change-review
description: 'Produce a full network-change review artifact (change plan, diff review, blast-radius, rollback, pre/post checklists, compliance evidence stub) for the active customer. Use when the user runs /yci:review <change>, asks to "review a network change", needs a customer-deliverable change document, or is preparing a CAB submission or MOP handoff. Composes ycc:planner and ycc:code-reviewer via the Agent tool for the change-plan and diff-review sections, then invokes the review.sh orchestrator for all remaining sections.'
argument-hint: '<change-path> [--customer <name>] [--data-root <path>] [--adapter <regime>] [--format <format>] [--output-dir <path>]'
allowed-tools:
  - Read
  - Write
  - Agent
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/network-change-review/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/blast-radius/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/customer-profile/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/telemetry-sanitizer/scripts/*.sh:*)
  - Bash(${CLAUDE_PLUGIN_ROOT}/skills/_shared/customer-isolation/detect.sh:*)
  - Bash(git:*)
  - Bash(cat|test|mkdir|python3|sha256sum|cp|rm|mktemp:*)
---

# network-change-review

Produces a complete, customer-deliverable network-change review artifact for the
active customer engagement. Given a change file (unified diff, structured YAML, or
playbook), this skill runs a 22-step composition pipeline: it spawns `ycc:planner`
and `ycc:code-reviewer` in parallel to generate the change-plan and diff-review
sections, then invokes `review.sh` to produce blast-radius analysis, rollback plan,
pre/post check catalogs, a compliance evidence stub, and the final rendered artifact.
The output is a single markdown file at a customer-scoped path under
`<data-root>/artifacts/<customer>/network-change-review/` — reviewable and handoff-ready,
never auto-applied.

## When to use

- The operator has a proposed network change (diff, structured YAML, playbook) and
  needs a reviewable artifact before the change window opens.
- A CAB submission or MOP handoff requires a structured change document with
  blast-radius analysis and a compliance evidence stub.
- The operator wants an implementation plan and diff review embedded in the
  deliverable alongside technical impact analysis.
- The active customer's compliance adapter (`commercial`, `hipaa`, etc.) must shape
  the artifact's evidence section and redaction rules.
- Downstream `yci:evidence-bundle` consumption is planned — this skill produces the
  evidence stub that `evidence-bundle` consumes verbatim.

## When NOT to use

- **Blast-radius label only** — use `yci:blast-radius` directly. This skill is
  heavier and writes a full deliverable artifact, not just the label.
- **No active customer** — this skill refuses to run without a resolved customer.
  Run `/yci:switch <customer>` first.
- **Change file has no parseable targets** — `parse-change.sh` exits fast with
  `ncr-targets-unresolvable`. Either add explicit `targets:` fields or reshape the
  diff so hostnames map to inventory entries.
- **Auto-applying a change to a live device** — this skill reads, reasons, and writes
  a deliverable. The operator applies. Auto-apply is a PRD §10 non-negotiable.
- **MOP generation** — use `yci:mop`, which consumes this skill's evidence stub and
  blast-radius label as inputs.

## Inputs

### Required

- `<change-path>` — path to the change file. Supported shapes: unified diff (`.diff`,
  `.patch`), structured YAML (`change_id`, `change_type`, `summary`, `targets`), or
  operator playbook. The shape is auto-detected by `parse-change.sh`. The file must
  be readable; a missing or unreadable path exits with `ncr-diff-unsupported-shape`.

### Optional overrides

- `--customer <name>` — override the active customer (else resolved from
  `$YCI_CUSTOMER`, `.yci-customer` dotfile, or `state.json` MRU).
- `--data-root <path>` — override the data root (else `$YCI_DATA_ROOT` or
  `~/.config/yci/`). Passed directly to `resolve-data-root.sh`.
- `--adapter <regime>` — compliance adapter override (else read from
  `profile.compliance.regime`). Only `commercial` and `none` are fully shipped in
  Phase 1; others exit with `ncr-adapter-unresolvable`.
- `--format <format>` — deliverable format override (else from
  `profile.deliverable.format`).
- `--output-dir <path>` — override the final artifact directory (else defaults to
  `<data-root>/artifacts/<customer>/network-change-review/<change_id>-<timestamp>/`).

## Outputs

The orchestrator prints exactly one line to stdout: the absolute path of the final
review artifact (`review.md`). Supporting files written alongside it:

- `rollback.txt` — derived rollback plan (with low-confidence warning if applicable)
- `catalog.json` — pre-check and post-check catalogs
- `evidence-stub.yaml` — compliance evidence stub consumed by `yci:evidence-bundle`
- `blast-radius-label.json` — structured blast-radius label

All files land under
`<data-root>/artifacts/<customer>/network-change-review/<change_id>-<timestamp>/`.

## Workflow

### Step 1 — Resolve active customer (preflight)

Confirm an active customer is set before touching any input. If no customer resolves
via the 4-tier precedence chain, stop immediately with a user-facing message:

```
No active customer. Run /yci:switch <customer> first.
```

Do not pass `--change` to the orchestrator until the customer is confirmed. This
preflight keeps the error message clear and avoids a partial workdir being created.

### Step 2 — Cross-customer leak preflight (before ycc agents)

Run the same foreign-identifier scan `review.sh` performs **before** parsing the
change, so raw content is never handed to subagents until this gate passes. Resolve
`YCI_DATA_ROOT` (or pass `--data-root`) the same way you will for `review.sh`, then:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/network-change-review/scripts/preflight-cross-customer.sh" \
  --data-root "<resolved-data-root>" \
  --customer "<customer-id>" \
  --change "<change-path>"
```

On exit 7, stop with `ncr-cross-customer-leak-detected` — do **not** spawn
`ycc:planner` or `ycc:code-reviewer`.

### Step 3 — Spawn ycc:planner and ycc:code-reviewer in parallel

After preflight succeeds, dispatch both subagents in **one message with two Agent
tool calls**. **Do not** paste the raw change file into prompts (avoids leaking
content across customers before the orchestrator runs). Give each subagent the
**absolute path** to the change file only and instruct them to read it themselves
via their normal file access. Save each output to a temp file:

```
NCR_WORKDIR=$(mktemp -d -t yci-ncr-skill-XXXX)
```

#### Agent call 1 — ycc:planner

```
subagent_type: "ycc:planner"
prompt: >
  A network change has been proposed for customer <customer-id>. The change file is
  at <absolute-path>; read it from disk and produce a concise implementation plan for
  the operator performing the change. Use your standard Plan Format but keep it tight
  (no parallel-mode directives). Focus on: (a) preparation steps, (b) execution steps,
  (c) immediate post-change validation. Target length: 40–80 lines. Do NOT end with the
  standard WAITING FOR CONFIRMATION prompt — this output will be embedded in a
  deliverable, not used for interactive approval.
```

Save output to `$NCR_WORKDIR/change-plan.md`.

#### Agent call 2 — ycc:code-reviewer

```
subagent_type: "ycc:code-reviewer"
prompt: >
  A network change has been proposed for customer <customer-id>. The change file is
  at <absolute-path>; read it from disk and review it for correctness, risk, and
  operational concerns. Focus on: (a) syntax / config correctness, (b) rollback
  readiness, (c) cross-device side effects, (d) monitoring coverage. Use your standard
  review format, medium severity threshold. Target length: 40–80 lines. Output as
  markdown findings, no preamble, no trailing summary.
```

Save output to `$NCR_WORKDIR/diff-review.md`.

### Step 4 — Invoke the orchestrator

After both subagents return, invoke `review.sh` with the real subagent outputs:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/network-change-review/scripts/review.sh" \
  --change <change-path> \
  --change-plan "${NCR_WORKDIR}/change-plan.md" \
  --diff-review "${NCR_WORKDIR}/diff-review.md" \
  [--customer <name>] \
  [--data-root <path>] \
  [--adapter <regime>] \
  [--format <format>] \
  [--output-dir <path>]
```

The orchestrator runs all 22 steps (flags parse, workdir, data-root, customer,
profile load, branding, adapter, preflight, change parse, rollback, blast-radius,
blast-radius markdown, change-plan slot, diff-review slot, check catalogs, evidence
stub, artifact render, post-render sanitizer, isolation check, output dir, artifact
write). Step 14 copies `change-plan.md` and step 15 copies `diff-review.md` directly
into the workdir; no placeholder is inserted because both files are pre-generated.

### Step 5 — Relay artifact path to user

Capture the single line printed to stdout by the orchestrator. Return it to the user
with a one-line summary:

```
Review artifact written to: <artifact-path>
Supporting files: rollback.txt  catalog.json  evidence-stub.yaml  blast-radius-label.json
```

Clean up `$NCR_WORKDIR` after the orchestrator exits.

### V1 optimization note

The current workflow (subagents first, then orchestrator once) is the recommended V1
path. An alternative "invoke orchestrator twice" pattern (once without subagent flags
to parse the change, then spawn subagents, then again with the real files) exists but
is heavier and unnecessary when the subagents can reason against the raw diff
directly. The single-pass pattern is known-good for Phase 1. Revisit when the change
parser's normalized JSON is more stable and the subagents benefit from structured
target context.

## Error handling

The orchestrator writes all errors to stderr in the format `[ncr-<id>] <message>`.
Propagate stderr verbatim — do not reformat.

| ID                                 | Exit | Recovery                                                        |
| ---------------------------------- | ---- | --------------------------------------------------------------- |
| `ncr-customer-unresolved`          | 2    | Run `/yci:switch <customer>` first                              |
| `ncr-profile-load-failed`          | 2    | Fix profile YAML and re-run                                     |
| `ncr-adapter-unresolvable`         | 2    | Verify `compliance.regime` matches a shipped adapter            |
| `ncr-diff-unsupported-shape`       | 3    | Reshape input to unified-diff, structured YAML, or playbook     |
| `ncr-targets-unresolvable`         | 3    | Add explicit `targets:` or adjust diff paths to match inventory |
| `ncr-rollback-missing-reverse`     | 3    | Supply a `reverse:` block in the structured YAML change         |
| `ncr-rollback-binary-unsupported`  | 3    | Use structured YAML with an explicit `reverse:` instead         |
| `ncr-sanitizer-input-rejected`     | 4    | Review diff for disallowed content; remove before re-running    |
| `ncr-blast-radius-failed`          | 5    | Inspect reasoner stderr; fix input or inventory                 |
| `ncr-branding-template-missing`    | 6    | Fix `deliverable.header_template` in profile                    |
| `ncr-adapter-template-missing`     | 6    | Verify adapter directory integrity; re-install plugin           |
| `ncr-cross-customer-leak-detected` | 7    | Review input for foreign-customer identifiers; fix and re-run   |

`ncr-rollback-ambiguous` exits 0 — it inserts a low-confidence warning callout into
the artifact rather than failing. The full error catalog with literal message text is
in `./references/error-messages.md`.

## Security

**Cross-customer isolation.** Before any parsing or reasoning, the orchestrator scans
the raw change input against every other customer's profile (`customer.id`,
`network.hostname_suffix`, `network.ipv4_ranges`). Any match triggers
`ncr-cross-customer-leak-detected` (exit 7) and aborts immediately — no workdir
content is retained. After rendering, a second isolation check runs the
`customer-isolation/detect.sh` belt-and-suspenders scan on the sanitized artifact.
If it returns `deny`, the artifact is deleted before any bytes reach disk. Both
passes are non-bypassable; there is no override or relaxed mode for normal customer
engagements.

**No auto-apply.** This skill produces a reviewable markdown artifact. It does not
execute, push, or apply any change to any device, system, or pipeline. PRD §10
lists this as a non-negotiable: the operator or their authorized pipeline applies the
change; the skill hands off a deliverable. Any modification to this skill that
introduces auto-apply behavior is a defect.

## Composition

This skill composes `yci:blast-radius` (via `blast-radius/scripts/reason.sh` and
`render-markdown.sh`), `yci:customer-profile` (via `resolve-customer.sh` and
`load-profile.sh`), the `yci:_shared` compliance adapter and telemetry sanitizer,
and — via the Agent tool — `ycc:planner` and `ycc:code-reviewer`. The Agent tool
is the only supported cross-plugin channel: no `ycc` filesystem path is sourced or
referenced in any `yci` script (per `CLAUDE.md` cross-plugin helper sharing rule).
The full composition order, data-flow diagram, and invocation mechanics by boundary
are documented in `./references/composition-contract.md`.

## See also

- `./references/composition-contract.md` — authoritative composition order,
  data flow, and per-boundary invocation mechanics
- `./references/error-messages.md` — canonical error catalog with exit codes
  and operator guidance
- `../blast-radius/SKILL.md` — blast-radius skill (invoked as a composed step)
- `../customer-profile/SKILL.md` — customer-profile skill (customer resolver)
- `docs/prps/prds/yci.prd.md` §6.1 — P0.5 keystone workflow specification
