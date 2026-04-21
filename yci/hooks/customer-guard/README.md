# yci customer-guard hook — Operator Reference

## Purpose

The `customer-guard` hook is a `PreToolUse` security control that intercepts every
Claude Code tool call (matcher `"*"`) and blocks cross-customer path access and
identifier leakage before a tool can act on them. It enforces the zero-cross-customer-leaks
invariant described in the yci PRD §10 non-negotiables: each customer's artifact root,
vault, inventory, and network identifiers must remain isolated from every other customer's
data, and a breach is non-negotiable grounds for aborting the tool call. The hook resolves
the active customer profile via the 4-tier precedence chain, checks every candidate path
and token in the tool input against all other loaded customer profiles, and emits a
structured decision JSON that Claude Code enforces as allow or deny.

What this hook does NOT do: it does not redact tool output (that is the P0.3 telemetry
sanitizer, tracked as a separate deliverable); it does not enforce authorization or scope
restrictions on what the operator may request (that is the P0.4 scope-gate); and it does
not intercept tools outside Claude Code — Cursor, Codex, and opencode have advisory stubs
only (see [references/capability-gaps.md](references/capability-gaps.md)).

## Install Check

Confirm the yci plugin is enabled and the hook is wired before relying on it in a
production engagement.

```bash
# Confirm yci plugin is enabled in Claude Code
claude plugins list | grep yci

# Confirm hook.json is registered in plugin.json
python3 -c "
import json
with open('<path-to-yci-plugin>/.claude-plugin/plugin.json') as f:
    print(json.load(f).get('hooks'))
"
# Expect: "hooks/customer-guard/hook.json"
```

For a live sanity check that proves the hook runs against a real tool-call payload,
use the supported operator-facing command:

```bash
/yci:guard-check <path-or-text>
```

This invokes the hook against a synthetic PreToolUse payload containing the supplied
path or text and prints the decision JSON plus any deny reason. Pass a path you know
belongs to the active customer (expect allow) and a path belonging to a different
customer (expect deny) to confirm both directions.

To invoke the hook script directly against a hand-crafted payload for deeper
inspection:

```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"/path/to/test"}}' \
  | bash yci/hooks/customer-guard/scripts/pretool.sh
```

If the hook exits non-zero or prints no JSON, run `./scripts/validate.sh --only yci`
to check the full yci installation status.

## False-positive Triage Workflow

When the hook blocks a tool call the operator intended to allow, follow these steps
in order:

1. **Re-run with dry-run mode** to confirm the would-block reason without
   actually denying the call:

   ```bash
   YCI_GUARD_DRY_RUN=1 <re-issue the failing tool call or script invocation>
   ```

   The hook emits a `guard-dry-run-would-block` banner to stderr and writes an
   audit entry, then allows the call. The banner includes the collision category
   and the matched path or token.

2. **Inspect the audit log** for the full structured reason (includes the resolved
   path and the matched token or fingerprint entry):

   ```
   <data-root>/.cache/customer-isolation/audit.log
   ```

   Each entry records the active customer, the foreign customer matched, the
   collision category (`path` or `fingerprint`), the offending value, and the
   resolved path.

3. **Decide**: is this a genuine cross-customer leak (abort and route the tool call
   correctly) or a legitimate cross-reference? Legitimate cross-references are rare —
   examples include a shared Dropbox folder managed by the active customer but
   named after a second customer, or a secondary DNS alias in the active customer's
   profile that resolves to an IP also registered in another profile.

4. **If legitimate**, add the minimal entry to the active customer's allowlist YAML
   with a mandatory `note:` field citing the specific SOW or ticket authorizing the
   cross-reference:

   ```
   <data-root>/profiles/<active-customer>.allowlist.yaml
   ```

   See [Allowlist YAML Schema](#allowlist-yaml-schema) below for the exact format.

5. **Re-run without dry-run** to confirm the tool call now proceeds:

   ```bash
   # unset dry-run (or ensure YCI_GUARD_DRY_RUN is unset)
   <re-issue the tool call>
   ```

   The hook should emit an allow decision. Verify via `/yci:guard-check <path-or-token>`.

6. **If the legitimate cross-reference is expected to recur**, upgrade the allowlist
   entry's `note:` from an ad-hoc comment to a stable ticket reference (not a
   "temp unblock" placeholder). Entries with vague notes are targets for the
   upcoming allowlist validator (see [Security Note](#security-note)).

## Allowlist YAML Schema

Per-tenant allowlist files live at `<data-root>/profiles/<customer>.allowlist.yaml`.
A global allowlist at `<data-root>/allowlist.yaml` applies to all customers; the
per-tenant file merges with the global one at evaluation time, with per-tenant entries
taking precedence on overlapping tokens.

```yaml
# <data-root>/profiles/acme.allowlist.yaml
#
# Per-tenant allowlist for the 'acme' customer profile. Entries here let
# specific paths / tokens bypass the cross-customer guard WITHOUT changing the
# default posture. Every entry MUST include a `note:` citing the SOW or ticket
# authorizing the cross-reference.
#
# Two equivalent forms are accepted; pick whichever reads better for the
# engagement. See below for the strict flat form that supports `note:` today
# (the dict-of-lists form uses YAML comments for the note until the loader
# grows a richer schema).

# Form 1 — dict-of-lists (notes as YAML comments; loader-compatible today)
paths:
  - /shared/acme/dropbox/cross-customer-export/ # SOW-2026-0117 §4.2 — monthly handoff to Bigbank-managed Dropbox

tokens:
  hostname:
    - bb01.bigbank.corp # ticket JIRA-8812 — acme-managed Bigbank secondary DNS, 30-day temp
  ipv4:
    - 10.2.2.2 # same as above


# Form 2 — flat list-of-dicts (native `note:` field; also loader-compatible)
# tokens:
#   - category: hostname
#     token: bb01.bigbank.corp
#     note: "ticket JIRA-8812 — acme-managed Bigbank secondary DNS, 30-day temp"
#   - category: ipv4
#     token: 10.2.2.2
#     note: "same as above"
```

**`paths:`** — A list of absolute paths. Match is a prefix comparison after `realpath`
normalization on both the candidate path and the allowlist entry. Symlinks on both sides
are resolved before comparison.

**`tokens:`** — A dict-of-lists keyed on fingerprint category matching the categories
defined in `references/fingerprint-rules.md`: `ipv4`, `ipv6`, `hostname`, `asn`,
`sow-ref`, `credential-ref`, `customer-id`. Alternatively, use the flat list-of-dicts
form:

```yaml
tokens:
  - category: hostname
    token: bb01.bigbank.corp
    note: 'ticket JIRA-8812 — acme-managed Bigbank secondary DNS'
```

Both forms are accepted. The dict-of-lists form is preferred for readability when
multiple tokens share a category.

**`note:`** — Required on every entry. Operator discipline today; a future validator
will flag missing notes as errors. The note must cite a specific SOW section or
ticket number, not a generic description.

**Global vs. per-tenant**: The global allowlist at `<data-root>/allowlist.yaml` uses
the same schema. It is evaluated first; per-tenant entries are merged in and take
precedence when both files contain an entry for the same token or path prefix.

## Error Reference

The hook emits structured deny reasons using catalogued error IDs. Every deny message
routes through the catalog — no ad-hoc strings. When the hook exits non-zero or emits
an unexpected message, cross-reference the ID against the catalog for the full message
template, producer script, exit code, and test coverage.

See [references/error-messages.md](references/error-messages.md) for the full catalog
with messages and test coverage.

- `guard-no-active-customer` — resolver refused + fail-closed default
- `guard-profile-load-failed` — profile YAML unparseable
- `guard-path-collision` — candidate path resolves under another customer's artifact root
- `guard-fingerprint-collision` — candidate token matches another customer's fingerprint bundle
- `guard-allowlist-malformed` — allowlist YAML parse failure
- `guard-dry-run-would-block` — dry-run active; would-be block logged
- `guard-missing-tool-input` — stdin JSON missing expected fields; fail-open default
- `guard-symlink-escape` — symlink inside active dir resolves under a foreign root

## Capability Gaps

Cross-target hook support varies. See [references/capability-gaps.md](references/capability-gaps.md)
for the per-target verdict. As of Phase 1, only Claude Code ships a functional hook;
Cursor / Codex / opencode stubs are advisory-only.

## Security Note

> **Every allowlist entry is a waiver of a security control.** Do NOT paste in
> entries that "just make the warnings go away" — each one should cite a specific
> SOW or ticket authorizing the cross-reference.
>
> A future validator tightening will flag allowlist entries without a `note:` field
> as errors. Relaxing the default posture (allow-by-default) is non-negotiably out
> of scope per the yci PRD.
