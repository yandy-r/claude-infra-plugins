# Composition Contract — `yci:network-change-review`

## Purpose

This document pins the composition contract for `yci:network-change-review` so
the SKILL prompt, the `review.sh` orchestrator, and future P0.4/P0.6 skills all
share the same view of how pieces fit together. It is the authoritative design
document consulted by every implementor of this workflow. When the SKILL prompt,
`review.sh`, and any sibling reference document disagree with this contract, this
contract wins and the disagreement is a defect to be fixed.

---

## Composition Order

The following 18 ordered steps describe exactly what `review.sh` (the orchestrator
script) does from invocation to artifact write. Steps 11–13 are data derivation
steps that consume the same inputs in parallel order of readiness; they are not
concurrent process forks in the shell script — `review.sh` runs them sequentially
in this order.

1. **Parse flags.** Extract `--change`, `--data-root`, and any override flags from
   script arguments. Validate that `--change` is present, the path exists, and the
   file is readable; otherwise exit `ncr-diff-unsupported-shape` (exit 3), matching
   `review.sh` and `parse-change.sh` callers/tests.

2. **Resolve data root.** Invoke
   `_shared/scripts/resolve-data-root.sh [--data-root <path>]`. Capture the
   canonicalized path on stdout; propagate any non-zero exit verbatim.

3. **Resolve active customer.** Invoke
   `customer-profile/scripts/resolve-customer.sh --data-root <data-root>`. Capture
   the customer ID on stdout. On non-zero exit propagate verbatim — the orchestrator
   refuses to continue without an active, resolved customer.

4. **Load profile.** Invoke
   `customer-profile/scripts/load-profile.sh <data-root> <customer>`. Capture the
   normalized profile JSON on stdout. On REFUSE (non-zero exit, no active customer)
   the orchestrator exits with `ncr-customer-unresolved`. On schema violation the
   error propagates verbatim.

5. **Load compliance adapter.** Invoke
   `_shared/scripts/load-compliance-adapter.sh --export --profile-json-path <path>`
   where `<path>` is a temp file holding the profile JSON from step 4. Capture the
   exported shell variables (`YCI_ADAPTER_DIR`, `YCI_ADAPTER_REGIME`,
   `YCI_ADAPTER_HAS_SCHEMA`) via `eval`. Non-zero exit propagates verbatim; the
   orchestrator does not substitute a fallback regime.

6. **Preflight: cross-customer identifier scan (raw input).** Before parsing, scan the
   **unmodified** `--change` file for identifiers belonging to any other customer under
   `<data-root>/profiles/` (same logic as `scripts/preflight-cross-customer.sh` /
   `review.sh` step 8). On a hit, exit `ncr-cross-customer-leak-detected` (exit 7). The
   orchestrator does **not** pipe the change file through `sanitize-output.sh` before
   `parse-change.sh`, because strict redaction would strip hostnames that inventory-based
   target resolution needs (see `review.sh` comment above step 8). Policy enforcement
   that maps to `ncr-sanitizer-input-rejected` applies on the **rendered** artifact via
   `pre-write-artifact.sh` (later step), not on the raw change file at this stage.

7. **Parse and validate the change file.** Run `parse-change.sh --input <change>` and
   capture the canonical JSON envelope documented in `./change-input-schema.md`:
   `diff_kind`, `raw`, `summary`, and `targets`. These are the required top-level fields
   at parse time (`change_id` / `change_type` are **not** part of this envelope — they
   may be synthesized later for blast-radius payload helpers). If no inventory-backed
   target can be resolved where required, exit `ncr-targets-unresolvable`.

8. **Persist normalized change JSON.** Write the envelope to `${NCR_WORKDIR}/change.json`
   (or equivalent); steps 9–13 consume this file as the single canonical representation.

9. **Derive rollback.** Invoke `scripts/derive-rollback.sh` with the normalized
   change JSON on stdin. Capture the rollback plan text (and stderr warning for
   `ncr-rollback-ambiguous` when confidence is low). On `confidence: low` for
   **playbook-shaped** inputs, proceed with a `> **WARNING**` callout — do **not** fail
   the run for low confidence. For `diff_kind: unknown`, `derive-rollback.sh` exits
   non-zero with `ncr-diff-unsupported-shape` (fatal). See `./rollback-derivation.md`.

10. **Build blast-radius payload; run reasoner; render markdown.** Construct the JSON
    payload (see `review.sh`), run `blast-radius/scripts/reason.sh`, then pipe
    `blast-radius-label.json` into `blast-radius/scripts/render-markdown.sh`. Set
    `YCI_ACTIVE_REGIME` from `YCI_ADAPTER_REGIME` on the **renderer** process (not on
    `cat`). On failure exit `ncr-blast-radius-failed`.

11. **Populate change-plan and diff-review slots.** Copy `--change-plan` /
    `--diff-review` inputs when provided; otherwise write placeholders. (These files are
    produced by `ycc:planner` / `ycc:code-reviewer` at the SKILL layer.)

12. **Build check catalogs.** Invoke `scripts/build-check-catalogs.sh` with
    `--adapter-dir` and `--blast-radius-label`. Capture pre-check and post-check JSON
    (adapter `handoff-checklist.md` plus blast-radius-derived checks).

13. **Load adapter handoff checklist.** Read `${YCI_ADAPTER_DIR}/handoff-checklist.md`
    from disk. This file is referenced verbatim in the evidence stub and in the final
    artifact's handoff section.

14. **Render evidence stub.** Invoke `scripts/render-evidence-stub.sh` with the
    blast-radius label JSON, rollback JSON, check catalog JSON, adapter paths, and
    profile JSON as inputs. Capture the rendered evidence stub markdown on stdout.
    The stub schema is documented in `./evidence-stub-schema.md`. This stub is
    consumed verbatim by `yci:evidence-bundle` (P0.4).

15. **Render final artifact.** Invoke `scripts/render-artifact.sh` with the profile
    JSON, resolved adapter directory, the change-plan and diff-review markdown files,
    blast-radius markdown, rollback text and confidence, pre/post check catalog JSON
    (from `build-check-catalogs.sh`), the rendered evidence-stub YAML path, and paths
    to `references/artifact-template.md` and `references/consultant-brand.md` (resolved
    inside the script from the plugin root). The renderer reads the template and
    customer header template, substitutes every `{{slot}}` from parsed evidence stub
    and the section files, and captures the full artifact in a temp variable without
    writing to disk yet. The adapter does **not** pass a separate `evidence-template.md`
    input — evidence shape is defined by `artifact-template.md` and the stub pipeline.

16. **Sanitize rendered artifact (strict mode).** Pipe the artifact content through
    `_shared/telemetry-sanitizer/scripts/pre-write-artifact.sh --output <tmp-path>`
    (strict mode, no `--meta-file`). This is the second sanitizer pass — it catches
    any cross-customer token that the render step may have injected from profile
    metadata or adapter templates.

17. **Run customer-isolation detect (belt-and-suspenders).** Invoke
    `_shared/customer-isolation/detect.sh` with `YCI_ACTIVE_CUSTOMER` and
    `YCI_DATA_ROOT_RESOLVED` set in the environment, feeding a synthetic PreToolUse
    payload whose `tool_input` contains the proposed artifact output path. On a
    `deny` decision: DELETE the partially-written temp artifact and exit
    `ncr-cross-customer-leak-detected`.

18. **Write artifact to disk.** Move the sanitized temp artifact to the final
    destination:
    `<data-root>/artifacts/<customer>/network-change-review/<change_id>-<timestamp>/review.md`
    where `<data-root>` respects any `deliverable.path` profile override, `<customer>`
    is the resolved customer ID, and the directory is created with `mkdir -p`.
    Print the artifact path to stdout and exit 0.

---

## Invocation Mechanics by Boundary

| Composed piece                             | Invocation style                                                                                                                                                                                     | Invoked by                                                                                                                              |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `yci:customer-profile`                     | Shell scripts: `resolve-customer.sh`, `load-profile.sh`                                                                                                                                              | `review.sh`                                                                                                                             |
| `yci:customer-guard` (PreToolUse hook)     | Automatic hook intercept; NOT invoked directly                                                                                                                                                       | Claude Code runtime — NOT `review.sh`                                                                                                   |
| `yci:_shared/customer-isolation/detect.sh` | Shell script sourced and function called                                                                                                                                                             | `review.sh` (step 17 — final belt-and-suspenders negative check)                                                                        |
| `yci:telemetry-sanitizer`                  | `pre-write-artifact.sh` on the rendered artifact (strict / internal per profile); optional `sanitize-output.sh` for other CLIs — **not** used on the raw `--change` file before parse in `review.sh` | `review.sh` (post-render pass); raw change is scanned in preflight instead of sanitized early                                           |
| Compliance adapter                         | `_shared/scripts/load-compliance-adapter.sh --export --profile-json-path <path>` + filesystem reads of `evidence-template.md`, `evidence-schema.json`, `handoff-checklist.md` from `YCI_ADAPTER_DIR` | `review.sh` (step 5) and consumed by check-catalog builder (step 12), evidence-stub renderer (step 14), and artifact renderer (step 15) |
| `yci:blast-radius`                         | Shell scripts: `blast-radius/scripts/reason.sh`, `blast-radius/scripts/render-markdown.sh`                                                                                                           | `review.sh` (after rollback derivation)                                                                                                 |
| `ycc:plan` (Change Plan section)           | Agent tool with `subagent_type: "ycc:planner"` — prompt in, structured plan text out                                                                                                                 | SKILL.md prompt — NOT `review.sh`                                                                                                       |
| `ycc:code-review` (Diff Review section)    | Agent tool with `subagent_type: "ycc:code-reviewer"` — prompt in, findings text out                                                                                                                  | SKILL.md prompt — NOT `review.sh`                                                                                                       |

---

## Cross-Plugin Boundary Rule

From the project `CLAUDE.md`:

> Cross-plugin helper sharing is NOT supported — if `ycc` and `yci` both need
> the same helper, duplicate it (the duplication cost is low, the coupling cost
> is high).

This rule is why `ycc:plan` and `ycc:code-review` are invoked via the Agent tool
(prompt in, text out) rather than by sourcing any `ycc` helper scripts directly.
`review.sh` is a `yci` artifact; it cannot and must not `source` or `bash` any
file from the `ycc/` source tree. The only supported cross-plugin channel is the
Agent tool, which treats the other plugin's skill as a black box: the invoking
SKILL prompt provides a structured prompt and receives text output. No `ycc`
filesystem path is ever embedded in any `yci` script.

Stated explicitly: **If `ycc` and `yci` both need the same helper, duplicate the
helper — do not cross the plugin boundary.**

The compliance-adapter pattern in `yci/CONTRIBUTING.md` provides the precedent for
keeping adapter-specific logic inside well-defined boundaries. The same boundary
discipline applies across plugins: `yci` defines its own interface and calls `ycc`
only through documented, runtime-stable channels (the Agent tool).

---

## Data Flow Between Stages

```
raw change file
    |
    v
[Preflight] foreign-customer identifier scan (raw text; same as preflight-cross-customer.sh)
    |
    v
[Parse] parse-change.sh → envelope { diff_kind, raw, summary, targets }  (change-input-schema.md)
    |
    v
normalized change JSON  ←────────────────────────────────┐
    |                                                     │
    ├──[Rollback] derive-rollback.sh ──► rollback text     │
    │               (playbook → low confidence warning)    │
    │               (unknown diff_kind → ncr-diff-unsupported-shape)
    │                                                     │
    ├──[Blast radius] reason.sh ──► label JSON             │
    │               └── render-markdown.sh (YCI_ACTIVE_REGIME on renderer)
    │                                                     │
    └──[Catalogs] build-check-catalogs.sh                 │
                    ──► pre/post-check catalog JSON        │
                                                          │
                    load adapter handoff-checklist.md
                                                          │
[Evidence stub] render-evidence-stub.sh                   │
    (label JSON + rollback JSON + catalog JSON            │
     + adapter paths + profile JSON)                      │
    |                                                     │
    v                                                     │
evidence stub markdown                                    │
    |                                                     │
    v                                                     │
[Step 15] render-artifact.sh                              │
    (all rendered sections + profile JSON for branding   │
     + adapter evidence-template.md)                      │
    |                                                     │
    v                                                     │
full review markdown (in memory)
    |
    v
[Step 16] pre-write-artifact.sh (strict mode, sanitizer pass 2)
    |
    v
sanitized artifact (temp path)
    |
    v
[Step 17] customer-isolation detect.sh (fail-closed)
    |       deny → DELETE temp, exit ncr-cross-customer-leak-detected
    |       allow → proceed
    v
[Step 18] write to disk:
  <data-root>/artifacts/<customer>/network-change-review/<change_id>-<timestamp>/review.md
```

---

## Error Propagation

Each failure mode has a canonical error code. The full error text for every code
lives in `./error-messages.md` — this section references that catalog and does not
duplicate the message copy.

| Failure condition                               | Orchestrator behavior                               | Error code                             |
| ----------------------------------------------- | --------------------------------------------------- | -------------------------------------- |
| `customer-profile` REFUSE — no active customer  | Exit immediately; do not proceed                    | `ncr-customer-unresolved`              |
| Sanitizer / policy failure on rendered artifact | Exit immediately; temp artifact discarded           | `ncr-sanitizer-input-rejected`         |
| Parse-change: unresolvable targets              | Exit immediately; blast-radius is never attempted   | `ncr-targets-unresolvable`             |
| `derive-rollback` returns `confidence: low`     | Proceed; insert `> **WARNING**` callout in artifact | (no exit — handled in artifact render) |
| `blast-radius/reason.sh` non-zero exit          | Exit immediately                                    | `ncr-blast-radius-failed`              |
| Post-render isolation detect returns `deny`     | DELETE the partially-written temp artifact; exit    | `ncr-cross-customer-leak-detected`     |

The canonical error catalog with literal message text, exit codes, and operator
guidance is in `./error-messages.md`.

---

## Why This Composition Is "Keystone"

PRD §5.6 describes the composition model: `yci` invokes `ycc` skills freely, and
`yci:network-change-review` is the first skill to exercise the full cross-plugin
composition chain in a single workflow. PRD §6.1 (P0.5) labels it the "keystone
workflow" explicitly, and innovation NH3 (non-negotiable #3 from the threat model)
states that inadequate handoff artifacts leave the customer unable to operate what
was built. This skill is what turns blast-radius analysis, compliance-shaped
evidence, and code-review semantics into a single customer-deliverable document.
Every other `yci` workflow skill (`yci:mop` P0.6, `yci:evidence-bundle` P0.4,
`yci:cab-prep` P1.10) either consumes outputs produced by this skill (the evidence
stub, the blast-radius label) or follows its composition pattern. Shipping a
reliable `yci:network-change-review` is therefore the prerequisite for every
downstream P0 and P1 skill being worth shipping.

---

## Forward-Compatibility Notes

**Evidence stub.** The evidence stub produced in step 14 and documented in
`./evidence-stub-schema.md` is consumed verbatim by `yci:evidence-bundle` (P0.4).
The schema version field in the stub allows `evidence-bundle` to detect and reject
stubs produced by an older schema revision. Do not change the stub schema without
bumping the schema version and updating `evidence-bundle` accordingly.

**`yci:change-reviewer` agent (P0).** The `yci:change-reviewer` agent delegates
the code-review slice of this composition: it invokes `ycc:code-review` (via the
Agent tool) for a focused deep review of the diff and returns findings that the
SKILL prompt incorporates into the final artifact. The agent does not replace
`review.sh`; it is an optional delegation path for the code-review phase that keeps
the orchestrator's scope narrow.

**Generator wiring.** As of Phase 0, `yci` skills are Claude-native only. The
cross-target generators (`generate_codex_common.py`, `generate_cursor_skills.py`,
`generate_opencode_common.py`) are hardcoded to `ycc`. Parameterizing the generators
for `yci` is Phase 1a work. Do not add generator-specific logic to this skill or
its scripts in anticipation of that work.

---

## See Also

- `./rollback-derivation.md` — rollback derivation algorithm, confidence scoring,
  and the warning callout format inserted on low-confidence results
- `./change-input-schema.md` — required and optional fields for the change input
  file, supported formats (YAML/JSON), and validation error codes
- `./error-messages.md` — canonical error copy, exit codes, and operator guidance
  for every error code referenced in this contract
- `./evidence-stub-schema.md` — schema for the evidence stub produced in step 14,
  including the schema version field consumed by `yci:evidence-bundle`
- `./artifact-template.md` — the markdown template for the final review artifact,
  including branding, section order, and the compliance-adapter handoff section
