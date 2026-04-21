# Error Messages

## Purpose

This document is the canonical catalog of every `ncr-*` error ID that
`yci:network-change-review` emits. Every script in the skill tree (parse-change.sh,
derive-rollback.sh, render-artifact.sh, etc.) MUST use only IDs defined here. IDs
are stable — renaming or removing an ID is a breaking change. Callers should key on
exit code + stderr ID prefix (`[ncr-<id>]`), not on message text, which may evolve.

---

## Error ID Catalog

| ID                                 | Triggered by                                                                                                        | Message template                                                                | Exit | Recovery                                                        |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ---- | --------------------------------------------------------------- |
| `ncr-customer-unresolved`          | `review.sh` after `resolve-customer.sh` returns empty                                                               | `No active customer. Run /yci:switch <customer> first.`                         | 2    | Set active customer via `/yci:switch`                           |
| `ncr-profile-load-failed`          | `load-profile.sh` error                                                                                             | `Failed to load profile: {detail}`                                              | 2    | Fix profile YAML; re-run                                        |
| `ncr-adapter-unresolvable`         | `load-compliance-adapter.sh` error                                                                                  | `Failed to resolve compliance adapter: {detail}`                                | 2    | Check profile `compliance.regime` matches a shipped adapter     |
| `ncr-diff-unsupported-shape`       | `parse-change.sh` detection                                                                                         | `Unsupported change shape. Supported: unified-diff, structured-yaml, playbook.` | 3    | Reshape input to a supported format                             |
| `ncr-targets-unresolvable`         | `parse-change.sh` heuristic failure                                                                                 | `Could not resolve any targets from change input.`                              | 3    | Add explicit `targets:` or adjust diff paths to match inventory |
| `ncr-sanitizer-input-rejected`     | `sanitize-output.sh` strict mode                                                                                    | `Sanitizer rejected input diff: {detail}`                                       | 4    | Review diff; remove disallowed content before re-running        |
| `ncr-rollback-missing-reverse`     | `derive-rollback.sh` — structured-yaml without `reverse:`                                                           | `Structured change lacks required \`reverse:\` block.`                          | 3    | Supply `reverse:` block alongside `forward:` in change file     |
| `ncr-rollback-ambiguous`           | `derive-rollback.sh` — playbook or unknown `diff_kind`                                                              | `Rollback confidence: low. Manual derivation required.`                         | 0    | Review the artifact warning callout; derive rollback manually   |
| `ncr-rollback-binary-unsupported`  | `derive-rollback.sh` — binary chunk detected in diff                                                                | `Binary diffs are not auto-reversible.`                                         | 3    | Supply a structured-yaml change with an explicit `reverse:`     |
| `ncr-blast-radius-failed`          | `blast-radius/scripts/reason.sh` non-zero exit                                                                      | `Blast radius reasoner failed: {detail}`                                        | 5    | Inspect reasoner stderr output; fix input or reasoner config    |
| `ncr-branding-template-missing`    | `render-artifact.sh` — customer brand path not found                                                                | `Customer branding template not found at {path}.`                               | 6    | Fix `deliverable.header_template` in profile, then re-run       |
| `ncr-adapter-template-missing`     | `render-artifact.sh` — adapter evidence template missing                                                            | `Compliance adapter template not found at {path}.`                              | 6    | Verify adapter directory integrity; re-install plugin           |
| `ncr-cross-customer-leak-detected` | `review.sh` step 8 preflight (`preflight-cross-customer.sh`) **or** `customer-isolation/detect.sh` post-render scan | `Cross-customer identifier leak detected; artifact discarded.`                  | 7    | Review sanitizer rules; correct cross-reference; re-run         |

---

## Design Notes

### Exit code grouping

Exit codes are grouped by failure domain to allow callers to triage without
inspecting message text.

**Group 2 — setup / configuration** (`ncr-customer-unresolved`,
`ncr-profile-load-failed`, `ncr-adapter-unresolvable`): the skill cannot start
useful work until the configuration problem is resolved. No partial artifact is
written. These errors should always be surfaced directly to the operator.

**Group 3 — input shape** (`ncr-diff-unsupported-shape`, `ncr-targets-unresolvable`,
`ncr-rollback-missing-reverse`, `ncr-rollback-binary-unsupported`): the change file
provided via `--change` does not meet the skill's input contract. No artifact is
written. The operator must correct the change file and re-invoke. Group 3 errors are
not retried silently — the root cause is in the input, not in a transient condition.

**Exit 4 — sanitizer hard-stop** (`ncr-sanitizer-input-rejected`): the diff contains
content that the active compliance adapter's redaction rules forbid in output
artifacts (e.g., private keys, RFC1918 addresses, internal hostnames). The diff must
be reviewed and corrected before re-running. This exit is distinct from group 3
because the file shape is valid but the content violates a policy boundary.

**Exit 5 — composed skill failure** (`ncr-blast-radius-failed`): `yci:blast-radius`
exited non-zero. The blast-radius skill has its own diagnostics; callers should
inspect its stderr output before re-running. No NCR artifact is written until blast
radius succeeds.

**Group 6 — rendering environment** (`ncr-branding-template-missing`,
`ncr-adapter-template-missing`): files that should exist in the plugin installation
or in the customer profile are absent. These typically indicate a misconfigured
profile (`deliverable.header_template` points to a non-existent file) or a corrupt
plugin install. The partial artifact is discarded.

**Exit 7 — isolation / security gate** (`ncr-cross-customer-leak-detected`): either
the **preflight** scan on the raw change input (`review.sh` step 8 /
`preflight-cross-customer.sh`) or the **post-render** `customer-isolation/detect.sh`
scan found identifiers from another customer engagement. The artifact is discarded
immediately (or never produced, when preflight fails). This exit code MUST NOT be
silently suppressed by calling scripts. Any suppression would bypass a critical
data-isolation control.

### Exit 0 warnings

`ncr-rollback-ambiguous` intentionally exits 0. Low rollback confidence is a
warning condition, not a fatal error — the artifact is still emitted with a visible
rollback confidence callout block so the operator can supplement the rollback plan
before the change window opens. Treating low confidence as a hard stop would block
legitimate playbook-shaped changes where manual rollback is the intended path.

### Stderr format

Every error is written to stderr in the format:

```
[ncr-<id>] <resolved message>
```

where `<resolved message>` has the `{detail}` and `{path}` placeholders replaced
with the actual values. The `[ncr-<id>]` prefix is stable; automated callers may
parse it with a simple prefix match.

### Adding a new error ID

When a new failure mode is introduced in any script under this skill:

1. Choose an ID that begins `ncr-` and uses kebab-case. Prefer descriptive names
   that identify the script and the failure mode (e.g., `ncr-derive-rollback-*`
   for failures in `derive-rollback.sh`).
2. Pick the exit code group that matches the failure domain (see groupings above).
   Do not reuse or alias exit codes across groups — the grouping is the stable
   contract for automated callers.
3. Add the new row to the catalog table above before adding the `exit` call in
   the script. The table is the authoritative definition; the script is the
   implementation.
4. Cross-reference the new ID in whichever other reference docs apply
   (`change-input-schema.md`, `artifact-template.md`, etc.).
5. Add a test case to the skill's `tests/` directory that covers the new error path
   (see step 6.1 acceptance test).

Do not add error IDs to scripts without adding them to this catalog first. An
undocumented `ncr-*` exit in a script is a defect, not a feature.

---

## See Also

- `./change-input-schema.md` — input shape detection and `targets[]` derivation
- `./evidence-stub-schema.md` — evidence stub field requirements
- `./artifact-template.md` — slot map for the rendered output artifact
- `./consultant-brand.md` — consultant brand block used in rendered artifacts
