# HIPAA Compliance Adapter

## Regime

`hipaa`

## Intent

This adapter implements healthcare-oriented evidence bundles for engagements
that operate under HIPAA / HITECH controls. It extends the commercial baseline
with BAA-aware metadata, PHI-focused redaction rules, and handoff checks that
explicitly confirm the artifact is suitable for regulated customer review.

## Evidence schema

File: `evidence-schema.json`
Schema version: `1`
JSON Schema dialect: draft-07

Required adapter-specific fields:

| Field                  | Type   | Description                                                                      |
| ---------------------- | ------ | -------------------------------------------------------------------------------- |
| `baa_reference`        | string | Business Associate Agreement or equivalent DPA reference from the active profile |
| `phi_redaction_status` | string | Whether PHI redaction rules were applied before the bundle was written           |
| `operator_identity`    | string | Human operator who assembled the evidence bundle                                 |

The schema also inherits the common evidence fields (`change_id`,
`change_summary`, `pre_check_artifacts`, `post_check_artifacts`,
`rollback_plan`, `approver`, `timestamp_utc`, `profile_commit`) expected by the
commercial baseline.

## Evidence template

File: `evidence-template.md`

The template extends the baseline evidence layout with HIPAA-specific metadata:
BAA reference, PHI redaction status, tenant scope, and operator identity.

## Redaction rules

File: `phi-redaction.rules`

Pattern classes applied by this adapter:

- SSN-like values
- MRN-like identifiers
- DOB markers
- PHI-style patient-name markers used in change tickets or evidence notes

## Handoff checklist

File: `handoff-checklist.md`

The reviewer must confirm the BAA reference, PHI redaction status, customer
branding, and signature metadata before the bundle is delivered.

## Promises

- The bundle includes a `baa_reference` field taken from the active customer
  profile.
- PHI-shaped patterns are scrubbed before the final artifact is written.
- The rendered evidence clearly records operator identity and tenant scope.

## Versioning

Evidence schema version is `1`. Bump the schema version, the template
frontmatter, and any fixture profiles together when the required field shape
changes.
