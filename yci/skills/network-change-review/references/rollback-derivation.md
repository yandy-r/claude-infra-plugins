# Rollback Derivation Design

## 1. Purpose

This document defines the reversal rules per diff shape that `derive-rollback.sh`
must implement. Auto-derivation of rollback plans is required by issue #32 AC4
("Rollback plan auto-derived by reversing the diff"). Mechanical reversal is the
default and preferred path; manual derivation is acceptable **only** when flagged by
a `confidence: low` marker so the operator sees the warning before applying the
rollback. The script must never silently produce a rollback plan it cannot verify is
correct — failing loud is safer than failing quiet.

---

## 2. Supported `diff_kind` Values

The script determines `diff_kind` by inspecting the raw input file before any
reversal logic runs. Detection order matters: check `unified-diff` first (byte-level
markers), then `structured-yaml`, then `structured-yaml-no-reverse`, then
`playbook`, then `unknown`.

| `diff_kind`                  | Detection                                                                        | Reversal strategy                     | Confidence |
| ---------------------------- | -------------------------------------------------------------------------------- | ------------------------------------- | ---------- |
| `unified-diff`               | File contains `^--- a/` + `^\+\+\+ b/` + `^@@` hunk markers                      | Mechanical reversal (see section 3)   | `high`     |
| `structured-yaml`            | `yaml.safe_load` yields a dict with top-level `forward:` **and** `reverse:` keys | Emit `reverse:` block verbatim        | `high`     |
| `structured-yaml-no-reverse` | `yaml.safe_load` yields a dict with `forward:` but **no** `reverse:` key         | Error: `ncr-rollback-missing-reverse` | n/a        |
| `playbook`                   | YAML or Jinja with no `forward:`/`reverse:` structure (e.g., Ansible playbook)   | Stub + manual derivation marker       | `low`      |
| `unknown`                    | None of the above                                                                | Error: `ncr-diff-unsupported-shape`   | n/a        |

---

## 3. Unified-Diff Reversal Algorithm

The mechanical reversal for `unified-diff` inputs proceeds in five steps.

**Step 1 — Parse into file diffs.**
Split the input on `^---` boundaries. Each segment is one file diff consisting of:

- A header pair: `--- a/<path>` and `+++ b/<path>`.
- One or more hunks, each beginning with a `@@ -<s>,<c> +<s>,<c> @@` marker.

**Step 2 — Swap header paths.**
Exchange the paths in the `---` and `+++` lines:

- `--- a/X` becomes `--- a/X` (the `a/` side now receives the original `b/` path).
- `+++ b/X` becomes `+++ b/X` (the `b/` side now receives the original `a/` path).

Concretely: if the forward diff reads `--- a/foo` / `+++ b/foo`, the reversed diff
reads the same (for in-place edits). For file creation/deletion cases (§ gotchas),
`/dev/null` swaps with the real path.

**Step 3 — Flip hunk lines.**
For each hunk:

- Every line beginning with `+` becomes `-`.
- Every line beginning with `-` becomes `+`.
- Lines beginning with a space (context lines) are unchanged.

After flipping, recompute the hunk header counts from the resulting content:

- `old_count` = number of `-` lines + number of context lines in the flipped hunk.
- `new_count` = number of `+` lines + number of context lines in the flipped hunk.
- `old_start` and `new_start` are derived from the original hunk positions adjusted
  for the flip. The simplest correct approach is to reparse the hunk line-by-line
  after flipping and recount.

**Step 4 — Reverse hunk order (optional, cosmetic).**
Reversing the sequence of hunks within each file diff so they appear bottom-to-top
produces a rollback that reads more naturally as "undo". The patch semantics are
identical either way. Implementations SHOULD reverse hunk order for readability but
MAY skip it.

**Step 5 — Re-emit as unified diff.**
Write the reversed file diffs to stdout in the same unified-diff format. The output
must be parseable by `patch -R` applied to the original (un-changed) files.

### Round-Trip Property

`reverse(reverse(diff)) == diff` modulo optional hunk-order reversal and
insignificant trailing whitespace. This property **must** be exercised by a unit
test (step 5.2 in the implementation plan will own this test). Any implementation
that violates the round-trip property is incorrect.

### Known Gotchas

**File creation / deletion.**
A new-file diff uses `--- /dev/null` (old side) and `+++ b/<path>` (new side), with
all hunk lines prefixed `+`. Reversal must:

- Swap: `--- a/<path>` / `+++ /dev/null` (becomes a deletion).
- Flip all `+` → `-`.

A deletion diff uses `--- a/<path>` / `+++ /dev/null`, with all `-` lines. Reversal
must:

- Swap: `--- /dev/null` / `+++ b/<path>` (becomes a creation).
- Flip all `-` → `+`.

Failing to handle `/dev/null` correctly turns a file-create rollback into a
no-op (patching `/dev/null` succeeds silently and the file remains).

**Empty hunks.**
Zero-line change hunks are not produced by standard `diff -u` output but may appear
in vendor-generated or hand-edited diffs. Preserve them verbatim — do not skip or
collapse.

**Binary diffs.**
Lines matching `Binary files a/<X> and b/<Y> differ` cannot be mechanically
reversed. Detect this pattern and fail with `ncr-rollback-binary-unsupported` (exit
non-zero) — do not emit a fake mechanical rollback.

---

## 4. Structured-YAML Reversal

Change-input authors who supply structured YAML **must** include an explicit
`reverse:` block alongside every `forward:` block. When `reverse:` is present,
`derive-rollback.sh` emits it verbatim as the rollback plan body — no inference
required.

```yaml
forward:
  - action: set_mtu
    device: dc1-edge-01
    interface: ge-0/0/0
    value: 9000
reverse:
  - action: set_mtu
    device: dc1-edge-01
    interface: ge-0/0/0
    value: 1500
```

When `reverse:` is **absent**, the script errors immediately:

```
error: ncr-rollback-missing-reverse
input: <path>
message: structured-yaml change file has a 'forward' block but no 'reverse' block.
         Add a 'reverse:' section or supply a unified diff instead.
```

Exit code 1. Do NOT attempt to infer the reverse from the `forward:` block.

---

## 5. Ambiguous / Playbook Handling

When the input is detected as **`playbook`**, emit this stub to stdout and exit 0
(the artifact is valid but low-confidence; the warning is surfaced via the
`confidence: low` marker and stderr `ncr-rollback-ambiguous`, not via a non-zero exit):

```
# ROLLBACK PLAN — MANUAL DERIVATION REQUIRED

No mechanical inverse is available for this change shape. The operator must
supply or derive the rollback steps manually before proceeding.

Confidence: low
Detected shape: playbook
Input: <path>
```

When the input is detected as **`unknown`**, do **not** emit this stub with exit 0.
`derive-rollback.sh` MUST exit non-zero with `ncr-diff-unsupported-shape` (see §2 and
`error-messages.md`) — the same fatal contract as `parse-change.sh` for unsupported
shapes.

The literal string `MANUAL DERIVATION REQUIRED` must appear verbatim for **playbook**
stubs so that downstream tooling (e.g., `render-artifact.sh`) can grep for it as a
sentinel. Do **not** fabricate steps. Do **not** guess at device state.

---

## 6. Confidence Levels

| Level    | Meaning                                                                                                                                         |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `high`   | Mechanical reversal is exact: `unified-diff` processed per §3, or `structured-yaml` with an explicit `reverse:` block.                          |
| `medium` | Reserved for future cases where partial inference produces a likely-correct-but-unverified reverse. Not currently used.                         |
| `low`    | Manual derivation required: `playbook` or binary diff (stub). `unknown` is **not** low-confidence — it is fatal (`ncr-diff-unsupported-shape`). |

The `render-artifact.sh` renderer **must** surface `confidence: low` as a visible
warning callout in the generated artifact (bolded block or highlighted admonition).
This constraint is cross-referenced in `./artifact-template.md` under the
"Rollback Confidence" section.

---

## 7. Error IDs (Canonical Catalog — Cross-Reference Only)

The canonical error catalog with full message text, exit codes, and remediation
guidance lives in `./error-messages.md`. The IDs relevant to rollback derivation are:

- `ncr-rollback-ambiguous` — low-confidence **playbook** stub emitted (stderr warning; exit 0)
- `ncr-rollback-missing-reverse` — structured YAML has `forward:` but no `reverse:`
- `ncr-diff-unsupported-shape` — input did not match any known `diff_kind`
- `ncr-rollback-binary-unsupported` — binary diff cannot be mechanically reversed

---

## 8. Examples

### Example A — Unified Diff

**Input (forward diff):**

```diff
--- a/configs/edge-01.yaml
+++ b/configs/edge-01.yaml
@@ -1,3 +1,3 @@
 hostname: dc1-edge-01
-mtu: 1500
+mtu: 9000
 bgp_asn: 64512
```

**Reversed output (rollback):**

```diff
--- a/configs/edge-01.yaml
+++ b/configs/edge-01.yaml
@@ -1,3 +1,3 @@
 hostname: dc1-edge-01
-mtu: 9000
+mtu: 1500
 bgp_asn: 64512
```

The `@@ -1,3 +1,3 @@` header is unchanged because the line counts are symmetric
(1 removed, 1 added, 1 context on each side). The `-` and `+` payload lines are
swapped; the context line (`hostname:` and `bgp_asn:`) is unchanged.

### Example B — Structured YAML with `reverse:`

**Input:**

```yaml
change_id: WIDGET-CR-2026-0421-A
forward:
  - action: set_mtu
    device: dc1-edge-01
    interface: ge-0/0/0
    value: 9000
reverse:
  - action: set_mtu
    device: dc1-edge-01
    interface: ge-0/0/0
    value: 1500
```

**Derived rollback plan (emitted verbatim from `reverse:` block):**

```yaml
- action: set_mtu
  device: dc1-edge-01
  interface: ge-0/0/0
  value: 1500
```

`confidence: high` — the `reverse:` block was explicitly declared by the
change-input author; no inference was performed.

---

## 9. See Also

- [`./composition-contract.md`](./composition-contract.md) — how `derive-rollback.sh` fits into the `yci:network-change-review` composition pipeline
- [`./change-input-schema.md`](./change-input-schema.md) — full schema for the change-input file, including `forward:`/`reverse:` field definitions
- [`./error-messages.md`](./error-messages.md) — canonical error catalog with exit codes and remediation guidance
- [`./artifact-template.md`](./artifact-template.md) — artifact rendering contract, including the `confidence: low` warning callout rule
