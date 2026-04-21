# Netbox Inventory Adapter — STUB

**Status**: interface-only. Not implemented.

The `netbox` adapter for `yci:blast-radius` is not yet implemented. Only the
`file` adapter ships in Phase 0. This file exists to:

1. Lock in the directory convention for inventory adapters
   (`yci/skills/_shared/inventory-adapters/<name>/`) — mirroring the
   compliance-adapter pattern described in PRD §5.3.
2. Document the interface a `netbox` adapter implementation will have to
   honour when it lands.

## Interface contract

A conformant inventory adapter MUST:

1. Be invocable from `yci:blast-radius` as `bash <adapter-root>/adapter-<name>.sh <args…>`.
2. Emit a single JSON object to stdout with keys matching the normalized
   inventory shape defined in
   [`../../../blast-radius/references/file-adapter-layout.md`](../../../blast-radius/references/file-adapter-layout.md)
   §"Normalization output":
   `{ adapter, root, tenants, services, devices, sites, dependencies }`.
3. Honour the exit-code convention:
   - 0 success
   - 1 source problem (unreachable, unauthorised)
   - 2 schema violation (fetched data does not match the normalized shape)
   - 3 runtime error (required tooling missing)
4. Accept its configuration from the loaded customer profile
   (`inventory.endpoint`, `inventory.credential_ref`, `inventory.path`) — the
   calling skill resolves these and passes them as arguments. The adapter
   script itself must NOT re-read the profile.
5. Fail closed if any required profile field is missing.

## Planned Netbox mapping (sketch)

| Netbox concept                                | Normalized output target                       |
| --------------------------------------------- | ---------------------------------------------- |
| `dcim.device`                                 | `devices[]`                                    |
| `dcim.site`                                   | `sites[]`                                      |
| `tenancy.tenant`                              | `tenants[]`                                    |
| `ipam.service`                                | `services[]` (if Netbox has service modelling) |
| custom relationships → `dependencies[]` edges |                                                |

## Blocker

Requires a production Netbox fixture for deterministic tests. Tracked for
Phase 1 once a consenting customer / lab instance is available.
