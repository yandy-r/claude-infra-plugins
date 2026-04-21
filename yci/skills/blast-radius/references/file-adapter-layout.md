# File Inventory Adapter — Layout

The `file` inventory adapter is the minimum-viable adapter for `yci:blast-radius`.
It reads a structured tree of YAML files from a path on disk and emits the
normalized JSON the reasoner consumes.

> **PRD binding**: §4 (no assumption of a specific inventory / CMDB system) and
> §5.2 (profile `inventory.adapter: file` + optional `inventory.path`).

This file is the contract for that directory tree. It is also the reference
that future adapters (`netbox`, `nautobot`, `servicenow-cmdb`, …) translate
their native shapes to.

## Path resolution

The inventory root path is resolved in this order (first non-empty wins):

1. `inventory.path` in the loaded customer profile
2. `<data-root>/inventories/<customer>/` (default)

`<data-root>` comes from
[`yci/skills/_shared/scripts/resolve-data-root.sh`](../../_shared/scripts/resolve-data-root.sh).
`<customer>` comes from
[`yci/skills/customer-profile/scripts/resolve-customer.sh`](../../customer-profile/scripts/resolve-customer.sh).

The adapter refuses to read any path outside the resolved root. Paths that
traverse via `..` or symlinks pointing outside the root are rejected with
`adapter-path-escape` (exit 1).

## Directory tree

```
<inventory-path>/
├── tenants/
│   ├── retail-ops.yaml
│   └── platform.yaml
├── services/
│   ├── orders-api.yaml
│   ├── checkout-web.yaml
│   └── payment-gw.yaml
├── devices/
│   ├── dc1-edge-01.yaml
│   ├── dc1-edge-02.yaml
│   └── dc1-spine-01.yaml
├── dependencies.yaml
└── sites/                        # optional
    ├── dc1.yaml
    └── dc2.yaml
```

All filenames under `tenants/`, `services/`, `devices/`, `sites/` MUST match
`<id>.yaml` where `<id>` matches `[a-z0-9][a-z0-9-]*`. Nested subdirectories
under these kind-directories are ignored (operators often keep archived
records in `archive/`; the adapter does not scan into subfolders).

Unknown top-level directories are ignored with a stderr warning. This lets
operators keep human-only files (`README.md`, `notes/`, `diagrams/`) in the
same tree.

## Record schemas

### `tenants/<id>.yaml`

```yaml
id: retail-ops # MUST match filename basename
display_name: Retail Ops
# Optional:
description: 'Team that owns order flow.'
contacts:
  - ops@example.internal
```

| Field          | Type   | Required | Notes                                         |
| -------------- | ------ | :------: | --------------------------------------------- |
| `id`           | string |   yes    | Must match filename basename.                 |
| `display_name` | string |   yes    | Human-readable label for narrative rendering. |
| `description`  | string |    no    | Free-form.                                    |
| `contacts`     | array  |    no    | Free-form list.                               |

### `services/<id>.yaml`

```yaml
id: orders-api
criticality: tier-1 # tier-1..tier-4 or unknown
rto_band: 5m-1h # see label-schema.md RTO bands
owner_tenant: retail-ops # optional — must match a tenant id
# Optional:
display_name: Orders API
arns:
  - arn:aws:ecs:us-east-1:111111111111:service/prod/orders-api
```

| Field          | Type        | Required | Notes                                                                                |
| -------------- | ----------- | :------: | ------------------------------------------------------------------------------------ |
| `id`           | string      |   yes    | Must match filename basename.                                                        |
| `criticality`  | string enum |   yes    | `tier-1`, `tier-2`, `tier-3`, `tier-4`, `unknown`.                                   |
| `rto_band`     | string enum |   yes    | `lt-5m`, `5m-1h`, `1h-4h`, `gt-4h`, `unknown`.                                       |
| `owner_tenant` | string      |    no    | When present, must match a tenant id. Otherwise `missing-tenant` gap (warning only). |
| `display_name` | string      |    no    |                                                                                      |
| `arns`         | array       |    no    | Free-form. Used only to match change targets of `kind: arn`.                         |

### `devices/<id>.yaml`

```yaml
id: dc1-edge-01
role: edge-router
site: dc1
# Optional:
vendor: cisco
model: ASR-9006
vlans: [10, 20, 30]
services_hosted: # optional hosting edge (devices run services directly)
  - orders-api
```

| Field             | Type   | Required | Notes                                                           |
| ----------------- | ------ | :------: | --------------------------------------------------------------- |
| `id`              | string |   yes    | Must match filename basename.                                   |
| `role`            | string |   yes    | Free-form slug (e.g., `edge-router`, `spine`, `leaf`).          |
| `site`            | string |    no    | Optional; when present should match a site id.                  |
| `vendor`          | string |    no    |                                                                 |
| `model`           | string |    no    |                                                                 |
| `vlans`           | array  |    no    | Integer or string vlan ids.                                     |
| `services_hosted` | array  |    no    | Service ids this device hosts directly. Added as `hosts` edges. |

### `dependencies.yaml`

A flat list of edges. All edges are directed.

```yaml
edges:
  - from: orders-api
    to: dc1-edge-01
    type: routes-via
  - from: checkout-web
    to: orders-api
    type: depends-on
  - from: orders-api
    to: payment-gw
    type: depends-on
```

| Field  | Type        | Required | Notes                                                                       |
| ------ | ----------- | :------: | --------------------------------------------------------------------------- |
| `from` | string      |   yes    | Source id (service / device / tenant).                                      |
| `to`   | string      |   yes    | Target id.                                                                  |
| `type` | string enum |   yes    | `depends-on`, `routes-via`, `auth-via`, `stores-in`, `hosts`, `peers-with`. |

Edges whose endpoints do not resolve to a known record are surfaced as
`orphan-edge` coverage gaps; they are still included in the graph so the
narrative can show them, but they count as structural gaps and downgrade
confidence to `low`.

### `sites/<id>.yaml` (optional)

```yaml
id: dc1
display_name: 'Primary Data Centre (DC1)'
address: '...'
```

Sites are narrative-only metadata. The reasoner never uses a site's
attributes for impact propagation — it only uses the `site` field on devices
to group output.

## Normalization output

The adapter emits a single JSON object on stdout:

```json
{
  "adapter": "file",
  "root": "/abs/path/to/inventory",
  "tenants": [
    /* ... */
  ],
  "services": [
    /* ... */
  ],
  "devices": [
    /* ... */
  ],
  "sites": [
    /* ... */
  ],
  "dependencies": [
    /* edges */
  ]
}
```

`root` is the resolved absolute path (for fingerprinting / error messages
only). `devices[].services_hosted` is rewritten as `hosts` edges appended to
`dependencies[]` so the reasoner consumes a single edge list.

## Exit codes

| Exit | Reason                                            |
| ---- | ------------------------------------------------- |
| 0    | Success.                                          |
| 1    | Path does not exist, unreadable, or escapes root. |
| 2    | YAML parse error or schema violation.             |
| 3    | Runtime error — pyyaml missing.                   |

All stderr output matches a catalogued error id from
[`error-messages.md`](./error-messages.md).

## Testing

The canonical test fixture lives at
`yci/skills/blast-radius/tests/fixtures/inventory-widgetcorp/` and covers:

- all four kind-directories populated,
- a dependency chain 3 hops deep,
- one optional block (`sites/`) populated,
- `services_hosted` rewritten as `hosts` edges in the normalized output.
