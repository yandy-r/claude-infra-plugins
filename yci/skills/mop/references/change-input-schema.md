# yci:mop Change Input Schema

`yci:mop` accepts four input families in V1.

## 1. Unified diff

- Detect by `--- a/...` and `+++ b/...` headers.
- Intended for repo-managed or file-managed configuration changes.
- Apply block is rendered as a `git apply` workflow.
- Rollback is derived mechanically by reversing the diff.

## 2. Structured YAML

Top-level mapping with at least:

```yaml
change_id: EXAMPLE-CR-001
summary: Enable feature X on edge-01.
targets:
  - kind: device
    id: edge-01
forward:
  - device: edge-01
    cli: |
      feature x
reverse:
  - device: edge-01
    cli: |
      no feature x
```

- `reverse:` is mandatory for rollback derivation.
- `targets:` is optional but strongly recommended; otherwise target extraction
  falls back to the `forward:` block.

## 3. Terraform plan JSON

- Detect by JSON with `format_version` and `resource_changes`.
- Intended shape: output from `terraform show -json`.
- Apply block is rendered as a plan verification + `terraform apply tfplan`
  workflow.
- Rollback is derived as a pre-state snapshot restore workflow plus resource-
  specific fast paths where the plan provides enough information.

## 4. Vendor CLI text

Plaintext file with required header comments:

```text
# vendor: iosxe
# summary: Raise MTU on edge-01 uplink
# change_id: EDGE-CR-001
# target: device=edge-01
interface GigabitEthernet0/0
 mtu 9000
```

Supported vendors in V1:

- `iosxe`
- `panos`

Supported `target:` forms:

- `device=<id>`
- `service=<id>`
- `tenant=<id>`

The command body starts at the first non-comment line. Header comments are not part
of the rendered apply block or rollback derivation.
