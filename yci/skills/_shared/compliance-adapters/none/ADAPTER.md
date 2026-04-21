# None Compliance Adapter

## Regime

`none`

## Intent

This adapter declares **no compliance framing**. It is intended exclusively for
internal, homelab, and non-production work where no formal compliance program
applies — personal lab environments, consultant-internal research, tooling tests,
and scratch engagements that will never produce customer-facing output. It is NOT
appropriate for any customer-facing engagement. Per PRD §11.2, `none` ships
alongside `commercial` as the Phase-1 baseline pair: `commercial` covers
generic best-practice for real customers, and `none` covers the operator's own
internal work.

## Evidence schema

**Exempt.** This adapter intentionally does NOT ship an `evidence-schema.json`.
Evidence bundles under the `none` regime are free-form and not validated against
any required-field schema. The loader and validator in `yci/skills/_shared/scripts/`
treat `none` as the canonical schema-exempt regime via `YCI_ADAPTER_SCHEMA_EXEMPT=(none)`
in `adapter-schema.sh`.

## Evidence template

See `evidence-template.md` in this directory. The template is a minimal
passthrough shape — it captures only a change identifier, a UTC timestamp, an
operator name, a free-form change summary, and operator notes. No regime-specific
fields are required. The `schema: none` frontmatter key allows downstream tooling
to distinguish a `none`-regime bundle from a commercial or regulated one without
inspecting the directory path.

## Redaction rules

**Exempt.** This adapter does NOT ship a `redaction.rules` file. No automatic
redaction is applied to content produced under the `none` regime. Operators using
`none` are responsible for any scrubbing required before sharing content outside
the homelab. See `yci/CONTRIBUTING.md § What Every Adapter Should Ship` for the
exemption entry.

## Handoff checklist

See `handoff-checklist.md` in this directory. The checklist is minimal because
there should be no customer-facing handoff under the `none` regime. Its purpose
is to give the operator a quick internal gate — confirm the note stays internal,
confirm no regulated data was processed, and confirm a follow-up plan if scope
unexpectedly expands to a real customer.

## Invariants

- **No customer-facing distribution.** If content must leave the homelab, switch
  the profile's `compliance.regime` to `commercial` (or a stricter regime) and
  re-run evidence generation under that adapter.
- **No PHI, PCI, or regulated data should be processed under this regime** —
  those demand a real adapter with a schema, redaction rules, and a full handoff
  checklist designed for that regulatory surface.

## Promises

- The loader resolves `regime: none` in a customer profile to this adapter
  directory. No further configuration is required.
- Schema and redaction are exempt by design, not by oversight. The absence of
  `evidence-schema.json` and `redaction.rules` is load-bearing: the loader uses
  it as the canonical signal to skip validation for this regime.
- The `_internal` stock profile (`yci/docs/profiles/_internal.yaml.example`)
  defaults to `compliance.regime: none`. This adapter is its backing implementation.

## Versioning

No `evidence_schema_version` is consumed for `none`. Profiles may still set
`compliance.evidence_schema_version: 1` for forward-compatibility (the
`_internal` stock profile does so); the field is accepted but ignored by the
loader when the regime is `none`.
