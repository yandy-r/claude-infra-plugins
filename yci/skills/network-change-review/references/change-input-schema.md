# Change Input Schema

## Purpose

This document defines what `--change <path>` accepts as input to
`yci:network-change-review`. The path must point to a file that `parse-change.sh`
can read at skill invocation time. The script detects the shape of the change
automatically, normalizes it to a canonical JSON envelope, and emits that envelope
on stdout for downstream consumers (`derive-rollback.sh`, `build-check-catalogs.sh`,
the blast-radius reasoner, and `render-artifact.sh`). If detection fails, the
script exits with a structured error referencing the IDs in `./error-messages.md`.

---

## Supported Shapes

| Shape             | File extension(s)                  | Magic signature                                      | Notes                                                                                   |
| ----------------- | ---------------------------------- | ---------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `unified-diff`    | `*.patch`, `*.diff`, or any suffix | Lines matching `^--- a/` AND `^\+\+\+ b/` in order   | Standard `git diff` and `diff -u` output. Binary chunks (no textual diff) are rejected. |
| `structured-yaml` | `*.yaml`, `*.yml`                  | Top-level key `forward:` present (YAML, not comment) | Optional `reverse:` block. Missing `reverse:` triggers `ncr-rollback-missing-reverse`.  |
| `playbook`        | `*.yaml`, `*.yml`                  | Does not match `structured-yaml` (no `forward:` key) | Ansible playbooks and similar; `targets[]` confidence is `low`.                         |

Detection is ordered: unified-diff magic is tested first (extension-agnostic),
then YAML extension with `forward:` key, then YAML extension without it. A file
that does not match any shape exits with `ncr-diff-unsupported-shape`.

---

## Normalized JSON Shape

`parse-change.sh` emits exactly the following JSON object on stdout. Every
downstream script treats this envelope as its canonical input contract.

```json
{
  "diff_kind": "unified-diff | structured-yaml | playbook",
  "raw": "<original file contents as string>",
  "summary": "<one-line human-readable summary>",
  "targets": [{ "kind": "device | service | tenant | dependency | unknown", "id": "<string>" }]
}
```

Field semantics:

| Field       | Type            | Required | Description                                                                                                |
| ----------- | --------------- | -------- | ---------------------------------------------------------------------------------------------------------- |
| `diff_kind` | string (enum)   | yes      | One of `unified-diff`, `structured-yaml`, `playbook`. Drives rollback derivation and target resolution.    |
| `raw`       | string          | yes      | Verbatim UTF-8 content of the `--change` file. Passed through unchanged.                                   |
| `summary`   | string          | yes      | Single line synthesized by the parser (or taken from `change_summary` if `structured-yaml`).               |
| `targets`   | array of object | yes      | Resolved targets; may be empty only when confidence is `low` (playbook shape). See derivation rules below. |

Each `targets[]` element:

| Field  | Type          | Required | Allowed values                                             |
| ------ | ------------- | -------- | ---------------------------------------------------------- |
| `kind` | string (enum) | yes      | `device`, `service`, `tenant`, `dependency`, `unknown`     |
| `id`   | string        | yes      | Stable identifier from inventory (device name, FQDN, etc.) |

---

## How `targets[]` Is Derived

Target derivation is keyed by `diff_kind`.

### `unified-diff`

1. Scan `+++ b/<path>` header lines in the diff.
2. For each `<path>`, take the last two path segments (e.g., `routers/dc1-edge-01.conf`
   → `["routers", "dc1-edge-01.conf"]`).
3. Search the active inventory root (`$YCI_DATA_ROOT/inventories/<customer>/`) for
   any file whose name contains either segment as a substring. Which subdirectory the
   match lives under (`devices/`, `services/`, `tenants/`, …) determines `targets[].kind`
   (see `KIND_MAP` in `parse-change.sh`). The parser reads only the `id` field from the
   matched YAML record (falling back to the filename stem) — it does **not** read a
   `type` property from the inventory file.
4. If zero targets resolve across all `+++ b/` headers, exit with
   `ncr-targets-unresolvable`. The operator must either add explicit `targets:` (use
   a `structured-yaml` wrapper) or adjust the diff path naming to match inventory
   entries.

### `structured-yaml`

Read the `forward[].device`, `forward[].service`, and `forward[].tenant` fields from
each step in the `forward:` block. The `targets[]` list is the union of all non-null
values found across all steps. `kind` is taken directly from which field carried the
value (`device` → `kind: device`, `service` → `kind: service`, etc.). Confidence is
`high` because the operator explicitly listed targets.

### `playbook`

Perform a best-effort keyword scan: extract values from `hosts:` keys at any YAML
nesting level. Map each extracted host string to a `targets[]` entry with
`kind: unknown`. Confidence is `low`; `render-artifact.sh` will include a warning
callout in the emitted artifact. This path does NOT exit non-zero solely because
confidence is low — the artifact proceeds with an explicit warning. If zero hosts are
found, `targets[]` is empty and a `ncr-targets-unresolvable` warning is included in
the artifact (non-fatal when `diff_kind` is `playbook`).

---

## Failure Modes

| Error ID                       | When triggered                                                         | See                   |
| ------------------------------ | ---------------------------------------------------------------------- | --------------------- |
| `ncr-diff-unsupported-shape`   | File does not match any of the three supported shapes                  | `./error-messages.md` |
| `ncr-targets-unresolvable`     | `unified-diff` shape: zero inventory matches across all `+++ b/` paths | `./error-messages.md` |
| `ncr-rollback-missing-reverse` | `structured-yaml` shape: `forward:` present but `reverse:` absent      | `./error-messages.md` |

All error messages are emitted to stderr. The exit codes match the table in
`./error-messages.md` exactly — callers must not rely on the message text, only
the exit code and ID (printed on stderr as `[ncr-<id>]` prefix).

---

## Examples

### `unified-diff` example

File: `dc1-edge-mtu-change.patch`

```diff
--- a/routers/dc1-edge-01.conf
+++ b/routers/dc1-edge-01.conf
@@ -12,7 +12,7 @@
 interface GigabitEthernet0/0
-  mtu 1500
+  mtu 9000
   no shutdown
```

Normalized output (abbreviated):

```json
{
  "diff_kind": "unified-diff",
  "raw": "--- a/routers/dc1-edge-01.conf\n+++ b/routers/dc1-edge-01.conf\n...",
  "summary": "Modify dc1-edge-01.conf: 1 hunk, +1/-1 lines",
  "targets": [{ "kind": "device", "id": "dc1-edge-01" }]
}
```

### `structured-yaml` example

File: `mtu-change.yaml`

```yaml
change_id: WIDGET-CR-2026-0421-A
change_type: config
summary: Adjust MTU on primary edge router to 9000.
targets:
  - kind: device
    id: dc1-edge-01
forward:
  - device: dc1-edge-01
    op: set
    path: interfaces.GigabitEthernet0_0.mtu
    value: 9000
reverse:
  - device: dc1-edge-01
    op: set
    path: interfaces.GigabitEthernet0_0.mtu
    value: 1500
```

Normalized output:

```json
{
  "diff_kind": "structured-yaml",
  "raw": "change_id: WIDGET-CR-2026-0421-A\n...",
  "summary": "Adjust MTU on primary edge router to 9000.",
  "targets": [{ "kind": "device", "id": "dc1-edge-01" }]
}
```

### `playbook` example

File: `deploy-ntp.yaml` (Ansible playbook — no `forward:` key)

```yaml
- name: Deploy NTP config
  hosts: dc1-edge-01
  tasks:
    - name: Set NTP server
      template:
        src: ntp.conf.j2
        dest: /etc/ntp.conf
```

Normalized output:

```json
{
  "diff_kind": "playbook",
  "raw": "- name: Deploy NTP config\n  hosts: dc1-edge-01\n...",
  "summary": "Playbook: Deploy NTP config (1 play, confidence: low)",
  "targets": [{ "kind": "unknown", "id": "dc1-edge-01" }]
}
```

---

## See Also

- `./rollback-derivation.md` — rollback plan derivation rules keyed on `diff_kind`
- `./error-messages.md` — canonical catalog of all `ncr-*` error IDs and exit codes
- `./composition-contract.md` — how `parse-change.sh` output flows into composed skills
