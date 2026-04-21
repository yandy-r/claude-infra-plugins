# Evidence Stub Schema

## Purpose

This document defines the YAML frontmatter that `render-evidence-stub.sh` emits at
the end of every `yci:network-change-review` artifact. The stub satisfies PRD §6.1
P0.4 — it must be forward-compatible with the commercial compliance adapter's
`evidence-schema.json` version 1 so that the downstream `yci:evidence-bundle` skill
(P0.4) can consume the stub, validate it, and extend it with regime-specific fields
(signing, SOC 2 attestations, etc.) without needing a migration step.

**Shared vs stub-only fields:** Several keys align with `commercial/evidence-schema.json`
v1 (`schema_version`, `change_summary`, `customer_id`, `profile_commit`, `timestamp_utc`,
`approver`, `pre_check_artifacts`, `post_check_artifacts`). Others are **stub-only**
(`yci_commit`, `compliance_regime`, `blast_radius_label`, `rollback_confidence`,
`rollback_plan_path`) — they help downstream tooling select the regime and attach
files, but are not always present in the canonical schema's `required` list. The
canonical schema expects `rollback_plan` (inline content); the stub records
`rollback_plan_path` instead. During evidence-bundle assembly, the bundle step reads
`rollback_plan_path`, loads that file from the artifact directory, and sets
`rollback_plan` to the file contents **before** final validation against
`evidence-schema.json`. `additionalProperties: true` on the schema allows these stub-only
keys until the schema version bumps to include them formally.

---

## Full Field Table

| Field                  | Type             | Required | Source                                                                                   | Example                               | Notes                                                                                                                                   |
| ---------------------- | ---------------- | -------- | ---------------------------------------------------------------------------------------- | ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `schema_version`       | string           | yes      | Hardcoded by `render-evidence-stub.sh`                                                   | `"commercial/1"`                      | Matches `evidence-schema.json` `$id` version. Updated when schema version bumps.                                                        |
| `change_id`            | string           | yes      | Derived by script: `sha256sum` of raw change file, first 8 chars + UTC timestamp         | `"a3f1b2c4-20260421-1430"`            | Stable across re-renders of the same input. Format: `<sha256-first-8>-<utc-YYYYMMDD-hhmm>` (`%Y%m%d` in `render-evidence-stub.sh`).     |
| `change_summary`       | string           | yes      | `parse-change.sh` `summary` field from normalized JSON                                   | `"Adjust MTU on dc1-edge-01 to 9000"` | One-line human-readable description. Not truncated. Maps to `change_summary` / `summary` in `evidence-schema.json` v1 where applicable. |
| `customer_id`          | string           | yes      | Active customer profile `customer.id`                                                    | `"widget-corp"`                       | Stable slug, not display name.                                                                                                          |
| `profile_commit`       | string           | yes      | `git rev-parse HEAD` of `$YCI_DATA_ROOT/profiles/` dir, or `"unknown"` if not a git repo | `"d4e5f6a7"`                          | Maps to `profile_commit` in `commercial/evidence-schema.json` v1.                                                                       |
| `yci_commit`           | string           | yes      | `git -C <plugin-repo-root> rev-parse HEAD`                                               | `"78e907b3"`                          | Stub-only (not in canonical `evidence-schema.json` v1 required set).                                                                    |
| `timestamp_utc`        | string (ISO8601) | yes      | Script invocation time, `date -u +%Y-%m-%dT%H:%M:%SZ`                                    | `"2026-04-21T14:30:00Z"`              | Maps to `timestamp_utc` in `commercial/evidence-schema.json` v1.                                                                        |
| `approver`             | string           | yes      | Default `"_pending_"` at stub time; operator updates before handoff                      | `"_pending_"`                         | Maps to `approver` in `commercial/evidence-schema.json` v1.                                                                             |
| `compliance_regime`    | string           | yes      | Active customer profile `compliance.regime`                                              | `"commercial"`                        | Stub-only; allows `yci:evidence-bundle` to select the correct adapter.                                                                  |
| `rollback_plan_path`   | string           | yes      | Relative path from artifact dir to the rollback plan file                                | `"rollback/dc1-edge-01-reverse.yaml"` | Stub-specific addition; used by `yci:evidence-bundle` to attach the rollback as an artifact.                                            |
| `pre_check_artifacts`  | array of string  | yes      | `build-check-catalogs.sh` output; empty at stub time                                     | `[]`                                  | Maps to `pre_check_artifacts` in `commercial/evidence-schema.json` v1. Populated post-change.                                           |
| `post_check_artifacts` | array of string  | yes      | `build-check-catalogs.sh` output; empty at stub time                                     | `[]`                                  | Maps to `post_check_artifacts` in `commercial/evidence-schema.json` v1.                                                                 |
| `blast_radius_label`   | string (enum)    | yes      | `yci:blast-radius` reasoner output, `impact_level` field                                 | `"medium"`                            | Stub-only. Allowed values: `"low"`, `"medium"`, `"high"`.                                                                               |
| `rollback_confidence`  | string (enum)    | yes      | `derive-rollback.sh` confidence output                                                   | `"high"`                              | Stub-only. Allowed values: `"high"`, `"medium"`, `"low"`.                                                                               |

> Note: `rollback_plan` (the `commercial/evidence-schema.json` v1 required field) is
> satisfied at the evidence bundle stage (`yci:evidence-bundle`) by reading
> `rollback_plan_path` and inlining the content. The stub itself records the path
> rather than the full text to keep the frontmatter compact.

---

## YAML Example

A filled-in stub as emitted by `render-evidence-stub.sh` for a commercial-regime
change:

```yaml
schema_version: 'commercial/1'
change_id: 'a3f1b2c4-20260421-1430'
change_summary: 'Adjust MTU on primary edge router dc1-edge-01 to 9000'
customer_id: 'widget-corp'
profile_commit: 'd4e5f6a7'
yci_commit: '78e907b3'
timestamp_utc: '2026-04-21T14:30:00Z'
approver: '_pending_'
compliance_regime: 'commercial'
rollback_plan_path: 'rollback/dc1-edge-01-reverse.yaml'
pre_check_artifacts: []
post_check_artifacts: []
blast_radius_label: 'medium'
rollback_confidence: 'high'
```

For a `none`-regime change, `schema_version` is `"none"` and `compliance_regime` is
`"none"`. The `pre_check_artifacts` and `post_check_artifacts` fields are still
emitted (as empty arrays) for structural uniformity, even though the `none` adapter
does not validate them.

---

## Validation Rules

The following invariants apply when `render-evidence-stub.sh` emits the stub YAML.
Violations cause the script to exit non-zero before writing any output.

- `schema_version` MUST be exactly `"commercial/1"` for `commercial`-regime customers
  and `"none"` for `none`-regime customers. No other values are valid at stub time.
- `change_id` MUST match the pattern `[0-9a-f]{8}-[0-9]{8}-[0-9]{4}` (sha256 prefix,
  UTC date `%Y%m%d`, time `hhmm`). An empty or missing `change_id` is a hard stop.
- `customer_id` MUST match the slug from the active profile (`customer.id`). The
  value is validated at render time by comparing against the loaded profile; a
  mismatch is treated as a `ncr-cross-customer-leak-detected` risk and the stub is
  discarded.
- `blast_radius_label` MUST be one of `"low"`, `"medium"`, `"high"`. Any other value
  from the blast-radius reasoner output is normalized to `"high"` as a fail-safe.
- `rollback_confidence` MUST be one of `"high"`, `"medium"`, `"low"`. If the
  derive-rollback script exits with `ncr-rollback-ambiguous`, the value is `"low"`.
- `approver` at stub time is always `"_pending_"`. The downstream `yci:evidence-bundle`
  skill is responsible for requiring a real approver value before the bundle is signed
  and shipped. A stub with `approver: "_pending_"` is valid for in-progress artifacts
  but MUST NOT be accepted by the handoff checklist without update.
- `pre_check_artifacts` and `post_check_artifacts` are emitted as empty arrays `[]`
  at stub time. They are populated by the operator or automation after the change
  executes. `yci:evidence-bundle` validates these are non-empty before signing.

---

## Forward Compatibility with `yci:evidence-bundle`

The P0.4 `yci:evidence-bundle` skill extends this stub with regime-specific fields
(e.g., PGP signing headers, SOC 2 control mappings, HIPAA safeguard references). It
reads the stub, validates required fields against the adapter's `evidence-schema.json`
(after resolving `rollback_plan` from `rollback_plan_path` as described above), then
appends its regime-specific additions using the `additionalProperties: true` headroom in
`commercial/evidence-schema.json`. This design means the bundle layer can validate the
core commercial fields while tolerating stub-only keys until a schema version bump
promotes them. Callers MUST NOT rename or remove shared fields defined in this table —
doing so breaks the P0.4 consumer without any schema version bump to signal the
incompatibility.

---

## See Also

- `./composition-contract.md` — how the stub flows through the rendering pipeline
- `./artifact-template.md` — the `{{evidence_stub}}` slot that embeds this YAML
- `./error-messages.md` — error IDs that may be raised during stub generation
