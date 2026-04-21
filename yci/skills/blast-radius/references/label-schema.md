# Blast-Radius Label Schema

The `yci:blast-radius` skill emits a **typed JSON blast-radius label** that
downstream skills consume verbatim. The schema is a stable contract; changes to
required fields require a coordinated version bump across every consumer.

This document is the human-readable spec. The machine-readable copy lives at
[`label-schema.json`](./label-schema.json) (JSON Schema, Draft 2020-12).

> **PRD binding**: §6.1 P0.7 (`yci:blast-radius`). Downstream consumers:
> P0.4 (`yci:evidence-bundle`), P0.5 (`yci:network-change-review`),
> P0.6 (`yci:mop`), P0.8 (`yci/hooks/change-window-gate`).

## Shape

```json
{
  "schema_version": 1,
  "change_id": "ACME-CR-2026-0418-01",
  "customer": "widget-corp",
  "inventory_adapter": "file",
  "inventory_source_fingerprint": "sha256:abc123…",
  "generated_at": "2026-04-21T14:32:07Z",
  "tenants": ["retail-ops"],
  "services": [
    {
      "id": "orders-api",
      "criticality": "tier-1",
      "rto_band": "5m-1h",
      "owner_tenant": "retail-ops"
    }
  ],
  "direct_devices": [{ "id": "dc1-edge-01", "role": "edge-router", "site": "dc1" }],
  "dependencies": [{ "from": "orders-api", "to": "dc1-edge-01", "type": "routes-via" }],
  "downstream_consumers": [
    { "id": "checkout-web", "kind": "service", "distance": 1 },
    { "id": "retail-ops", "kind": "tenant", "distance": 2 }
  ],
  "rto_band": "5m-1h",
  "confidence": "high",
  "coverage_gaps": []
}
```

## Field reference

### Top-level

| Field                          | Type             | Required | Meaning                                                                                         |
| ------------------------------ | ---------------- | :------: | ----------------------------------------------------------------------------------------------- |
| `schema_version`               | integer          |   yes    | Contract version. Currently `1`. Bump on breaking change.                                       |
| `change_id`                    | string           |   yes    | Opaque identifier copied verbatim from the change input.                                        |
| `customer`                     | string           |   yes    | Active customer id (matches `customer.id` in the loaded profile).                               |
| `inventory_adapter`            | string enum      |   yes    | `file`, `netbox`, `nautobot`, `servicenow-cmdb`, `infoblox`, or `none`.                         |
| `inventory_source_fingerprint` | string           |   yes    | `sha256:<hex>` of the canonical JSON inventory the reasoner ingested.                           |
| `generated_at`                 | string (RFC3339) |   yes    | UTC ISO-8601 timestamp when the label was produced.                                             |
| `tenants`                      | array\<string\>  |   yes    | Distinct tenant ids touched (direct or downstream). May be empty.                               |
| `services`                     | array\<object\>  |   yes    | Impacted services. See [Services](#services). May be empty.                                     |
| `direct_devices`               | array\<object\>  |   yes    | Devices named directly by the change. See [Devices](#devices).                                  |
| `dependencies`                 | array\<object\>  |   yes    | Edge list explaining _why_ each impact was derived. See [Dependencies](#dependencies).          |
| `downstream_consumers`         | array\<object\>  |   yes    | Services and tenants reached via the dependency graph. See [Downstream](#downstream-consumers). |
| `rto_band`                     | string enum      |   yes    | Aggregate RTO band. See [RTO bands](#rto-bands).                                                |
| `confidence`                   | string enum      |   yes    | `high`, `medium`, or `low`. See [Confidence rule](#confidence-rule).                            |
| `coverage_gaps`                | array\<object\>  |   yes    | Holes in the inventory the reasoner encountered. May be empty.                                  |

### Services

Each entry:

| Field          | Type        | Required | Meaning                                                   |
| -------------- | ----------- | :------: | --------------------------------------------------------- |
| `id`           | string      |   yes    | Service id (matches `[a-z0-9][a-z0-9-]*`).                |
| `criticality`  | string enum |   yes    | `tier-1`, `tier-2`, `tier-3`, `tier-4`, or `unknown`.     |
| `rto_band`     | string enum |   yes    | See [RTO bands](#rto-bands).                              |
| `owner_tenant` | string      |    no    | Tenant id that owns the service. Absent = not attributed. |

### Devices

Each entry in `direct_devices`:

| Field  | Type   | Required | Meaning                                                    |
| ------ | ------ | :------: | ---------------------------------------------------------- |
| `id`   | string |   yes    | Device id.                                                 |
| `role` | string |   yes    | Role slug (`edge-router`, `spine`, `leaf`, `firewall`, …). |
| `site` | string |    no    | Site id. Absent = unknown / global.                        |

### Dependencies

Each entry is an **edge** in the impact graph showing why a service or consumer
made it into the label.

| Field  | Type        | Required | Meaning                                                                     |
| ------ | ----------- | :------: | --------------------------------------------------------------------------- |
| `from` | string      |   yes    | Source id (service, device, or tenant).                                     |
| `to`   | string      |   yes    | Target id.                                                                  |
| `type` | string enum |   yes    | `depends-on`, `routes-via`, `auth-via`, `stores-in`, `hosts`, `peers-with`. |

Edges are deduplicated but order-preserving: the order encodes BFS discovery,
which is useful for narrative rendering.

### Downstream consumers

Each entry:

| Field      | Type        | Required | Meaning                                     |
| ---------- | ----------- | :------: | ------------------------------------------- |
| `id`       | string      |   yes    | Service or tenant id.                       |
| `kind`     | string enum |   yes    | `service` or `tenant`.                      |
| `distance` | integer ≥ 1 |   yes    | BFS distance from the change (1 = one hop). |

`direct_devices` is intentionally _not_ an entry in `downstream_consumers`;
distance-0 items are already represented in `direct_devices` and `services`.

### Coverage gaps

Each entry records a place the reasoner had to guess or bail:

| Field    | Type        | Required | Meaning                                                                                                     |
| -------- | ----------- | :------: | ----------------------------------------------------------------------------------------------------------- |
| `kind`   | string enum |   yes    | `unknown-device`, `unknown-service`, `orphan-edge`, `missing-rto`, `missing-criticality`, `missing-tenant`. |
| `detail` | string      |   yes    | Human-readable specifics (e.g., `"device 'dc9-tor-42' referenced by change but not in inventory"`).         |

## RTO bands

Canonical ordered set, _coarser bands are safer defaults_ when a precise value
is missing:

| Band      | Meaning                                             |
| --------- | --------------------------------------------------- |
| `lt-5m`   | < 5 minutes recovery                                |
| `5m-1h`   | 5 minutes to 1 hour                                 |
| `1h-4h`   | 1 hour to 4 hours                                   |
| `gt-4h`   | > 4 hours                                           |
| `unknown` | No inventory data available; operator must confirm. |

### Aggregate RTO-band rule

The top-level `rto_band` is computed by this deterministic rule:

1. Collect the `rto_band` of every entry in `services` (direct or downstream).
2. Discard any `unknown`. (They are surfaced as `coverage_gaps`, not absorbed.)
3. If the set is empty → `rto_band = "unknown"`.
4. Otherwise → `rto_band = strictest` where strictest is the band with the
   shortest recovery window (`lt-5m` < `5m-1h` < `1h-4h` < `gt-4h`).

This is a **worst-case rollup**, not an average. Consumers (MOP, CAB) must see
the most aggressive RTO the change could breach.

### Per-service RTO-downgrade rule

When an individual service's `rto_band` is absent from the inventory, the
reasoner applies:

- If the service is _only_ reached via a single-homed dependency whose target
  has a known `rto_band` → inherit that band.
- Otherwise → `rto_band = "unknown"` and emit a `missing-rto` coverage gap.

Never fabricate bands heuristically (e.g., "tier-1 ⇒ lt-5m"). Inventory is
authoritative; absence of data is reported, not guessed.

## Confidence rule

Confidence is a direct function of coverage gaps, not a subjective estimate:

| Condition                                                                   | Confidence |
| --------------------------------------------------------------------------- | ---------- |
| `coverage_gaps == []`                                                       | `high`     |
| Only `missing-rto` or `missing-criticality` entries (no structural gaps)    | `medium`   |
| Any `unknown-device`, `unknown-service`, `orphan-edge`, or `missing-tenant` | `low`      |

Structural gaps mean the graph itself is incomplete; those downgrade to `low`
regardless of how many data-quality gaps exist.

## Inventory source fingerprint

`inventory_source_fingerprint` is `sha256:<hex>` of:

```
SHA-256(
  JSON.stringify(
    { tenants, services, devices, dependencies, sites },
    { sort_keys: true, separators: (",", ":") }
  )
)
```

computed over the adapter's normalized output (the same JSON that was piped
into the reasoner on stdin). This lets downstream consumers prove their label
was produced against the exact inventory snapshot the operator was looking at.

## Schema version policy

- **v1** (current): fields above are required.
- Additive changes (new optional fields) do **not** bump `schema_version`;
  consumers must tolerate unknown top-level keys.
- Removing, renaming, or retyping any required field **does** bump
  `schema_version`. Consumer skills pin a `schema_version` they accept and
  refuse labels with a different value.
