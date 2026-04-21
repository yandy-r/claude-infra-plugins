# Change-Input Schema

The `yci:blast-radius` skill reasons about a **proposed change** — a description
of what the operator intends to do, _not_ an applied change. The input is
supplied via `--change-file <path>` (YAML preferred, JSON accepted). The skill
never modifies the input.

This document is the contract for that input. It is intentionally minimal:
extra fields are tolerated (operators annotate changes with ticket IDs,
reviewers, approval chains — none of which blast-radius needs).

## Shape

```yaml
change_id: ACME-CR-2026-0418-01
change_type: config # config|firmware|replace|decommission|migration|cutover|rollback
summary: >
  Enable BGP graceful-restart on dc1 edge routers. Expected no traffic impact.
targets:
  - kind: device
    id: dc1-edge-01
  - kind: device
    id: dc1-edge-02
  - kind: service
    id: orders-api
windows: # optional — hints for downstream consumers only.
  requested_start: 2026-04-22T03:00:00Z
  requested_end: 2026-04-22T04:00:00Z
```

## Required fields

| Field         | Type        | Meaning                                                      |
| ------------- | ----------- | ------------------------------------------------------------ |
| `change_id`   | string      | Opaque identifier. Passed through to the label unchanged.    |
| `change_type` | string enum | See [Change types](#change-types).                           |
| `summary`     | string      | 1-3 sentences in natural language. Rendered in the markdown. |
| `targets`     | array       | ≥1 entries. See [Targets](#targets).                         |

## Optional fields

| Field      | Type   | Meaning                                                                  |
| ---------- | ------ | ------------------------------------------------------------------------ |
| `windows`  | object | Hint block consumed by downstream skills (change-window-gate, CAB prep). |
| `metadata` | object | Freeform operator annotations. Blast-radius ignores this.                |

Unknown top-level keys are tolerated (the reasoner ignores them silently).
This lets teams embed blast-radius input inside a larger change-ticket file
without copying it.

## Change types

| Value          | Intent                                              |
| -------------- | --------------------------------------------------- |
| `config`       | Configuration-only edit (no firmware, no topology). |
| `firmware`     | Firmware/OS upgrade. Implies reboot window.         |
| `replace`      | Hardware replacement / RMA.                         |
| `decommission` | Remove target from production.                      |
| `migration`    | Move workload from one substrate to another.        |
| `cutover`      | Atomic switchover (DNS, BGP, VIP).                  |
| `rollback`     | Revert a prior change.                              |

The reasoner does **not** use `change_type` to alter the impact graph — it is
surfaced verbatim in the markdown narrative so reviewers can weigh risk.

## Targets

Each entry identifies a resource that will be _directly_ modified. The
reasoner uses targets as the entry points for BFS on the inventory.

| Field       | Type        | Required | Meaning                                                                                      |
| ----------- | ----------- | :------: | -------------------------------------------------------------------------------------------- |
| `kind`      | string enum |   yes    | `device`, `service`, `interface`, `vlan`, `arn`, `tenant`.                                   |
| `id`        | string      |   yes    | Resource id. Must match `[a-z0-9][a-z0-9-]*` for device/service/tenant ids.                  |
| `ref`       | string      |    no    | Free-form back-reference (e.g., a Cisco interface spec `Gi0/0/1`). Not used by the reasoner. |
| `rationale` | string      |    no    | Why this target was selected. Rendered in markdown.                                          |

### Kind semantics

- `device` — match against `devices/<id>.yaml`.
- `service` — match against `services/<id>.yaml`.
- `interface` — parent device id inferred from `id` per convention
  `<device-id>:<iface>`. Only the parent device is used for reasoning; the
  interface suffix is narrative-only.
- `vlan` — matches devices with `vlans` field containing the vlan id
  (inventory side; the `file` adapter surfaces `devices[].vlans` as a list).
- `arn` — AWS ARN. Reasoner performs a direct exact-match lookup against each
  entry in `services[].arns`; if the target's id string appears verbatim in any
  service's `arns` list, that service is treated as directly impacted. No
  parsing of the ARN's service-and-resource components is performed.
- `tenant` — match against `tenants/<id>.yaml`. Direct-tenant changes surface
  the tenant in `tenants[]` of the label and downstream-expand to its
  services.

### Unknown targets

If a target's id is absent from the inventory the reasoner:

1. Emits a `coverage_gaps[]` entry with `kind: unknown-device` /
   `kind: unknown-service` / `missing-tenant` and a `detail` string that
   includes the target id.
2. Downgrades `confidence` to `low` per the
   [Confidence rule](./label-schema.md#confidence-rule) — `unknown-device`,
   `unknown-service`, `orphan-edge`, and `missing-tenant` are structural gaps
   that force low confidence.

Note: the label schema has no `targets` field. Unknown targets are **not**
echoed into `direct_devices[]`, `services[]`, or `tenants[]`; they surface
only through `coverage_gaps[]`. Operators must consult the coverage-gap
detail strings to see which requested targets were not resolved.

## Worked example

Given `change-simple.yaml`:

```yaml
change_id: WIDGET-CR-2026-04-21-A
change_type: config
summary: Change MTU to 9000 on two edge links at site-dc1.
targets:
  - kind: device
    id: dc1-edge-01
    rationale: primary edge path for orders-api
  - kind: device
    id: dc1-edge-02
    rationale: redundant edge path for orders-api
```

The reasoner:

1. Looks up `devices/dc1-edge-01.yaml` and `devices/dc1-edge-02.yaml` → both
   resolved → `direct_devices[]` populated.
2. Finds `dependencies.yaml` edges `orders-api --routes-via--> dc1-edge-01`
   and `orders-api --routes-via--> dc1-edge-02` → `services[]` includes
   `orders-api`.
3. BFS one more hop: any service that `depends-on` orders-api → added to
   `downstream_consumers` with `distance: 2`.
4. Rolls up tenants via `services[].owner_tenant`.
5. Computes aggregate `rto_band` per the strictness rule.

No coverage gaps → `confidence: high`.
