# Commercial Compliance Adapter

## Regime

`commercial`

## Intent

This adapter implements generic best-practice change-management and
customer-engagement hygiene without any regulator-specific framing. It is the
intended default for non-regulated customers: commercial engagements that are
subject to good engineering discipline and customer accountability, but do not
operate under a named regulatory body (HIPAA, PCI-DSS, SOX, SOC 2, ISO 27001,
NIST 800-53, etc.). Per PRD §11.2, the `commercial` adapter ships first in the
compliance adapter rollout order, covering the broadest slice of the customer
base before specialized regime adapters are layered in.

## Evidence schema

File: `evidence-schema.json`
Schema version: `1`
JSON Schema dialect: draft-07

Required fields and their purpose:

| Field                  | Type               | Description                                                                                    |
| ---------------------- | ------------------ | ---------------------------------------------------------------------------------------------- |
| `change_id`            | string             | Unique ID for this change event (ticket reference, UUID, or opaque token).                     |
| `change_summary`       | string             | One-paragraph human summary of what changed and why.                                           |
| `pre_check_artifacts`  | array[string]      | Paths or URIs to artifacts captured before the change (state dumps, screenshots, test output). |
| `post_check_artifacts` | array[string]      | Paths or URIs to artifacts captured after the change (same shape as pre_check_artifacts).      |
| `rollback_plan`        | string             | Human-readable rollback steps or a reference to a rehearsed runbook.                           |
| `approver`             | string             | Identity of the human who approved this change (email, handle, or ticket approver).            |
| `timestamp_utc`        | string (date-time) | ISO-8601 UTC timestamp the change landed.                                                      |
| `profile_commit`       | string             | Git commit hash of the customer profile snapshot used for this change.                         |

`additionalProperties` is `true` — downstream adapters (HIPAA, PCI, etc.) may
extend the bundle with regime-specific fields without invalidating a
`commercial`-validated document.

## Evidence template

File: `evidence-template.md`

The template uses `{{double_braces}}` placeholders matching the schema field
names above. Handlebars-style `{{#each}}` blocks are used for list fields
(`pre_check_artifacts`, `post_check_artifacts`). Skills should substitute
actual values before writing the artifact. The YAML frontmatter declares
`schema: commercial/1` so downstream tooling can identify the adapter version
without parsing the body.

## Redaction rules

File: `generic-redaction.rules`

Format: the `NAME:<rule-name>` / `RE:<python-regex>` paragraph format
consumed by `yci/skills/_shared/telemetry-sanitizer/scripts/load_adapter_rules.py`.
Discovery is glob-based (`*-redaction.rules`), so the filename prefix
(`generic-`) describes the rule class within this adapter.

Pattern classes applied by this adapter:

- **secrets** — AWS access key IDs, GCP API keys, GitHub tokens, generic
  `password`/`passwd`/`pwd` assignments, Bearer tokens.
- **private keys** — PEM-encoded RSA, DSA, EC, OpenSSH, and generic private
  key blocks.
- **RFC1918 + link-local IPs** — 10.x.x.x, 172.16-31.x.x, 192.168.x.x,
  169.254.x.x. These are internal addresses that must not appear in
  customer-facing artifacts.
- **hostnames** — names ending in `.internal`, `.corp`, `.local`, `.lan`,
  `.intranet`. These are topology-disclosing consultant-internal identifiers.

Explicit note: this adapter applies **no PHI, no PCI, no regulator-specific
markers**. Those pattern classes belong to the HIPAA and PCI adapters
respectively. The `commercial` adapter is intentionally narrower to avoid
false positives on non-regulated customer data.

## Handoff checklist

File: `handoff-checklist.md`

A reviewer checklist that must be satisfied before an evidence bundle or
deliverable leaves the engagement. The checklist is in GitHub-style task-list
format (`- [ ] ...`). The reviewer marks each item, or records an explicit
waiver comment where an item does not apply.

## Promises

A skill loading this adapter can rely on the following:

- The evidence bundle conforms to `evidence-schema.json` version `1` — all
  eight required fields are present and typed correctly.
- Schema version is declared as `commercial/1` in the evidence template
  frontmatter and recorded in the customer profile's
  `compliance.evidence_schema_version` field.
- Redaction patterns for secrets, private keys, RFC1918/link-local IPs, and
  internal hostnames have been applied before the artifact is written.
- The handoff checklist has been reviewed and all items are either ticked or
  carry an explicit waiver comment.
- No PHI, PCI, or regulator-specific redaction markers are applied (those
  belong to their respective adapters).

## Invariants

None regime-specific beyond the generic best-practice controls.

## Versioning

Evidence schema version is `1`. Any addition, removal, or type change to a
field in `evidence-schema.json` must:

1. Bump `$id` in `evidence-schema.json` to reflect the new version number.
2. Update the version reference in this file (`ADAPTER.md`) and in
   `evidence-template.md` frontmatter (`schema: commercial/<new-version>`).
3. Update `compliance.evidence_schema_version` in every customer profile that
   uses `compliance.regime: commercial`.

The version number in `evidence-schema.json` is the canonical source of truth.
Profile fields and template frontmatter must stay in sync with it.
