# Plan: yci customer-guard PreToolUse Hook (Cross-Customer Isolation)

## Summary

Build `yci/hooks/customer-guard/` — a load-bearing PreToolUse hook that blocks any tool call, artifact write, or string input referencing a customer different from the active profile. Detection lives in a standalone library at `yci/skills/_shared/customer-isolation/` (Python extractors + Bash orchestrator) so it can be reused by a slash command and future hooks. Claude Code ships a real blocking hook registered via the plugin manifest; Cursor / Codex / opencode ship documented capability gaps, mirroring the anti-parity pattern from `ycc:hooks-workflow`.

## User Story

As a consultant running the `yci` plugin across multiple customer engagements, I want any accidental reference to a different customer's artifacts, inventory, credentials, or identifiers to be blocked before the tool call executes — so that the load-bearing non-negotiable "zero cross-customer leaks" from the `yci` PRD is enforced by the runtime, not by operator discipline alone.

## Problem → Solution

**Current state**: `yci` can resolve the active customer via `resolve-customer.sh` (4-tier precedence), but there is no runtime enforcement preventing a tool call from reading / writing / referencing another customer's data. A typo or paste in a shared session can leak customer A's hostnames into customer B's deliverable before the operator notices.

**Desired state**: every Claude Code tool call passes through a PreToolUse hook that resolves the active customer, extracts paths and identifier tokens from the tool input, intersects them against every other customer's canonical artifact roots and inventory fingerprints, and blocks with a catalogued, actionable error on collision. False positives are mitigated by a per-tenant allowlist and a dry-run mode. Cursor / Codex / opencode gaps are documented, not faked.

## Metadata

- **Complexity**: Large
- **Source PRD**: `docs/prps/prds/yci.prd.md`
- **PRD Phase**: Phase 1 — §6.1 P0.1 (load-bearing hook); §10 non-negotiables #1 + #2
- **Estimated Files**: ~25 new + 3 modified
- **Source Issue**: [#28 — yci: customer-guard PreToolUse hook (cross-customer isolation)](https://github.com/yandy-r/claude-plugins/issues/28)
- **Labels**: `type:feature`, `priority:high`, `phase:1`, `source:prd`, `feat:yci`

---

## Batches

Tasks grouped by dependency for parallel execution. Tasks within the same batch run concurrently; batches run in order.

| Batch | Tasks         | Depends On | Parallel Width |
| ----- | ------------- | ---------- | -------------- |
| B1    | 1.1, 1.2, 1.3 | —          | 3              |
| B2    | 2.1, 2.2, 2.3 | B1         | 3              |
| B3    | 3.1, 3.2      | B2         | 2              |
| B4    | 4.1, 4.2, 4.3 | B3         | 3              |
| B5    | 5.1           | B4         | 1              |
| B6    | 6.1, 6.2      | B5         | 2              |
| B7    | 7.1           | B6         | 1              |

- **Total tasks**: 15
- **Total batches**: 7
- **Max parallel width**: 3

---

## Worktree Setup

Per-task worktrees off a shared parent. Sequential tasks (5.1 and 7.1) run in the parent.

- **Parent**: `~/.claude-worktrees/claude-plugins-yci-customer-guard/` (branch: `feat/yci-customer-guard`)
- **Children**:
  - 1.1 → `~/.claude-worktrees/claude-plugins-yci-customer-guard-1-1/` (branch: `feat/yci-customer-guard-1-1`)
  - 1.2 → `~/.claude-worktrees/claude-plugins-yci-customer-guard-1-2/` (branch: `feat/yci-customer-guard-1-2`)
  - 1.3 → `~/.claude-worktrees/claude-plugins-yci-customer-guard-1-3/` (branch: `feat/yci-customer-guard-1-3`)
  - 2.1 → `~/.claude-worktrees/claude-plugins-yci-customer-guard-2-1/` (branch: `feat/yci-customer-guard-2-1`)
  - 2.2 → `~/.claude-worktrees/claude-plugins-yci-customer-guard-2-2/` (branch: `feat/yci-customer-guard-2-2`)
  - 2.3 → `~/.claude-worktrees/claude-plugins-yci-customer-guard-2-3/` (branch: `feat/yci-customer-guard-2-3`)
  - 3.1 → `~/.claude-worktrees/claude-plugins-yci-customer-guard-3-1/` (branch: `feat/yci-customer-guard-3-1`)
  - 3.2 → `~/.claude-worktrees/claude-plugins-yci-customer-guard-3-2/` (branch: `feat/yci-customer-guard-3-2`)
  - 4.1 → `~/.claude-worktrees/claude-plugins-yci-customer-guard-4-1/` (branch: `feat/yci-customer-guard-4-1`)
  - 4.2 → `~/.claude-worktrees/claude-plugins-yci-customer-guard-4-2/` (branch: `feat/yci-customer-guard-4-2`)
  - 4.3 → `~/.claude-worktrees/claude-plugins-yci-customer-guard-4-3/` (branch: `feat/yci-customer-guard-4-3`)
  - 6.1 → `~/.claude-worktrees/claude-plugins-yci-customer-guard-6-1/` (branch: `feat/yci-customer-guard-6-1`)
  - 6.2 → `~/.claude-worktrees/claude-plugins-yci-customer-guard-6-2/` (branch: `feat/yci-customer-guard-6-2`)

---

## UX Design

### Before

```
$ yci-active = acme
$ <tool>: Read { file_path: "~/data/bigbank/inventory.yaml" }
→ (silently succeeds — cross-customer leak into active session)
```

### After

```
$ yci-active = acme
$ <tool>: Read { file_path: "~/data/bigbank/inventory.yaml" }
→ PreToolUse hook: DENY (guard-path-collision)
   reason: active customer is 'acme', path resolves under 'bigbank's
           inventory root (~/data/inventories/bigbank/).
           To bypass, add to ~/data/profiles/acme.allowlist.yaml with
           a `note:` citing the SOW or ticket authorizing it.
```

### Interaction Changes

| Touchpoint            | Before                        | After                                                                                                          | Notes                                                          |
| --------------------- | ----------------------------- | -------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| Every Claude tool     | No guard; operator discipline | PreToolUse hook evaluates every call                                                                           | Hook matcher is `"*"` — applies globally when `yci` is enabled |
| Cross-customer Read   | Silently succeeds             | Blocked with `guard-path-collision`                                                                            | Canonical-form path compare rejects `/acme` vs `/acme-inc`     |
| Fingerprint collision | Silently succeeds             | Blocked with `guard-fingerprint-collision`                                                                     | Hostname / IP / SOW-ref / AS / credential-ref scanning         |
| False positive        | N/A                           | Add to `<data-root>/profiles/<active>.allowlist.yaml`                                                          | Must cite SOW/ticket in `note:` field                          |
| Profile not loaded    | No enforcement                | Default fail-closed with `guard-no-active-customer`; `YCI_GUARD_FAIL_OPEN=1` opt-in softens                    | Documented as security-reducing knob                           |
| Dry-run               | N/A                           | `YCI_GUARD_DRY_RUN=1` logs would-be blocks to `<data-root>/.cache/customer-isolation/audit.log`, exits 0 allow | Banner on stderr every invocation                              |
| `/yci:guard-check`    | N/A                           | New ad-hoc slash command wrapping `detect.sh`                                                                  | Manual pre-check for pastes                                    |

---

## Mandatory Reading

| Priority       | File                                                        | Lines                  | Why                                                                                                                 |
| -------------- | ----------------------------------------------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------- |
| P0 (critical)  | `docs/prps/prds/yci.prd.md`                                 | §6.1 P0.1, §10 #1 + #2 | The hook's scope, threat model, and non-negotiables                                                                 |
| P0 (critical)  | `yci/skills/customer-profile/scripts/resolve-customer.sh`   | all                    | The function the hook calls to get the active customer; exit semantics                                              |
| P0 (critical)  | `yci/skills/customer-profile/scripts/load-profile.sh`       | all                    | How profiles + path overrides are resolved — the extractor must match                                               |
| P0 (critical)  | `ycc/skills/_shared/references/target-capability-matrix.md` | HOOKS rows             | Authoritative per-target hook support verdicts                                                                      |
| P1 (important) | `yci/skills/customer-profile/references/error-messages.md`  | all                    | Error catalog style the new `error-messages.md` must mirror                                                         |
| P1 (important) | `yci/skills/customer-profile/tests/helpers.sh`              | 1-195                  | Test harness (`assert_error_id`, `with_sandbox`) duplicated into new suites                                         |
| P1 (important) | `yci/skills/customer-profile/tests/run-all.sh`              | all                    | Test-runner convention for each tests/ dir                                                                          |
| P1 (important) | `ycc/settings/hooks/worktree-create.sh`                     | all                    | Claude Code hook stdin-JSON pattern (worktree hook uses plaintext stdout; PreToolUse uses JSON — adapt)             |
| P1 (important) | `yci/CONTRIBUTING.md`                                       | all                    | yci scope guardrails; Non-Goals list; Phase-1 discipline                                                            |
| P2 (reference) | `ycc/skills/hooks-workflow/references/support-notes.md`     | all                    | Anti-parity phrasing — "yci refuses to fabricate config for an unsupported target" comes from this canonical stance |
| P2 (reference) | `yci/docs/profiles.md`                                      | all                    | Profile YAML shape + override chain the inventory loader must honor                                                 |
| P2 (reference) | `scripts/validate-yci-skills.sh`                            | 1-80                   | Validator pattern new sections must match                                                                           |
| P2 (reference) | `ycc/skills/_shared/references/worktree-strategy.md`        | all                    | Parent/child worktree format                                                                                        |

## External Documentation

| Topic                                   | Source                                              | Key Takeaway                                                                                               |
| --------------------------------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Claude Code hooks (PreToolUse decision) | https://docs.claude.com/en/docs/claude-code/hooks   | PreToolUse reads JSON from stdin and writes a decision JSON to stdout; `permissionDecision: "deny"` blocks |
| Claude Code plugin hooks registration   | https://docs.claude.com/en/docs/claude-code/plugins | Plugins can register hooks via a `hooks` key in `plugin.json`                                              |
| `realpath -m` portability               | POSIX / GNU coreutils / BSD man pages               | `-m` is GNU-only; BSD/macOS needs a Python fallback                                                        |

---

## Patterns to Mirror

Code patterns discovered in the codebase. Follow these exactly.

### NAMING_CONVENTION (shell scripts)

```bash
# SOURCE: yci/skills/customer-profile/scripts/resolve-customer.sh:1-18
#!/usr/bin/env bash
# yci — <one-line purpose>.
#
# <body docstring with Usage / Stdout / Stderr / Exit contract>.

set -euo pipefail
```

New `pretool.sh`, `decision-json.sh`, extractors, `detect.sh`, etc. all open with the same shebang + `set -euo pipefail` + contract docstring. Sourceable libraries (`detect.sh`, `path-match.sh`, `allowlist.sh`) OMIT the `set -euo pipefail` at file scope — same convention as `state-io.sh`. The docstring is mandatory; `validate-yci-skills.sh` style grep is fine to read.

### ERROR_CATALOG_STYLE (reference docs)

```markdown
### `guard-path-collision`

- **ID**: `guard-path-collision`
- **Producer**: `pretool.sh`
- **Exit code**: 0 (hook emits deny via decision JSON; script itself exits 0)
- **Trigger**: a path extracted from the PreToolUse payload resolves
  (after symlink + realpath) under another customer's canonical artifact root.
- **Message**:
```

yci guard: cross-customer path collision.
active customer: '<active>'
foreign customer: '<foreign>' (matched on root: <root>)
offending path: <path>
resolved to: <resolved>
To bypass, add '<path>' to <data-root>/profiles/<active>.allowlist.yaml
under `paths:`, with a `note:` citing the SOW or ticket authorizing it.

```
- **Test coverage**: `test_pretool_deny_path.sh::test_path_collision`
```

Same shape as `yci/skills/customer-profile/references/error-messages.md` so `assert_error_id` works unchanged.

### ERROR_HANDLING (stderr + exit)

```bash
# SOURCE: yci/skills/customer-profile/scripts/resolve-customer.sh:107-128
yci_emit_refusal() {
    local data_root="$1" env_status="$2"
    printf 'yci: no active customer.\n' >&2
    printf '  $YCI_CUSTOMER: %s\n' "$env_status" >&2
    # ... multi-line message — each arg on its own printf line ...
    printf 'Run `/yci:init <customer>` ...\n' >&2
}
```

Errors: named emit function, write to stderr with `printf >&2`, never interpolate user input without `%s`, end with an actionable hint line.

### HOOK_STDIN_READ (Claude Code)

```bash
# SOURCE: ycc/settings/hooks/worktree-create.sh:34-49
INPUT="$(cat)"
json_get() {
  local field="$1"
  if command -v jq &>/dev/null; then
    printf '%s' "$INPUT" | jq -r --arg f "$field" '.[$f] // empty'
  else
    printf '%s' "$INPUT" \
      | grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
      | head -1 \
      | sed 's/.*: *"\(.*\)"/\1/'
  fi
}
```

Always read stdin once into `INPUT` then extract. jq preferred; grep+sed fallback when unavailable. NOTE: `worktree-create.sh` writes plaintext stdout; `pretool.sh` writes JSON decision stdout. Adapt the input-read helper; do not copy the output format.

### TEST_STRUCTURE (bash test runner)

```bash
# SOURCE: yci/skills/customer-profile/tests/helpers.sh:1-50
#!/usr/bin/env bash
# Shared test helpers. Source this file from every test_*.sh.
# Do NOT set -euo here — tests handle their own failures.

YCI_TEST_PASS=0
YCI_TEST_FAIL=0
YCI_TEST_FILE="${BASH_SOURCE[1]##*/}"
```

Every test file sources `helpers.sh`, uses `assert_eq` / `assert_contains` / `assert_exit` / `assert_error_id`, wraps filesystem work in `with_sandbox`, ends with `yci_test_summary`. Duplicate the helpers.sh into each new tests/ directory (per repo rule: no cross-skill helper sharing).

### TEST_RUNNER_CONVENTION

```bash
# SOURCE: yci/skills/customer-profile/tests/run-all.sh:1-50
#!/usr/bin/env bash
set -uo pipefail  # intentional: no -e here

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "${TESTS_DIR}/helpers.sh"

# ... discover test_*.sh, run each in bash subshell, aggregate ...
[ "$fail" -eq 0 ]
```

Each new `tests/run-all.sh` follows this shape.

### VALIDATOR_SECTION

```bash
# SOURCE: scripts/validate-yci-skills.sh:24-44
validate_customer_profile_skill() {
    echo "--- customer-profile skill ---"
    local plugin_json="${REPO_ROOT}/yci/.claude-plugin/plugin.json"
    # ... if missing/invalid: fail ...; else: ok ...
}
```

Validator uses `fail` / `ok` / `warn` helpers, checks existence first, then structural validity, then behavioural (test run).

---

## Files to Change

| File                                                                        | Action | Justification                                                          |
| --------------------------------------------------------------------------- | ------ | ---------------------------------------------------------------------- |
| `yci/hooks/customer-guard/hook.json`                                        | CREATE | Claude Code plugin-native hook descriptor (PreToolUse matcher `"*"`)   |
| `yci/hooks/customer-guard/scripts/pretool.sh`                               | CREATE | Hook entrypoint: stdin JSON in, decision JSON out                      |
| `yci/hooks/customer-guard/scripts/decision-json.sh`                         | CREATE | Centralize Claude Code hook decision JSON shape + audit-log line       |
| `yci/hooks/customer-guard/README.md`                                        | CREATE | Operator-facing doc: purpose, verification, false-positive triage      |
| `yci/hooks/customer-guard/references/error-messages.md`                     | CREATE | Canonical error catalog (8 IDs)                                        |
| `yci/hooks/customer-guard/references/capability-gaps.md`                    | CREATE | Per-target hook capability matrix + ship path                          |
| `yci/hooks/customer-guard/references/tool-surface.md`                       | CREATE | Enumerates which Claude Code tools the hook inspects + fields          |
| `yci/hooks/customer-guard/targets/codex/codex-config-fragment.toml`         | CREATE | Advisory-only placeholder for Codex (unsupported target)               |
| `yci/hooks/customer-guard/tests/helpers.sh`                                 | CREATE | Integration-test helpers (duplicate of customer-profile pattern)       |
| `yci/hooks/customer-guard/tests/run-all.sh`                                 | CREATE | Integration-test runner                                                |
| `yci/hooks/customer-guard/tests/test_pretool_allow.sh`                      | CREATE | Baseline allow case                                                    |
| `yci/hooks/customer-guard/tests/test_pretool_deny_path.sh`                  | CREATE | Path-collision deny scenario                                           |
| `yci/hooks/customer-guard/tests/test_pretool_deny_fingerprint.sh`           | CREATE | Fingerprint-collision deny scenario                                    |
| `yci/hooks/customer-guard/tests/test_pretool_allowlist_pass.sh`             | CREATE | Allowlist entry bypasses guard                                         |
| `yci/hooks/customer-guard/tests/test_pretool_dry_run.sh`                    | CREATE | `YCI_GUARD_DRY_RUN=1` logs + allows                                    |
| `yci/hooks/customer-guard/tests/test_pretool_no_active_customer.sh`         | CREATE | Fail-closed default + fail-open opt-in                                 |
| `yci/hooks/customer-guard/tests/test_pretool_symlink_escape.sh`             | CREATE | Symlink-out-of-active-tree gets denied                                 |
| `yci/skills/_shared/customer-isolation/detect.sh`                           | CREATE | Public library API: `isolation_check_payload`                          |
| `yci/skills/_shared/customer-isolation/scripts/extract-paths.py`            | CREATE | Pull candidate paths from PreToolUse JSON                              |
| `yci/skills/_shared/customer-isolation/scripts/extract-tokens.py`           | CREATE | Pull candidate identifier tokens from PreToolUse JSON                  |
| `yci/skills/_shared/customer-isolation/scripts/inventory-fingerprint.py`    | CREATE | Build per-customer fingerprint bundle + cache                          |
| `yci/skills/_shared/customer-isolation/scripts/path-match.sh`               | CREATE | Canonical-form path-prefix containment                                 |
| `yci/skills/_shared/customer-isolation/scripts/allowlist.sh`                | CREATE | Load + query per-tenant allowlist files                                |
| `yci/skills/_shared/customer-isolation/references/fingerprint-rules.md`     | CREATE | What counts as a cross-customer identifier                             |
| `yci/skills/_shared/customer-isolation/tests/helpers.sh`                    | CREATE | Unit-test helpers (duplicate)                                          |
| `yci/skills/_shared/customer-isolation/tests/run-all.sh`                    | CREATE | Unit-test runner                                                       |
| `yci/skills/_shared/customer-isolation/tests/test_extract_paths.sh`         | CREATE | extract-paths.py coverage                                              |
| `yci/skills/_shared/customer-isolation/tests/test_extract_tokens.sh`        | CREATE | extract-tokens.py coverage                                             |
| `yci/skills/_shared/customer-isolation/tests/test_inventory_fingerprint.sh` | CREATE | inventory-fingerprint.py coverage                                      |
| `yci/skills/_shared/customer-isolation/tests/test_path_match.sh`            | CREATE | path-match.sh coverage                                                 |
| `yci/skills/_shared/customer-isolation/tests/test_allowlist.sh`             | CREATE | allowlist.sh coverage                                                  |
| `yci/skills/_shared/customer-isolation/tests/test_detect.sh`                | CREATE | detect.sh end-to-end library coverage                                  |
| `yci/skills/_shared/customer-isolation/tests/fixtures/` (directory)         | CREATE | Synthetic profiles + inventories + payloads for every test             |
| `yci/commands/guard-check.md`                                               | CREATE | `/yci:guard-check <path-or-text>` slash command                        |
| `yci/skills/customer-guard/SKILL.md`                                        | CREATE | Skill that `/yci:guard-check` invokes                                  |
| `yci/.claude-plugin/plugin.json`                                            | UPDATE | Add `"hooks": "hooks/customer-guard/hook.json"` registration           |
| `scripts/validate-yci-skills.sh`                                            | UPDATE | Add `validate_customer_guard_hook` + `validate_customer_isolation_lib` |
| `yci/CONTRIBUTING.md`                                                       | UPDATE | "Guard-hook discipline" subsection + non-goal about default-relaxation |

## NOT Building

- **Cursor / Codex / opencode functional hooks** — only breadcrumbs and advisory stubs. Real hook wiring for those targets is Phase 1b work.
- **Generator-fleet extension for yci** — `scripts/generate_*.py` stay ycc-only (PRD Phase-0 posture). Cross-target bundle emission is Phase 1a.
- **Automatic allowlist auto-approval** — every allowlist entry is operator-authored with a mandatory `note:` field; no programmatic bypass is added.
- **Default-relaxed guard** — flipping to allow-by-default is out of scope forever (PRD non-negotiable).
- **Telemetry sanitizer** — PRD P0.3 is tracked separately. The guard only blocks; it does not redact.
- **New ycc-side code** — cross-plugin helper sharing is not supported; we duplicate helpers into `yci/skills/_shared/` instead of consuming them from `ycc/`.
- **Integration against real Claude Code sessions in CI** — hook runner is environment-specific; we test the JSON stdin/stdout contract directly via subprocess.

---

## Step-by-Step Tasks

### Task 1.1: Error catalog — Depends on [none]

- **BATCH**: B1
- **WORKTREE**: `~/.claude-worktrees/claude-plugins-yci-customer-guard-1-1/`
- **ACTION**: Create `yci/hooks/customer-guard/references/error-messages.md`.
- **IMPLEMENT**: Write canonical catalog with exit-code table (0/1/2/3) and the following IDs in this order: `guard-no-active-customer` (exit 1; producer `pretool.sh`; trigger: resolver refused AND `YCI_GUARD_FAIL_OPEN` unset/0), `guard-profile-load-failed` (exit 2; producer `inventory-fingerprint.py`; trigger: active or foreign profile YAML unparseable), `guard-path-collision` (exit 0 + deny JSON; producer `pretool.sh`; trigger: candidate path resolves under another customer's canonical artifact root), `guard-fingerprint-collision` (exit 0 + deny JSON; producer `pretool.sh`; trigger: candidate token matches another customer's fingerprint bundle), `guard-allowlist-malformed` (exit 3; producer `allowlist.sh`; trigger: allowlist YAML parse fail), `guard-dry-run-would-block` (exit 0 + stderr banner; producer `pretool.sh`; trigger: `YCI_GUARD_DRY_RUN=1` + collision), `guard-missing-tool-input` (exit 0 + stderr warn; producer `pretool.sh`; trigger: stdin JSON missing expected keys; fail-open default, fail-closed under `YCI_GUARD_STRICT=1`), `guard-symlink-escape` (exit 0 + deny JSON; producer `pretool.sh`; trigger: path is inside active dir but `realpath` resolves under a foreign root). Each entry: ID, Producer, Exit code, Trigger, Message (fenced code block with `<placeholder>` syntax), Test coverage pointer. Include a Style Guide section (short, referencing the customer-profile one verbatim) + Test-Assertion Helpers section describing `assert_error_id` behaviour.
- **MIRROR**: `ERROR_CATALOG_STYLE` — exact shape of `yci/skills/customer-profile/references/error-messages.md` so `assert_error_id` works unchanged.
- **IMPORTS**: none (pure markdown).
- **GOTCHA**: `<placeholder>` tokens are stripped by `assert_error_id` before matching — the FIRST code-block line in each entry after `- **ID**:` is what the helper extracts, so keep distinctive free text there (not the placeholders alone).
- **VALIDATE**:
  - `wc -l yci/hooks/customer-guard/references/error-messages.md` → ≥ 120 lines
  - `grep -c '^### `' yci/hooks/customer-guard/references/error-messages.md` → 8
  - Markdown renders cleanly in a preview

### Task 1.2: Per-target capability-gaps doc — Depends on [none]

- **BATCH**: B1
- **WORKTREE**: `~/.claude-worktrees/claude-plugins-yci-customer-guard-1-2/`
- **ACTION**: Create `yci/hooks/customer-guard/references/capability-gaps.md`.
- **IMPLEMENT**: Open with a short preamble citing `ycc/skills/_shared/references/target-capability-matrix.md` as the authoritative source. For each of Claude / Cursor / Codex / opencode include a subsection with: (a) verdict copied verbatim from the HOOKS.PreToolUse row (e.g., "supported" / "partial" / "unsupported"), (b) what ships in this PR for that target, (c) what is deferred to which phase, (d) concrete file path of the advisory stub if applicable. Close with the sentence "yci refuses to fabricate config for an unsupported target." and a link to `ycc/skills/hooks-workflow/references/support-notes.md`. For Codex, create a matching advisory stub at `yci/hooks/customer-guard/targets/codex/codex-config-fragment.toml` whose ONLY content is a multi-line comment beginning `# Advisory only — Codex hooks under development; see capability-gaps.md for status.` (no executable TOML).
- **MIRROR**: Anti-parity stance from `ycc/skills/hooks-workflow/references/support-notes.md`.
- **IMPORTS**: none.
- **GOTCHA**: Do NOT invent Cursor `.mdc` or opencode TypeScript plugin files in THIS PR — only reference their future paths. The only runtime-visible target stub we ship is the Codex TOML placeholder, because its comment-only content is safe to drop in the generator bundle when Phase 1a lands.
- **VALIDATE**:
  - File exists and has 4 target subsections
  - Codex stub starts with `# Advisory only` as its first non-blank line
  - `grep -c 'yci refuses to fabricate' yci/hooks/customer-guard/references/capability-gaps.md` → ≥ 1

### Task 1.3: Fingerprint-rules reference — Depends on [none]

- **BATCH**: B1
- **WORKTREE**: `~/.claude-worktrees/claude-plugins-yci-customer-guard-1-3/`
- **ACTION**: Create `yci/skills/_shared/customer-isolation/references/fingerprint-rules.md` (and the parent directory).
- **IMPLEMENT**: Sections: (1) "What counts as a fingerprint" — enumerate per PRD §10 #2: `customer.id`, `customer.display_name`, `engagement.id`, `engagement.sow_ref`, hostnames / IPv4 / IPv6 / AS numbers / device serials from inventory files, path prefixes under each of `vaults.path` / `inventory.path` / `calendars.path` / `deliverable.path`, `credential_ref` strings. (2) "Generic-token whitelist" — `127.0.0.0/8`, `::1`, `0.0.0.0`, `localhost`, `example.com`, RFC-5737 (`192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`), RFC-3849 (`2001:db8::/32`). (3) "Minimum matching criteria" — hostnames must be ≥ 4 chars AND contain a dot OR appear in an inventory file explicitly; IP literals must pass CIDR validation via Python `ipaddress`; AS numbers must match `^AS\d+$` (case-insensitive); SOW refs require a customer-configurable prefix declared in the profile (fall back to `sow[-/ ]\d+`). (4) "Category regexes" — give a named regex for each category with a short rationale. (5) "Adding a new category" — one-paragraph process.
- **MIRROR**: None (new reference doc).
- **IMPORTS**: none.
- **GOTCHA**: Fingerprint rules are load-bearing for false-positive rate. Err toward UNDER-matching (miss some leaks) for generic-token edges like bare IPv4 literals, which would otherwise trigger on every `127.0.0.1` in a test config; the PRD prefers "clear actionable error" over "zero leaks at any operational cost" — subsequent passes tighten.
- **VALIDATE**:
  - File exists; 5 required sections present (grep for each heading)
  - Each category regex compiles (copy into a scratch `python3 -c "import re; re.compile(...)"` in validator later — not here)

### Task 2.1: Path extractor — Depends on [1.1, 1.2, 1.3]

- **BATCH**: B2
- **WORKTREE**: `~/.claude-worktrees/claude-plugins-yci-customer-guard-2-1/`
- **ACTION**: Create `yci/skills/_shared/customer-isolation/scripts/extract-paths.py`.
- **IMPLEMENT**: Python 3 script, reads PreToolUse JSON from `sys.argv[1]` (as path) OR from `stdin` when no argv. For each supported tool, emit absolute paths one-per-line on stdout.
  - Tool → fields read: `Read.file_path`, `Write.file_path`, `Edit.file_path`, `MultiEdit.file_path`, `NotebookEdit.notebook_path`, `Glob.path` (optional), `Grep.path` (optional), `Bash.command` (shlex-split with `posix=True`, cap 512 tokens, keep tokens that LOOK like paths: leading `/`, `~/`, `./`, `../`, or contain `/`), `WebFetch.url` (only when scheme is `file://` → emit path component), `Task.prompt` (secondary scan for path-like tokens via regex `[~./][\w./-]{2,}`).
  - For each candidate: expand `~` relative to `$HOME` (fallback: leave literal); if relative, resolve against `tool_input.cwd` when present, else `os.getcwd()`; apply `os.path.realpath` when the path exists, else `os.path.abspath`.
  - Emit truncation marker `truncated:paths:<count>` on stderr if Bash tokens exceed cap.
  - Always exit 0 (library layer — downstream decides policy).
- **MIRROR**: `NAMING_CONVENTION` at the top (shebang + docstring); style-match `yci/skills/customer-profile/scripts/*.py` if any exist, else PEP 8.
- **IMPORTS**: `import json, os, os.path, re, shlex, sys`; optionally `from pathlib import Path`.
- **GOTCHA**: `shlex.split` raises on unbalanced quotes — wrap in try/except and fall back to `re.split(r"\s+", cmd)` with a stderr warning; otherwise one malformed command takes the whole hook down. Don't `follow symlinks` in realpath when testing — actually `realpath` DOES follow symlinks, which is what we want for both path-match sides.
- **VALIDATE**:
  - `python3 -m py_compile yci/skills/_shared/customer-isolation/scripts/extract-paths.py`
  - Manual run: `echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' | python3 .../extract-paths.py` prints `/tmp/x`
  - Every supported tool type has at least one manual-run check documented in test_extract_paths.sh (task 4.1)

### Task 2.2: Fingerprint extractor — Depends on [1.1, 1.2, 1.3]

- **BATCH**: B2
- **WORKTREE**: `~/.claude-worktrees/claude-plugins-yci-customer-guard-2-2/`
- **ACTION**: Create `yci/skills/_shared/customer-isolation/scripts/extract-tokens.py`.
- **IMPLEMENT**: Python 3 script with same I/O convention as extract-paths. Walk the entire JSON recursively, collecting every string value; in addition, scan concatenated text from `Bash.command`, `Task.prompt`, `Edit.old_string`, `Edit.new_string`, `Write.content`, `MultiEdit.edits[*].old_string` + `new_string`. Cap total scanned content at 1 MiB (`sum(len(s) for s ...)`); truncate gracefully and emit `truncated:tokens:1` on stderr.
  - For each scanned string, apply every category regex from `fingerprint-rules.md` (compile once at module level): ipv4, ipv6, hostname, asn, sow-ref, credential-ref. Also emit raw string candidates that LOOK like customer ids (`^[a-z0-9][a-z0-9-]{2,63}$`) tagged `customer-id`.
  - Apply the generic-token whitelist from fingerprint-rules.md; filtered tokens do NOT appear on stdout.
  - Output format: `<category>\t<token>` (tab-separated), newline-delimited, deduped by (category, token).
  - Exit 0 always.
- **MIRROR**: Same docstring + imports pattern as 2.1.
- **IMPORTS**: `import ipaddress, json, re, sys` and a local `RULES` module loaded from the same directory if helpful (keep it a single file for simplicity).
- **GOTCHA**: Naïve hostname regex matches everything containing a dot — e.g., `file.txt`. Enforce TLD-ish last label via `re.compile(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$", re.I)` and a length floor of 4. Still tune via `fingerprint-rules.md` if tests flake.
- **VALIDATE**:
  - `python3 -m py_compile ...`
  - Manual: `echo '{"tool_name":"Write","tool_input":{"content":"10.0.0.1 bigbank.corp"}}' | python3 .../extract-tokens.py` prints two tagged tokens
  - Whitelist check: `127.0.0.1` and `localhost` must NOT appear

### Task 2.3: Inventory fingerprint loader — Depends on [1.1, 1.2, 1.3]

- **BATCH**: B2
- **WORKTREE**: `~/.claude-worktrees/claude-plugins-yci-customer-guard-2-3/`
- **ACTION**: Create `yci/skills/_shared/customer-isolation/scripts/inventory-fingerprint.py`.
- **IMPLEMENT**: CLI script: `inventory-fingerprint.py --data-root <path> --customer <id>`. Loads the customer's profile by invoking `yci/skills/customer-profile/scripts/load-profile.sh` via `subprocess.run(["bash", "<path-to-load-profile>", "--data-root", data_root, "--customer", cid, "--format", "json"], capture_output=True, check=True)` (confirm flag shape by reading load-profile.sh FIRST during implementation — adjust here if the real flags differ).
  - Resolve every path override (`vaults.path`, `inventory.path`, `calendars.path`, `deliverable.path`) through tilde / env expansion + `os.path.realpath`.
  - Walk `<data-root>/inventories/<customer>/` recursively for `*.yaml`, `*.yml`, `*.json`; cap at 2000 files; on overshoot emit `truncated:inventory:<count>` on stderr.
  - For each file, parse (yaml → `yaml.safe_load`; json → `json.load`); walk every string leaf; apply the same category regexes from `extract-tokens.py` (share the compile-once block by copying it — no cross-file import; standalone scripts are easier to ship). Union tokens per category; dedupe.
  - Emit normalized bundle JSON on stdout: `{"customer": "<id>", "artifact_roots": [<realpath-canonicalized dirs>], "tokens": {"hostname": [...], "ipv4": [...], ...}, "generated_at": "<iso8601>", "source_mtime_max": <epoch_float>}`.
  - Cache under `<data-root>/.cache/customer-isolation/<customer>.json`. On cache hit, compare `source_mtime_max` against the tree's current max `mtime` — if unchanged, reuse. Create cache dir with `mkdir(parents=True, exist_ok=True)`.
  - Exit 0 on success; 2 on profile YAML parse failure (emit `guard-profile-load-failed` message to stderr).
- **MIRROR**: Python `pathlib.Path` usage; docstring header as in 2.1/2.2.
- **IMPORTS**: `argparse, datetime, json, os, os.path, subprocess, sys, time`; `import yaml` (PyYAML); reuse category regexes from 2.2 (copy inline).
- **GOTCHA**: PyYAML might not be installed — `try/except ImportError` with a clear error pointing to the load-profile.sh fallback (which also handles this case). Also: when a profile YAML declares an override pointing OUTSIDE `<data-root>`, honor it (per `yci/docs/profiles.md`) but realpath the result so the guard's path-match still works.
- **VALIDATE**:
  - `python3 -m py_compile ...`
  - Manual: construct a fixture `<data-root>` with profiles/acme.yaml pointing to inventories/acme/inv.yaml with `hosts: [bigbank.corp]` (wrong!) — just for cache test — run with --customer acme, confirm cache file written and subsequent run reuses it.

### Task 3.1: Path-match + allowlist helpers — Depends on [2.1, 2.2, 2.3]

- **BATCH**: B3
- **WORKTREE**: `~/.claude-worktrees/claude-plugins-yci-customer-guard-3-1/`
- **ACTION**: Create `yci/skills/_shared/customer-isolation/scripts/path-match.sh` and `.../allowlist.sh`.
- **IMPLEMENT**:
  - `path-match.sh` (sourceable; NO `set -euo` at file scope): export `path_is_under()` that takes two args `<candidate>` and `<root>`, canonicalizes both via `_pm_realpath` (prefer `realpath -m "$p"`, fall back to `python3 -c 'import os.path,sys;print(os.path.realpath(sys.argv[1]))' "$p"`), and returns 0 iff `$cand == $root` OR `"${cand#${root}/}" != "$cand"` (prefix-with-separator match). Reject partial-segment matches: explicit separator required. Also export `path_canonicalize()` for reuse.
  - `allowlist.sh` (sourceable; NO `set -euo`): export `allowlist_load <data-root> <active-customer>` which populates shell arrays `ALLOWLIST_PATHS=(...)` and `ALLOWLIST_TOKENS=(...)` by reading `<data-root>/profiles/<active>.allowlist.yaml`, then merging `<data-root>/allowlist.yaml`. Use embedded Python for YAML parse (same pattern as `resolve-customer.sh` uses for JSON). Emit `guard-allowlist-malformed` on parse failure and return 3. Export `allowlist_contains <category> <token>` that scans the appropriate array.
- **MIRROR**: `NAMING_CONVENTION` + embedded-Python-in-bash pattern from `resolve-customer.sh:87-104`.
- **IMPORTS**: none (pure bash + embedded python3).
- **GOTCHA**: `realpath -m` is not on macOS. Use `command -v realpath` AND check `realpath -m /` works (probe once, cache in a global `_PM_HAS_M`) before relying on it. Also: `"${cand#${root}/}"` is NOT safe when `$root` contains glob chars — quote-protect via `local escaped="${root//\*/\\*}"; escaped="${escaped//\?/\\?}"` before comparison.
- **VALIDATE**:
  - `bash -n path-match.sh && bash -n allowlist.sh` (syntax)
  - Source each, call each exported function once with trivial args, confirm exit codes
  - `shellcheck --severity=warning yci/skills/_shared/customer-isolation/scripts/*.sh`

### Task 3.2: detect.sh orchestrator — Depends on [2.1, 2.2, 2.3, 3.1]

- **BATCH**: B3
- **WORKTREE**: `~/.claude-worktrees/claude-plugins-yci-customer-guard-3-2/`
- **ACTION**: Create `yci/skills/_shared/customer-isolation/detect.sh`.
- **IMPLEMENT**: Sourceable library. Exposes ONE function: `isolation_check_payload`. Inputs: env vars `YCI_ACTIVE_CUSTOMER` and `YCI_DATA_ROOT_RESOLVED`; PreToolUse JSON via stdin (read once into `PAYLOAD`) or `--payload-file <path>`. Algorithm:
  1. Abort with internal error if `YCI_ACTIVE_CUSTOMER` unset (caller's responsibility to set).
  2. Enumerate non-active customers: `find "$YCI_DATA_ROOT_RESOLVED/profiles" -maxdepth 1 -name '*.yaml' -not -name '_*.yaml'` → strip `.yaml`, filter out active.
  3. Invoke `extract-paths.py` with PAYLOAD → read candidate-paths array.
  4. Invoke `extract-tokens.py` with PAYLOAD → read candidate-tokens array (tab-separated `cat\ttoken`).
  5. For each foreign customer, invoke `inventory-fingerprint.py --data-root ... --customer <f>` → cache-or-build its bundle (JSON from stdout).
  6. For each bundle: intersect candidate paths with `bundle.artifact_roots` via `path_is_under`; intersect candidate tokens with `bundle.tokens.<category>` via set-membership (use `jq` to extract token arrays; fall back to python one-liner).
  7. Source `allowlist.sh`; call `allowlist_load`; filter both collision sets via `allowlist_contains`.
  8. If any remaining collision: emit decision JSON on stdout — `{"decision":"deny","collision":{"active":"<a>","foreign":"<f>","kind":"path|token","evidence":"<v>","resolved":"<r>"}}`. Return 0.
  9. Else emit `{"decision":"allow"}`; return 0.
- **MIRROR**: `NAMING_CONVENTION` (sourceable → no `set -euo` at top); explicit error cases emit to stderr with `printf >&2` per `ERROR_HANDLING`.
- **IMPORTS**: sources `path-match.sh` and `allowlist.sh`; invokes `extract-paths.py`, `extract-tokens.py`, `inventory-fingerprint.py` via `python3`.
- **GOTCHA**: The two extractors emit to stdout, so capture with `cand_paths=$(python3 .../extract-paths.py <<<"$PAYLOAD")`. On inventory-fingerprint failure (exit 2 = profile load failed), propagate via a stderr note but continue evaluation for other foreign customers — one malformed foreign profile shouldn't disable the whole guard. On zero foreign customers, short-circuit to allow.
- **VALIDATE**:
  - Source the file in a clean bash, call `isolation_check_payload` with a rigged `$YCI_DATA_ROOT_RESOLVED` containing TWO profiles, stdin = synthetic `Read` of a foreign path → confirm stdout starts with `{"decision":"deny"`
  - `shellcheck --severity=warning detect.sh`

### Task 4.1: Unit tests for the detection library — Depends on [3.1, 3.2]

- **BATCH**: B4
- **WORKTREE**: `~/.claude-worktrees/claude-plugins-yci-customer-guard-4-1/`
- **ACTION**: Create `yci/skills/_shared/customer-isolation/tests/` (whole tree).
- **IMPLEMENT**:
  - `helpers.sh` — duplicate of `yci/skills/customer-profile/tests/helpers.sh` (no cross-path import). Resolve `YCI_SCRIPTS_DIR` to `../scripts`, `YCI_REFS_DIR` to `../references`.
  - `run-all.sh` — identical structure to `yci/skills/customer-profile/tests/run-all.sh`.
  - `fixtures/` — two profiles (`profiles/acme.yaml`, `profiles/bigbank.yaml`) + inventory trees `inventories/acme/hosts.yaml`, `inventories/bigbank/hosts.yaml` populated with non-overlapping identifiers (acme: 10.1.1.1, acme01.acme.com; bigbank: 10.2.2.2, bb01.bigbank.corp), plus a set of PreToolUse JSON payloads under `fixtures/payloads/`: one per Claude tool type. Keep fixtures small (< 200 lines total).
  - `test_extract_paths.sh` — one sub-test per tool type (Read, Write, Edit, MultiEdit, NotebookEdit, Glob, Grep, Bash, WebFetch, Task); truncation cap; missing `file_path`; relative path; `~/` path.
  - `test_extract_tokens.sh` — one sub-test per category; whitelist bypasses for `127.0.0.1`, `localhost`, `example.com`, `192.0.2.1`, `2001:db8::1`; content-size cap.
  - `test_inventory_fingerprint.sh` — missing inventory dir → empty bundle; malformed YAML → exit 2 + `guard-profile-load-failed`; path override honored; cache hit vs miss via explicit mtime probe.
  - `test_path_match.sh` — `/acme` vs `/acme-inc` (no match); symlink inside → follows to target; relative path resolution.
  - `test_allowlist.sh` — missing file (empty allowlist); malformed → `guard-allowlist-malformed` / exit 3; path entry matches; token entry matches.
  - `test_detect.sh` — allow case (empty foreign list); deny-path; deny-token; symlink-escape; allowlisted bypass.
- **MIRROR**: `TEST_STRUCTURE` + `TEST_RUNNER_CONVENTION`.
- **IMPORTS**: `source "$(dirname "$0")/helpers.sh"`. Use `with_sandbox` around every FS-touching test.
- **GOTCHA**: Fixtures and tests share the same directory; `find` in `run-all.sh` uses `-maxdepth 1 -name 'test_*.sh'` so fixture `.sh` files don't accidentally execute. Keep fixtures plain-text and NON-executable.
- **VALIDATE**:
  - `bash yci/skills/_shared/customer-isolation/tests/run-all.sh` → zero failures
  - `find yci/skills/_shared/customer-isolation/tests -name 'test_*.sh' -not -executable` → empty
  - `shellcheck --severity=warning` on every `test_*.sh`

### Task 4.2: Claude Code hook entrypoint + plugin registration — Depends on [3.1, 3.2]

- **BATCH**: B4
- **WORKTREE**: `~/.claude-worktrees/claude-plugins-yci-customer-guard-4-2/`
- **ACTION**: Create `yci/hooks/customer-guard/scripts/pretool.sh`, `.../decision-json.sh`, `yci/hooks/customer-guard/hook.json`; UPDATE `yci/.claude-plugin/plugin.json` to register the hook.
- **IMPLEMENT**:
  - `pretool.sh` (executable, `#!/usr/bin/env bash`, `set -euo pipefail`): read PreToolUse JSON into `INPUT="$(cat)"`. Resolve active customer by running `"$SCRIPT_DIR/../../skills/customer-profile/scripts/resolve-customer.sh"` via subshell — capture stdout; on exit 1, honor `YCI_GUARD_FAIL_OPEN=1` (exit 0 silently, stderr notes dry-fail-open) OR default fail-closed (source `decision-json.sh`, emit deny JSON with `guard-no-active-customer` reason, exit 0). Source `YCI_SHARED/customer-isolation/detect.sh`; call `isolation_check_payload <<<"$INPUT"`; capture stdout into `DECISION`. If DECISION is allow → exit 0 silently. If deny → source `decision-json.sh`; emit Claude Code hook JSON (see `HOOK_STDIN_READ` pattern, but output is JSON not plaintext): `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<catalogued message>"}}`. Exit 0 (Claude Code reads stdout for decision; non-zero exit means "hook errored" not "deny").
  - Honor `YCI_GUARD_DRY_RUN=1`: when a deny would be emitted, write a timestamped line to `<data-root>/.cache/customer-isolation/audit.log` (create dir lazily) with the full would-emit reason; emit a prominent `YCI GUARD: DRY-RUN MODE ACTIVE — would-block logged to <path>` banner to stderr; emit `{"decision":"allow"}` instead. Export `YCI_GUARD_DRY_RUN_HIT=1` for test observability.
  - `decision-json.sh` (sourceable, NO `set -euo` at top): export `emit_deny <reason>` which escapes reason for JSON and prints the correct Claude Code hook decision object. Also export `emit_allow` (prints nothing; allow is default).
  - `hook.json`: `{"hooks":{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"bash ${CLAUDE_PLUGIN_ROOT}/hooks/customer-guard/scripts/pretool.sh"}]}]}}`. Confirm exact shape against Claude Code plugin hooks doc when implementing.
  - Edit `yci/.claude-plugin/plugin.json` to add top-level key `"hooks": "hooks/customer-guard/hook.json"` (or the spec-correct shape — verify). Validate with `python3 -m json.tool`.
- **MIRROR**: `HOOK_STDIN_READ` from `ycc/settings/hooks/worktree-create.sh` (adapt the stdin-read + json_get helpers; DO NOT copy the plaintext-stdout output path — that is a WorktreeCreate convention). `NAMING_CONVENTION` for docstring contract.
- **IMPORTS**: source `decision-json.sh` + `detect.sh` + `allowlist.sh` + `path-match.sh`. Subshell-invoke `resolve-customer.sh`.
- **GOTCHA**: Claude Code's decision-JSON shape MAY evolve — the centralized `decision-json.sh` makes future shape changes a one-file edit. Do NOT put the JSON inline in `pretool.sh`. Also: Claude Code hooks may run in an environment without PyYAML — ensure `inventory-fingerprint.py` degrades gracefully (task 2.3 gotcha).
- **VALIDATE**:
  - `python3 -m json.tool yci/.claude-plugin/plugin.json` passes
  - `python3 -m json.tool yci/hooks/customer-guard/hook.json` passes
  - `bash -n yci/hooks/customer-guard/scripts/*.sh`
  - Manual: `echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/foreign/x"},"cwd":"/tmp"}' | bash yci/hooks/customer-guard/scripts/pretool.sh` under a contrived `$YCI_DATA_ROOT` with foreign fixture → stdout starts with `{"hookSpecificOutput"`
  - `find yci/hooks/customer-guard -name '*.sh' -not -executable` → empty

### Task 4.3: Operator command surface + skill wrapper — Depends on [3.1, 3.2]

- **BATCH**: B4
- **WORKTREE**: `~/.claude-worktrees/claude-plugins-yci-customer-guard-4-3/`
- **ACTION**: Create `yci/commands/guard-check.md` and `yci/skills/customer-guard/SKILL.md`.
- **IMPLEMENT**:
  - `yci/commands/guard-check.md` — slash-command wrapper with a 1-paragraph description and `**Load and follow the `yci:customer-guard`skill, passing through`$ARGUMENTS`.**` line (identical pattern to `/ycc:plan`).
  - `yci/skills/customer-guard/SKILL.md` — frontmatter: `name: customer-guard`, description (≥ 50 chars: "Ad-hoc cross-customer isolation check. Runs the customer-isolation detection library against a single path or text blob and reports allow/deny with the same catalogued errors as the PreToolUse hook."), `argument-hint: '<path-or-text> [--dry-run] [--data-root <path>]'`, `allowed-tools`: `[Read, Bash(cat:*), Bash(test:*), Bash(bash:*), Bash(python3:*)]`. Body: steps to construct a synthetic PreToolUse payload shaped like a `Read` tool call with the argument as `file_path` (OR if the input starts without `/` `~/` `./`, wrap as a `Write`-shape with the text as `content`), then invoke `yci/skills/_shared/customer-isolation/detect.sh` with the payload. Print the decision JSON verbatim to the user; on deny, also print the catalogued error ID.
- **MIRROR**: `yci/skills/customer-profile/SKILL.md` for frontmatter shape; `/ycc:plan` command pattern for the command wrapper.
- **IMPORTS**: none.
- **GOTCHA**: description MUST be ≥ 50 chars — the validator (task 5.1) enforces this. Keep `allowed-tools` minimal; do not grant Write or Edit — this skill is a checker, not a mutator.
- **VALIDATE**:
  - `python3 -m json.tool` does NOT apply (markdown)
  - Manual: read frontmatter and confirm description length via `python3 -c "import re,sys; m=re.search(r'description:\s*(.+?)\n', open(sys.argv[1]).read()); print(len(m.group(1)))" SKILL.md` → ≥ 50

### Task 5.1: Extend the yci validator — Depends on [4.1, 4.2, 4.3]

- **BATCH**: B5 (sequential; single-writer file)
- **ACTION**: UPDATE `scripts/validate-yci-skills.sh`.
- **IMPLEMENT**: Add two functions after `validate_customer_profile_skill`:
  - `validate_customer_guard_hook`: check `yci/hooks/customer-guard/hook.json` exists + valid JSON + references `pretool.sh`; each `*.sh` under `yci/hooks/customer-guard/scripts/` is executable with the correct shebang + `set -euo pipefail`; each reference doc under `yci/hooks/customer-guard/references/` exists and is non-empty; `error-messages.md` has ≥ 6 entries (`grep -c '^### `'`); Codex stub starts with `# Advisory only`.
  - `validate_customer_isolation_lib`: every `*.sh` under `yci/skills/_shared/customer-isolation/` has the right shebang; every `*.py` passes `python3 -m py_compile`; `detect.sh` sources cleanly (`bash -c 'source detect.sh && declare -F isolation_check_payload'`); `yci/skills/_shared/customer-isolation/tests/run-all.sh` exits 0; `yci/hooks/customer-guard/tests/run-all.sh` exits 0; `shellcheck --severity=warning` clean over both trees.
  - Plugin.json check: `yci/.claude-plugin/plugin.json` parses AND the `hooks` key (when present) resolves to an existing file.
  - Wire both functions into `main()` alongside the existing validators.
- **MIRROR**: `VALIDATOR_SECTION` — `fail` / `ok` / `warn` helpers; existence first, structural second, behavioural third.
- **IMPORTS**: bash built-ins + `python3`, `shellcheck` (guard with `command -v shellcheck` — warn-only if missing).
- **GOTCHA**: `shellcheck` may not be installed in every environment (CI usually has it; local dev sometimes not). Wrap in `if command -v shellcheck >/dev/null; then ...; else warn "shellcheck not installed"; fi` so dev-laptop validation still passes.
- **VALIDATE**:
  - `bash scripts/validate-yci-skills.sh` → exits 0 with the two new sections appearing in the output
  - Deliberately introduce a broken JSON in `yci/hooks/customer-guard/hook.json` (in a scratch branch) and confirm the validator fails loudly, then revert

### Task 6.1: End-to-end integration tests — Depends on [5.1]

- **BATCH**: B6
- **WORKTREE**: `~/.claude-worktrees/claude-plugins-yci-customer-guard-6-1/`
- **ACTION**: Create `yci/hooks/customer-guard/tests/` directory: `helpers.sh`, `run-all.sh`, and 7 test files.
- **IMPLEMENT**: Mirror the customer-profile + unit-test shapes. For each test, inside `with_sandbox`: write two profiles (`acme.yaml`, `bigbank.yaml`) and two inventory trees, set `YCI_CUSTOMER=acme`, invoke `bash "$SCRIPT_DIR/../scripts/pretool.sh"` via `printf '%s' "$payload" | bash ...` in a subshell with controlled env.
  - `test_pretool_allow.sh`: payload `Read` on active-customer's own file → stdout empty, exit 0.
  - `test_pretool_deny_path.sh`: payload `Read` on `<data-root>/artifacts/bigbank/...` → stdout starts `{"hookSpecificOutput"`, reason contains `bigbank`, `assert_error_id guard-path-collision`, exit 0.
  - `test_pretool_deny_fingerprint.sh`: payload `Write` whose `content` contains `bb01.bigbank.corp` (from bigbank inventory fixture) → deny with `guard-fingerprint-collision`.
  - `test_pretool_allowlist_pass.sh`: same payload as deny_path BUT with `<data-root>/profiles/acme.allowlist.yaml` listing the path → allow; `assert_contains "$AUDIT_LOG" "allowlisted"`.
  - `test_pretool_dry_run.sh`: `YCI_GUARD_DRY_RUN=1` env + deny_path payload → allow, `assert_contains "$(cat .cache/customer-isolation/audit.log)" "would-block"`, stderr banner present.
  - `test_pretool_no_active_customer.sh`: no profile active; with fail-closed default → deny + `guard-no-active-customer`; with `YCI_GUARD_FAIL_OPEN=1` → allow.
  - `test_pretool_symlink_escape.sh`: symlink inside acme's dir → bigbank target. Guard by `ln -s "$foreign" "$link" || { printf 'skip: symlink unsupported\n'; return 0; }` so FS without symlink doesn't fail the suite.
- **MIRROR**: `TEST_STRUCTURE` + `TEST_RUNNER_CONVENTION`. `assert_error_id` pulls from `yci/hooks/customer-guard/references/error-messages.md` (task 1.1).
- **IMPORTS**: `source helpers.sh`; invoke `pretool.sh` via subshell.
- **GOTCHA**: `with_sandbox` overrides `$HOME`, `$YCI_DATA_ROOT`, `$YCI_CUSTOMER` — but `pretool.sh` also invokes `resolve-customer.sh`, which walks up from `$PWD` looking for `.yci-customer`. Ensure the sandbox `$PWD` is inside `$HOME` so the walk stops correctly; also set `$YCI_CUSTOMER` to the desired active id (Tier 1 wins).
- **VALIDATE**:
  - `bash yci/hooks/customer-guard/tests/run-all.sh` → 0 failures
  - Each test file uses `yci_test_summary` at the end
  - `find ... -not -executable` → empty

### Task 6.2: Operator README + CONTRIBUTING update — Depends on [5.1]

- **BATCH**: B6
- **WORKTREE**: `~/.claude-worktrees/claude-plugins-yci-customer-guard-6-2/`
- **ACTION**: Create `yci/hooks/customer-guard/README.md`; UPDATE `yci/CONTRIBUTING.md`.
- **IMPLEMENT**:
  - README sections: Purpose (what the hook blocks and why); Install check (confirm `yci` plugin enabled; confirm `hook.json` registration); False-positive triage workflow (enable `YCI_GUARD_DRY_RUN=1` → inspect `<data-root>/.cache/customer-isolation/audit.log` → add minimal allowlist entry → re-run); Allowlist YAML schema (`paths:`, `tokens:`, mandatory `note:` field), by example; Error reference (link to `references/error-messages.md`); Capability gaps (link to `references/capability-gaps.md`); Security note: every allowlist entry must cite SOW or ticket — entries without a `note:` WILL BE FLAGGED by future validator tightening.
  - CONTRIBUTING.md: Add a "Guard-hook discipline" subsection under the Phase Discipline section (or append to Non-Goals) — 2-3 sentences pointing at the README and stating that relaxing the default posture (allow-by-default) is non-negotiable scope out.
- **MIRROR**: Voice and depth of `yci/skills/customer-profile/SKILL.md` + existing CONTRIBUTING.md; README shape of `ycc/skills/git-workflow/SKILL.md` (concise, section-first).
- **IMPORTS**: none.
- **GOTCHA**: Be careful not to duplicate content between README, CONTRIBUTING, and the PRD. README = operator; CONTRIBUTING = contributor; PRD = why-we-are-doing-this.
- **VALIDATE**:
  - `wc -l yci/hooks/customer-guard/README.md` → ≥ 60
  - `grep -c "SOW" yci/hooks/customer-guard/README.md` → ≥ 1
  - `git diff yci/CONTRIBUTING.md` → additive only; no reverts; mentions `customer-guard`

### Task 7.1: Full validate + smoke-test pass — Depends on [6.1, 6.2]

- **BATCH**: B7 (sequential)
- **ACTION**: From the parent worktree, run the full validation pipeline + manual smoke.
- **IMPLEMENT**:
  - `./scripts/validate.sh --only yci,json` → expect green.
  - `./scripts/validate.sh` (full) → expect green.
  - Manual smoke test:
    `bash
    dr="$(mktemp -d)"
    mkdir -p "$dr/profiles" "$dr/inventories/acme" "$dr/inventories/bigbank"
    cat > "$dr/profiles/acme.yaml" <<'EOF'
customer: { id: "acme", display_name: "Acme Corp" }
inventory: { path: "inventories/acme" }
EOF
    cat > "$dr/profiles/bigbank.yaml" <<'EOF'
customer: { id: "bigbank", display_name: "Big Bank" }
inventory: { path: "inventories/bigbank" }
EOF
    cat > "$dr/inventories/bigbank/hosts.yaml" <<'EOF'
hosts: [bb01.bigbank.corp]
EOF
    export YCI_CUSTOMER=acme YCI_DATA_ROOT="$dr"
    printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"'"$dr"'/inventories/bigbank/hosts.yaml"},"cwd":"/tmp"}' \
      | bash yci/hooks/customer-guard/scripts/pretool.sh
    # Expect: stdout starts with {"hookSpecificOutput"
    YCI_GUARD_DRY_RUN=1 printf '%s' '<same payload>' | bash .../pretool.sh
    # Expect: no stdout; stderr banner; audit.log updated
    `
  - `python3 -m json.tool yci/.claude-plugin/plugin.json` passes.
  - `find yci -name '*.sh' -not -executable` empty.
- **MIRROR**: Project "Testing Changes" conventions from `CLAUDE.md`.
- **IMPORTS**: none.
- **GOTCHA**: If `./scripts/validate.sh` (full) fails, DO NOT force-pass. Root-cause the failure — often it's the Codex/Cursor/opencode regeneration detecting drift because a helper from the YCI side got accidentally committed into a generated bundle. No generated file should have changed in this PR; if one did, revert it.
- **VALIDATE**: as above, each command exits 0.

---

## Testing Strategy

### Unit Tests

| Test                                    | Input                                          | Expected Output                                   | Edge Case?                 |
| --------------------------------------- | ---------------------------------------------- | ------------------------------------------------- | -------------------------- |
| `test_extract_paths::read`              | `Read` tool with `/tmp/x`                      | `/tmp/x` on stdout                                | No                         |
| `test_extract_paths::bash_heredoc`      | `Bash` with heredoc containing `/foreign/path` | `/foreign/path` extracted                         | Yes — heredoc escape       |
| `test_extract_paths::truncation`        | `Bash` with 1000 tokens                        | `truncated:paths:1000` on stderr; cap honored     | Yes — DoS guard            |
| `test_extract_tokens::ipv4_whitelisted` | payload containing `127.0.0.1`                 | stdout empty                                      | Yes — whitelist            |
| `test_extract_tokens::ipv4_real`        | payload containing `10.2.2.2`                  | `ipv4\t10.2.2.2` on stdout                        | No                         |
| `test_extract_tokens::content_cap`      | `Write` with 2 MiB content                     | `truncated:tokens:1` on stderr                    | Yes — size cap             |
| `test_inventory_fingerprint::missing`   | customer with no inventory dir                 | Bundle with empty tokens + artifact_roots         | Yes — missing data         |
| `test_inventory_fingerprint::cache`     | Same call twice                                | Second call reads cache (no parse)                | Yes — cache correctness    |
| `test_path_match::prefix_segment`       | `/acme` vs `/acme-inc`                         | NOT under                                         | Yes — false-positive guard |
| `test_path_match::symlink`              | Candidate symlink → foreign root               | Under                                             | Yes — symlink resolution   |
| `test_allowlist::malformed`             | invalid YAML                                   | exit 3 + `guard-allowlist-malformed`              | Yes — error path           |
| `test_allowlist::path_match`            | `{paths: [/foo]}` + candidate `/foo/x`         | `allowlist_contains path /foo/x` → 0              | No                         |
| `test_detect::allow`                    | no foreign profiles                            | `{"decision":"allow"}`                            | Yes — empty state          |
| `test_detect::deny_path`                | foreign path candidate                         | `{"decision":"deny","collision":{...kind:path}}`  | No                         |
| `test_detect::deny_token`               | foreign hostname in content                    | `{"decision":"deny","collision":{...kind:token}}` | No                         |
| `test_detect::allowlisted`              | foreign path + allowlist entry                 | `{"decision":"allow"}`                            | Yes — override path        |

### Edge Cases Checklist

- [x] Empty input (`{}` payload) → `guard-missing-tool-input` stderr warn, fail-open default
- [x] Maximum size input (1 MiB content cap, 2000 inventory files, 512 Bash tokens)
- [x] Invalid types (malformed allowlist YAML, malformed profile YAML)
- [x] Concurrent access (cache writes — use atomic `mv`-after-tmp pattern in inventory-fingerprint)
- [x] Network failure — N/A (no network IO)
- [x] Permission denied (`<data-root>/.cache/...` unwritable → warn on stderr, skip cache; don't fail)
- [x] Symlink escape (explicit test)
- [x] No active customer (both fail-closed default and fail-open opt-in)
- [x] Dry-run left on (banner on stderr every invocation)

---

## Validation Commands

### Static Analysis

```bash
# JSON validity
python3 -m json.tool yci/.claude-plugin/plugin.json
python3 -m json.tool yci/hooks/customer-guard/hook.json

# Python syntax
python3 -m py_compile yci/skills/_shared/customer-isolation/scripts/*.py

# Shell syntax + shellcheck
find yci/hooks/customer-guard yci/skills/_shared/customer-isolation -name '*.sh' -exec bash -n {} \;
find yci/hooks/customer-guard yci/skills/_shared/customer-isolation -name '*.sh' -exec shellcheck --severity=warning {} \;

# Executable bit
find yci/hooks/customer-guard yci/skills/_shared/customer-isolation -name '*.sh' -not -executable
```

EXPECT: Zero errors. Executable-find returns empty.

### Unit Tests

```bash
bash yci/skills/_shared/customer-isolation/tests/run-all.sh
```

EXPECT: All tests pass; `fail=0`.

### Integration Tests

```bash
bash yci/hooks/customer-guard/tests/run-all.sh
```

EXPECT: All 7 integration tests pass; `fail=0`.

### Full Validator

```bash
./scripts/validate.sh --only yci,json
./scripts/validate.sh
```

EXPECT: No regressions in existing validators; new validators green.

### Manual Validation

- [ ] Smoke test from task 7.1 returns a deny decision JSON on cross-customer `Read`
- [ ] Smoke test with `YCI_GUARD_DRY_RUN=1` produces an audit-log entry and allow decision
- [ ] Smoke test with `YCI_GUARD_FAIL_OPEN=1` + no active customer produces allow
- [ ] Default with no active customer produces deny + `guard-no-active-customer`
- [ ] Every error ID in `yci/hooks/customer-guard/references/error-messages.md` has a matching test reference

---

## Acceptance Criteria

- [ ] All 15 tasks completed
- [ ] All validation commands pass
- [ ] Unit tests (detection library) written and passing
- [ ] Integration tests (hook) written and passing
- [ ] `python3 -m json.tool` passes on both JSON files
- [ ] `shellcheck --severity=warning` clean across new shell scripts
- [ ] `find yci -name '*.sh' -not -executable` empty
- [ ] `./scripts/validate.sh --only yci,json` passes
- [ ] `./scripts/validate.sh` (full) passes
- [ ] Every error ID has a matching test
- [ ] Dry-run logs without blocking (integration-tested)
- [ ] Per-tenant allowlist accepted (integration-tested)
- [ ] Issue #28 acceptance criteria all checked off

## Completion Checklist

- [ ] Code follows discovered patterns (`NAMING_CONVENTION`, `ERROR_HANDLING`, `HOOK_STDIN_READ`, `TEST_STRUCTURE`, `TEST_RUNNER_CONVENTION`, `VALIDATOR_SECTION`, `ERROR_CATALOG_STYLE`)
- [ ] Error handling matches codebase style (named emit functions, stderr via `printf >&2`, actionable hints)
- [ ] Tests follow test patterns (helpers.sh duplicated, `with_sandbox` wrap, `yci_test_summary`)
- [ ] No hardcoded values (data-root, customer ids, paths are parameters)
- [ ] Documentation updated (README, CONTRIBUTING, error catalog, capability gaps, fingerprint rules)
- [ ] No unnecessary scope additions (Cursor/opencode runtime stubs NOT added; generator extension NOT added)
- [ ] Self-contained — no questions needed during implementation

---

## Risks

| Risk                                                            | Likelihood | Impact   | Mitigation                                                                                                                               |
| --------------------------------------------------------------- | ---------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Cross-customer leak slips past detection                        | Medium     | Critical | Default fail-closed; explicit fingerprint rules; every detection path unit-tested; unknown tools fall through to broad path + token scan |
| Allowlist abuse (operator whitelists everything under pressure) | Medium     | High     | README requires `note:` with SOW/ticket; per-customer allowlist (not global); future validator tightening to flag missing notes          |
| Dry-run left on in production                                   | Low        | High     | `YCI GUARD: DRY-RUN MODE ACTIVE` stderr banner every invocation; integration test asserts banner                                         |
| Profile-not-loaded edge case bypasses guard                     | Medium     | High     | Fail-closed default; `YCI_GUARD_FAIL_OPEN=1` opt-in documented as security-reducing                                                      |
| Symlink / relative-path traversal                               | Medium     | Critical | `realpath -m` with Python fallback on both sides; explicit symlink-escape integration test; `posixpath.commonpath` semantics             |
| Adversarial `Bash.command` parsing (path hidden in heredoc)     | Medium     | Medium   | Token extractor scans full command string independent of shlex split; both layers must miss for a leak                                   |
| Stale inventory fingerprint cache                               | Medium     | Medium   | Cache keyed on tree's max source mtime; invalidated on any change; README documents manual nuke                                          |
| Claude Code hook decision JSON shape drifts between releases    | Low        | Medium   | `decision-json.sh` centralizes shape; integration test covers shape; README notes targeted version                                       |
| Cross-platform `realpath -m` (macOS BSD differs)                | Medium     | Medium   | Probe + Python fallback; `test_path_match.sh` exercises fallback                                                                         |
| PyYAML missing on runtime machine                               | Low        | Medium   | `inventory-fingerprint.py` degrades with clear error; load-profile.sh already handles the case                                           |
| Glob-character injection in path-match prefix                   | Low        | Medium   | Quote-protect root string by escaping `*` and `?` before the prefix strip                                                                |
| `shellcheck` missing on dev laptop breaks validator             | High       | Low      | Guard with `command -v shellcheck`; warn-only when missing                                                                               |

---

## Notes

- The detection library lives in `yci/skills/_shared/customer-isolation/` rather than inline in the hook because it is also consumed by `/yci:guard-check` (task 4.3) and will be consumed by future hooks (P0.2 context-guard, P0.4 scope-gate). Extracting it now saves duplication later.
- Cross-plugin helper sharing is not supported — any helper pattern we want from `ycc/` we duplicate into yci, per `CLAUDE.md`. The `HOOK_STDIN_READ` pattern in `ycc/settings/hooks/worktree-create.sh` is a documented _pattern_ we follow, not a file we source.
- The Codex `targets/codex/codex-config-fragment.toml` advisory stub is the ONLY target-specific file committed in this PR. Cursor and opencode stubs are deferred to Phase 1a when the generator fleet gains yci wiring.
- The PRD (§11.9) requires secrets never leave the customer profile boundary. This hook enforces that at runtime; the telemetry-sanitizer (P0.3, separate issue) handles the output side.
- Post-merge, the guard is enabled automatically for every operator who has the `yci` plugin enabled. There is no feature flag — per PRD §10 #1, this behavior is non-negotiable.
