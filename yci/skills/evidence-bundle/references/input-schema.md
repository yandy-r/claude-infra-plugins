# Evidence Bundle Manifest Schema

The supplemental manifest can be YAML or JSON. It carries execution metadata
that does not live in the upstream `network-change-review` evidence stub.

## Required fields

| Field                     | Type          | Notes                                                |
| ------------------------- | ------------- | ---------------------------------------------------- |
| `git.commit_range`        | string        | Commit range or revision spec covering the change    |
| `git.diff_path`           | string        | Path to the diff or change artifact                  |
| `approvals`               | array[string] | Human-readable approvals                             |
| `pre_state`               | array[string] | Pre-change state artifact paths                      |
| `post_state`              | array[string] | Post-change state artifact paths                     |
| `operator_identity`       | string        | Operator who assembled the bundle                    |
| `tenant_scope`            | array[string] | Tenants, services, or environments touched           |
| `timestamps.generated_at` | string        | ISO-8601 UTC timestamp when the bundle was assembled |
| `timestamps.executed_at`  | string        | ISO-8601 UTC timestamp when the change executed      |

## Optional adapter-specific fields

- `pci.cde_boundary_attestation` — string
- `soc2.control_mappings` — array of CC-series control identifiers
- `hipaa.baa_reference_override` — string; only used if the profile omits
  `compliance.baa_reference`

## Example

```yaml
git:
  commit_range: abc123..def456
  diff_path: ./fixtures/changes/example.diff
approvals:
  - CAB-123 approved by ops@example.com
pre_state:
  - artifacts/pre/interfaces.txt
post_state:
  - artifacts/post/interfaces.txt
operator_identity: ops@example.com
tenant_scope:
  - tenant-a
  - payments
timestamps:
  generated_at: 2026-04-21T15:00:00Z
  executed_at: 2026-04-21T14:45:00Z
pci:
  cde_boundary_attestation: Change is limited to the east CDE edge pair.
soc2:
  control_mappings:
    - CC6.1
    - CC7.2
```
