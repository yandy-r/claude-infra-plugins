<!-- markdownlint-disable MD013 -->
<!-- Plan files are generated artifacts with long lines in tables, JSON payloads, and nested bullets. MD013 adds friction without readability benefit here. -->

# Implementation Plan: yci change-window-gate hook + iCal + JSON-schedule adapters

> **Source**: [GitHub issue #1](https://github.com/yandy-r/claude-infra-plugins/issues/1) **PRD
> refs**: `docs/prps/prds/yci.prd.md` §6.1 P0.8; §5.4 adapter pattern; §11.4 ship order.
> **Generated**: 2026-04-22 via `/ycc:plan --parallel github issue 1`. **Format**: PRP-compatible
> plan (parallel batches + dependency-resolved).

## Overview

Add a second PreToolUse hook — `yci:change-window-gate` — that reads the active profile's
`change_window.adapter` and blocks destructive tool calls during freeze / blackout windows. Ships
with four adapters (`ical`, `json-schedule`, `always-open`, `none`) mirroring the PRD §5.4 / schema
enum, plus the dispatcher, a Codex advisory stub, fixture-backed integration tests, and
documentation. Phase 0 scope — Claude-native runtime plus Codex advisory stub; Cursor / opencode
parity deferred to Phase 1+.

## Locked Decisions

- **D1 (naming)** — Directory `yci/skills/_shared/change-window-adapters/` (hyphenated; consistent
  with `compliance-adapters/`, `inventory-adapters/`). PRD §5.4 prose using `changewindow-adapters/`
  is overruled for repo-layout consistency; profile schema value `change_window.adapter` already
  uses kebab-case and is unaffected.
- **D2 (manifest shape)** — Single combined `yci/hooks/hooks.json` manifest;
  `yci/.claude-plugin/plugin.json` `"hooks"` key pivots to `"./hooks/hooks.json"`. Both hooks share
  one `PreToolUse matcher: "*"` with two sequential `command` entries; customer-guard first,
  change-window-gate second. Per-hook `hook.json` files retained for direct-invocation testability
  but the combined manifest is what Claude Code loads.
- **D3 (aggregation)** — change-window-gate runs as a **separate hook script** invoked after
  customer-guard under the same matcher. Keeps concerns split, lets customer-guard
  deny-short-circuit the chain, matches one-hook-one-responsibility norm.
- **D4 (adapter I/O)** — Adapters emit a one-line JSON object on stdout:
  `{"decision":"allowed|warning|blocked","rationale":"<string>","adapter":"<name>","window_source":"<path-or-null>"}`.
  Exit codes: 0 = decision emitted, 2 = adapter config error (missing `.ics`, malformed JSON), 3 =
  runtime error. Non-zero exits translate to `blocked` with `cwg-adapter-error`.
- **D5 (warning handling)** — The hook treats `warning` as allow-with-stderr-banner. Tool proceeds;
  operator sees a visible advisory. Rationale: `warning` is "window closes in 15 min"-class;
  blocking it degrades UX.
- **D6 (destructive tool classes)** — `Write`, `Edit`, `NotebookEdit`, and `Bash` where the parsed
  command starts with a destructive verb catalogued in `destructive-classifier.sh` (`rm`, `mv`,
  `cp -f`, `dd`, `mkfs`, `apply`, `terraform apply`, `helm upgrade`, `kubectl apply|delete|replace`,
  `git push --force`, `systemctl start|restart|stop`, `shutdown`, `reboot`). Other Bash commands
  (`ls`, `cat`, `grep`, `rg`, `find`, `git status`, `git diff`) → read-only. Read tools (`Read`,
  `Grep`, `Glob`, `WebFetch`, `WebSearch`) → always read-only.
- **D7 (no active profile) — REVISED** — Instead of deferring entirely to customer-guard,
  change-window-gate classifies by **purpose class** when no profile is resolvable:
  - **Init / setup / dependency-resolution** paths (e.g., `/yci:init` scaffolding, writes under
    `$YCI_DATA_ROOT/profiles/`, reads of shared adapters, package/dependency installs) → **allow**
    with a stderr advisory banner. Rationale: bootstrap must function before a profile exists.
  - **Customer-artifact creation** (writes under `$YCI_DATA_ROOT/artifacts/` or paths matching
    deliverable conventions) → **block** with rationale `cwg-no-profile-cannot-create`. Cannot
    enforce a window without knowing the target customer's posture.
  - **Any other destructive write** without a resolvable profile → **block** (conservative).
  - **Read-only paths** → allow (unchanged).
  - Encoded in a new `purpose-classifier.sh` companion to `destructive-classifier.sh` — see step
    4.0.

## Patterns to Mirror

| Surface                  | Mirror                                                                                                                                                                                                                                             |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Hook directory shape     | `yci/hooks/customer-guard/` — `hook.json`, `scripts/pretool.sh`, `scripts/decision-json.sh`, `README.md`, `references/{capability-gaps,error-messages}.md`, `targets/codex/codex-config-fragment.toml`, `tests/{run-all,helpers}.sh` + `test_*.sh` |
| Adapter directory shape  | `yci/skills/_shared/compliance-adapters/{hipaa,pci,soc2,commercial,none}/` — each has `ADAPTER.md` + scripts/check.sh or equivalent                                                                                                                |
| Dispatcher shape         | `yci/skills/_shared/scripts/load-compliance-adapter.sh` — mirror exit-code taxonomy (0/1/2/3/4) and `--export-file` / `--print-path` flag set                                                                                                      |
| Adapter-schema lib shape | `yci/skills/_shared/scripts/adapter-schema.sh` — sourceable bash, declares `*_REQUIRED_FILES`, `*_ADAPTERS` arrays plus `*_is_shipped()` helper                                                                                                    |
| Profile loading          | `yci/skills/customer-profile/scripts/{profile-schema,resolve-customer,load-profile}.sh` — reuse verbatim (source-invoke from the hook)                                                                                                             |
| Hook entrypoint idiom    | `#!/usr/bin/env bash` + `set -uo pipefail` (intentionally no `-e`, aggregating decision logic)                                                                                                                                                     |
| Test harness             | `yci/hooks/customer-guard/tests/{run-all,helpers}.sh` — copy + adapt                                                                                                                                                                               |

## Worktree Setup

- **Parent**: `~/.claude-worktrees/claude-infra-plugins-change-window-gate/` (branch:
  `feat/change-window-gate`)
- **Children** (one per parallel task; merged into parent at batch boundaries):
  - Task 1.1 → `~/.claude-worktrees/claude-infra-plugins-change-window-gate-1-1/` (branch:
    `feat/change-window-gate-1-1`)
  - Task 1.2 → `~/.claude-worktrees/claude-infra-plugins-change-window-gate-1-2/` (branch:
    `feat/change-window-gate-1-2`)
  - Task 3.1 → `~/.claude-worktrees/claude-infra-plugins-change-window-gate-3-1/` (branch:
    `feat/change-window-gate-3-1`)
  - Task 3.2 → `~/.claude-worktrees/claude-infra-plugins-change-window-gate-3-2/` (branch:
    `feat/change-window-gate-3-2`)
  - Task 3.3 → `~/.claude-worktrees/claude-infra-plugins-change-window-gate-3-3/` (branch:
    `feat/change-window-gate-3-3`)
  - Task 3.4 → `~/.claude-worktrees/claude-infra-plugins-change-window-gate-3-4/` (branch:
    `feat/change-window-gate-3-4`)
  - Task 4.0 → `~/.claude-worktrees/claude-infra-plugins-change-window-gate-4-0/` (branch:
    `feat/change-window-gate-4-0`)
  - Task 4.1 → `~/.claude-worktrees/claude-infra-plugins-change-window-gate-4-1/` (branch:
    `feat/change-window-gate-4-1`)
  - Task 4.2 → `~/.claude-worktrees/claude-infra-plugins-change-window-gate-4-2/` (branch:
    `feat/change-window-gate-4-2`)
  - Task 4.3 → `~/.claude-worktrees/claude-infra-plugins-change-window-gate-4-3/` (branch:
    `feat/change-window-gate-4-3`)
  - Task 6.1 → `~/.claude-worktrees/claude-infra-plugins-change-window-gate-6-1/` (branch:
    `feat/change-window-gate-6-1`)
  - Task 6.2 → `~/.claude-worktrees/claude-infra-plugins-change-window-gate-6-2/` (branch:
    `feat/change-window-gate-6-2`)

Sequential / cross-cutting tasks (2.1 manifest plumbing, 5.1 tests, 7.1 verify+PR) carry NO worktree
annotation — they run in the parent worktree.

## Files to Change

### New files

- `yci/hooks/change-window-gate/hook.json`
- `yci/hooks/change-window-gate/scripts/pretool.sh`
- `yci/hooks/change-window-gate/scripts/destructive-classifier.sh`
- `yci/hooks/change-window-gate/scripts/purpose-classifier.sh` (D7 revision)
- `yci/hooks/change-window-gate/scripts/window-decision.sh`
- `yci/hooks/change-window-gate/README.md`
- `yci/hooks/change-window-gate/references/capability-gaps.md`
- `yci/hooks/change-window-gate/references/error-messages.md`
- `yci/hooks/change-window-gate/targets/codex/codex-config-fragment.toml`
- `yci/hooks/change-window-gate/tests/run-all.sh`
- `yci/hooks/change-window-gate/tests/helpers.sh`
- `yci/hooks/change-window-gate/tests/test_*.sh` (16 test files enumerated in 5.1)
- `yci/hooks/change-window-gate/tests/fixtures/{blocked,open,warning}.ics`
- `yci/hooks/change-window-gate/tests/fixtures/blackout.schedule.json`
- `yci/hooks/change-window-gate/tests/fixtures/profile-{ical,json,always-open,none,no-profile}.yaml`
- `yci/hooks/hooks.json` (combined manifest)
- `yci/skills/_shared/change-window-adapters/ical/ADAPTER.md`
- `yci/skills/_shared/change-window-adapters/ical/scripts/check.sh`
- `yci/skills/_shared/change-window-adapters/ical/scripts/ical_eval.py`
- `yci/skills/_shared/change-window-adapters/json-schedule/ADAPTER.md`
- `yci/skills/_shared/change-window-adapters/json-schedule/scripts/check.sh`
- `yci/skills/_shared/change-window-adapters/json-schedule/scripts/schedule_eval.py`
- `yci/skills/_shared/change-window-adapters/json-schedule/schema.json`
- `yci/skills/_shared/change-window-adapters/always-open/ADAPTER.md`
- `yci/skills/_shared/change-window-adapters/always-open/scripts/check.sh`
- `yci/skills/_shared/change-window-adapters/none/ADAPTER.md`
- `yci/skills/_shared/change-window-adapters/none/scripts/check.sh`
- `yci/skills/_shared/scripts/load-change-window-adapter.sh`
- `yci/skills/_shared/scripts/change-window-adapter-schema.sh`
- `docs/prps/reports/change-window-gate.report.md` (post-impl)

### Modified files

- `yci/.claude-plugin/plugin.json` — `"hooks"` path pivot from `./hooks/customer-guard/hook.json` to
  `./hooks/hooks.json`.
- `yci/hooks/customer-guard/README.md` — one-line insert under "Install Check" noting the
  combined-manifest redirect.
- `scripts/validate.sh` — new `validate_change_window_gate_hook()`,
  `validate_change_window_adapters()`, `validate_combined_hooks_manifest()` sections.
- `yci/CONTRIBUTING.md` — "Change-window adapters" subsection documenting adapter contract.

## Batches

Steps grouped by dependency for parallel execution. Steps within the same batch run concurrently;
batches run in order.

| Batch | Steps              | Depends On | Parallel Width | Notes                                                                                |
| ----- | ------------------ | ---------- | -------------- | ------------------------------------------------------------------------------------ |
| B1    | 1.1, 1.2           | —          | 2              | Cross-cutting groundwork — dispatcher + adapter-schema contract (independent files). |
| B2    | 2.1                | B1         | 1              | Combined-manifest pivot + plugin.json edit. High blast radius; sequential.           |
| B3    | 3.1, 3.2, 3.3, 3.4 | B2         | 4              | Four adapter implementations (each own directory — fully parallel).                  |
| B4    | 4.0, 4.1, 4.2, 4.3 | B2         | 4              | Hook scripts incl. purpose-classifier (D7); distinct files, parallel-safe.           |
| B5    | 5.1                | B3, B4     | 1              | Integration tests + fixtures — single tests/ dir, serial.                            |
| B6    | 6.1, 6.2           | B5         | 2              | Validator wiring + documentation.                                                    |
| B7    | 7.1                | B6         | 1              | Final validate, internal report, commit, PR. Runs in parent worktree.                |

- **Total steps**: 15 (was 14; +1 for D7's purpose-classifier)
- **Total batches**: 7
- **Max parallel width**: 4 (B3 and B4)

## Implementation Steps

### Batch 1 — Cross-cutting groundwork

#### 1.1 Adapter-schema contract library

- **File**: `yci/skills/_shared/scripts/change-window-adapter-schema.sh`
- **Depends on**: [none]
- **Worktree**: `~/.claude-worktrees/claude-infra-plugins-change-window-gate-1-1/` (branch:
  `feat/change-window-gate-1-1`)
- **Action**: Create sourceable bash library. No `set -euo` at file scope. Declare:
  - `YCI_CW_ADAPTER_REQUIRED_FILES=(ADAPTER.md scripts/check.sh)`
  - `YCI_CW_ADAPTERS_SHIPPED=(ical json-schedule always-open none)`
  - `YCI_CW_ADAPTERS_DEFERRED=(servicenow-cab)` — listed for informative errors
  - Helper
    `yci_cw_adapter_is_shipped() { local a="$1"; for s in "${YCI_CW_ADAPTERS_SHIPPED[@]}"; do [[ "$s" == "$a" ]] && return 0; done; return 1; }`
  - Helper
    `yci_cw_adapter_expected_files() { printf '%s\n' "${YCI_CW_ADAPTER_REQUIRED_FILES[@]}"; }`
- **Pattern**: mirror `yci/skills/_shared/scripts/adapter-schema.sh` verbatim, adapting
  names/values.
- **Validation**: shellcheck clean; `source` in a sub-shell produces declared arrays/functions.

#### 1.2 Dispatcher library

- **File**: `yci/skills/_shared/scripts/load-change-window-adapter.sh`
- **Depends on**: [none]
- **Worktree**: `~/.claude-worktrees/claude-infra-plugins-change-window-gate-1-2/` (branch:
  `feat/change-window-gate-1-2`)
- **Action**: Mirror `load-compliance-adapter.sh`. Expose `yci_load_change_window_adapter()`
  accepting `--adapter <name>` or `--profile-json-path <path>`; validates against
  `YCI_CW_ADAPTERS_SHIPPED` from `change-window-adapter-schema.sh`; resolves directory under
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/change-window-adapters/<name>/`; verifies required files.
  Modes: `--print-path` (stdout: resolved dir), `--export-file <file>` (write
  `export YCI_CW_ADAPTER_DIR=...` + `export YCI_CW_ADAPTER_NAME=...`), default `--print-path`. Exit
  codes match compliance loader: 0 ok; 1 usage; 2 unknown adapter; 3 shipped-but-missing-files; 4
  profile parse error. When `change_window` block is missing from profile AND
  `safety.change_window_required: false` → resolve as `always-open` with stderr advisory. When
  missing AND `safety.change_window_required: true` → exit 4.
- **Validation**: shellcheck clean; unit test with mock profile JSON for each outcome.

### Batch 2 — Combined manifest + plugin.json pivot (sequential, parent worktree)

#### 2.1 Combined hooks manifest + plugin.json pivot

- **Files**: `yci/hooks/hooks.json` (new), `yci/.claude-plugin/plugin.json` (edit),
  `yci/hooks/change-window-gate/hook.json` (new), `yci/hooks/customer-guard/README.md` (one-line
  edit)
- **Depends on**: [1.1, 1.2]
- **Worktree**: parent (sequential, load-bearing)
- **Action**:
  1. Create `yci/hooks/hooks.json`:

     ```json
     {
       "hooks": {
         "PreToolUse": [
           {
             "matcher": "*",
             "hooks": [
               {
                 "type": "command",
                 "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/customer-guard/scripts/pretool.sh"
               },
               {
                 "type": "command",
                 "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/change-window-gate/scripts/pretool.sh"
               }
             ]
           }
         ]
       }
     }
     ```

  2. Edit `yci/.claude-plugin/plugin.json`: `"hooks": "./hooks/customer-guard/hook.json"` →
     `"hooks": "./hooks/hooks.json"`.
  3. Create `yci/hooks/change-window-gate/hook.json` (standalone fallback — same matcher, single
     change-window-gate command).
  4. Insert one line under "Install Check" in `yci/hooks/customer-guard/README.md`:
     `> Both yci hooks are wired via \`yci/hooks/hooks.json\`; see
     \`yci/hooks/change-window-gate/README.md\` for the second hook.`

- **Validation**: `python3 -m json.tool` on all three JSON files; `./scripts/validate.sh` passes
  (note: validator will warn about missing `change-window-gate/scripts/pretool.sh` until B4 —
  acceptable intermediate state; CI is not run between batches).

### Batch 3 — Adapters (fully parallel)

#### 3.1 iCal adapter

- **Files**:
  `yci/skills/_shared/change-window-adapters/ical/{ADAPTER.md,scripts/check.sh,scripts/ical_eval.py}`
- **Depends on**: [1.1, 1.2, 2.1]
- **Worktree**: `~/.claude-worktrees/claude-infra-plugins-change-window-gate-3-1/` (branch:
  `feat/change-window-gate-3-1`)
- **Action**:
  - `ADAPTER.md`: intent, interface (`--ts <iso8601>`, `--source <path.ics>`, `--timezone <tz>`),
    emitted JSON shape, exit codes (0/2/3), documented RRULE subset, security note (`.ics` content
    is untrusted; `ical_eval.py` does not execute any embedded content).
  - `scripts/check.sh`: `#!/usr/bin/env bash` + `set -euo pipefail`; parses
    `--ts --source --timezone`; delegates to `ical_eval.py`. Propagates exit code.
  - `scripts/ical_eval.py`: stdlib-only `.ics` parser. Supports `VEVENT` with `DTSTART`/`DTEND`
    (date, date-time with/without `Z`, `TZID=...:...` resolved via `zoneinfo`), `SUMMARY`, `RRULE`
    subset `FREQ=DAILY|WEEKLY|MONTHLY` with `COUNT` or `UNTIL`. Explicitly unsupported (documented +
    rationale-messaged): inline `VTIMEZONE`, `BYDAY`/`BYSETPOS`. Logic: event covers ts → `blocked`;
    no event covers but one starts within `warn_before_minutes` (default 60) → `warning`; else
    `allowed`. Rationale string = `SUMMARY` + UTC-normalized window.
- **Validation**: fixture `.ics` files in 5.1 exercise documented cases;
  `python3 -c "import ical_eval"` succeeds (no third-party deps).

#### 3.2 JSON-schedule adapter

- **Files**:
  `yci/skills/_shared/change-window-adapters/json-schedule/{ADAPTER.md,schema.json,scripts/check.sh,scripts/schedule_eval.py}`
- **Depends on**: [1.1, 1.2, 2.1]
- **Worktree**: `~/.claude-worktrees/claude-infra-plugins-change-window-gate-3-2/` (branch:
  `feat/change-window-gate-3-2`)
- **Action**:
  - `schema.json`: draft-07. Top-level
    `{blackouts: [{start, end, label?}], warn_before_minutes?: int}`. `start`/`end` are ISO-8601
    strings; `warn_before_minutes` default 60.
  - `scripts/check.sh`: bash wrapper; flags mirror iCal.
  - `scripts/schedule_eval.py`: `json.load` + `datetime.fromisoformat` (Python ≥3.11) + `zoneinfo`.
    Logic: ts ∈ any blackout → `blocked` with `label` in rationale; ts within `warn_before_minutes`
    of next blackout start → `warning`; else `allowed`.
  - `ADAPTER.md`: parity with ical.
- **Validation**: fixture `blackout.schedule.json` round-trips through `schedule_eval.py` for each
  outcome.

#### 3.3 always-open adapter

- **Files**: `yci/skills/_shared/change-window-adapters/always-open/{ADAPTER.md,scripts/check.sh}`
- **Depends on**: [1.1, 1.2, 2.1]
- **Worktree**: `~/.claude-worktrees/claude-infra-plugins-change-window-gate-3-3/` (branch:
  `feat/change-window-gate-3-3`)
- **Action**:
  - `ADAPTER.md`: bookend adapter; used by `_internal` homelab profile; ignores all flags.
  - `scripts/check.sh`: `#!/usr/bin/env bash` + `set -euo pipefail`;
    `printf '{"decision":"allowed","rationale":"always-open adapter: no window enforced","adapter":"always-open","window_source":null}\n'`;
    exit 0.
- **Validation**: direct invocation returns expected JSON.

#### 3.4 none adapter

- **Files**: `yci/skills/_shared/change-window-adapters/none/{ADAPTER.md,scripts/check.sh}`
- **Depends on**: [1.1, 1.2, 2.1]
- **Worktree**: `~/.claude-worktrees/claude-infra-plugins-change-window-gate-3-4/` (branch:
  `feat/change-window-gate-3-4`)
- **Action**:
  - `ADAPTER.md`: paranoid-mode bookend; requires explicit `YCI_CWG_OVERRIDE=1` to proceed.
  - `scripts/check.sh`: if `YCI_CWG_OVERRIDE=1` → emit
    `{"decision":"allowed","rationale":"none adapter: override acknowledged","adapter":"none","window_source":null}`;
    else emit
    `{"decision":"blocked","rationale":"none adapter: explicit override required; set YCI_CWG_OVERRIDE=1 to proceed","adapter":"none","window_source":null}`.
    Exit 0 in both cases.
- **Validation**: both branches tested in 5.1.

### Batch 4 — Hook scripts (parallel by file)

#### 4.0 Purpose classifier (D7 revision)

- **File**: `yci/hooks/change-window-gate/scripts/purpose-classifier.sh`
- **Depends on**: [2.1]
- **Worktree**: `~/.claude-worktrees/claude-infra-plugins-change-window-gate-4-0/` (branch:
  `feat/change-window-gate-4-0`)
- **Action**: Sourceable bash lib (no `set -euo` at file scope). Exports:
  - `cwg_is_init_path "$tool_name" "$tool_input_json"` — returns 0 when the call is
    init/setup/dependency-resolution:
    - Writes whose resolved path is under `$YCI_DATA_ROOT/profiles/` (profile scaffolding)
    - Reads of any path
    - Bash commands matching
      `^(/yci:init|yci-init|mkdir -p "$YCI_DATA_ROOT"|npm install|pip install|uv (sync|pip install)|pnpm install|yarn install|brew install|asdf install|apt install|dnf install)\b`
  - `cwg_is_artifact_creation "$tool_name" "$tool_input_json"` — returns 0 when the call creates
    customer artifacts:
    - `Write`/`Edit`/`NotebookEdit` whose resolved path is under `$YCI_DATA_ROOT/artifacts/` OR
      matches deliverable-path patterns from profile (pattern: any path containing `/artifacts/`,
      `/deliverables/`, or a `path:` override from profile `deliverable.path`)
  - Resolution helper: parses `$YCI_DATA_ROOT` (default `~/.config/yci/`) and honors
    `$YCI_DATA_ROOT` envvar override.
- **Validation**: unit tests in 5.1 (`test_purpose_classifier.sh`) cover ~15 cases per function.

#### 4.1 Destructive classifier

- **File**: `yci/hooks/change-window-gate/scripts/destructive-classifier.sh`
- **Depends on**: [2.1]
- **Worktree**: `~/.claude-worktrees/claude-infra-plugins-change-window-gate-4-1/` (branch:
  `feat/change-window-gate-4-1`)
- **Action**: Sourceable lib. Exports `cwg_is_destructive "$tool_name" "$tool_input_json"` returning
  0 when destructive. Tool classes:
  - `Write`, `Edit`, `NotebookEdit` → destructive (always).
  - `Bash` → parse `command` via Python one-liner:
    `python3 -c 'import sys, shlex, json; d=json.load(sys.stdin); toks=shlex.split(d.get("command",""), comments=True); print(toks[0] if toks else "")'`.
    Compare first token against `DESTRUCTIVE_BASH_VERBS=(rm mv dd mkfs shutdown reboot)` OR parse
    for destructive sub-invocations (`git push --force`, `kubectl {apply,delete,replace}`,
    `terraform apply`, `helm upgrade`, `systemctl {start,restart,stop}`, `cp -f`). Catalogued in an
    inline table with one-line rationale per entry.
  - `Read`, `Grep`, `Glob`, `WebFetch`, `WebSearch`, `Bash` with non-destructive first token →
    non-destructive.
- **Validation**: `test_destructive_classifier.sh` with ~20 cases.

#### 4.2 Window-decision orchestrator

- **File**: `yci/hooks/change-window-gate/scripts/window-decision.sh`
- **Depends on**: [2.1]
- **Worktree**: `~/.claude-worktrees/claude-infra-plugins-change-window-gate-4-2/` (branch:
  `feat/change-window-gate-4-2`)
- **Action**: Sourceable + CLI. `cwg_decide "$profile_json_path" [$ts_iso8601]`:
  - Default `ts` = `date -u +%Y-%m-%dT%H:%M:%SZ`.
  - Honor `YCI_CWG_OVERRIDE=1` — short-circuit
    `{"decision":"allowed","rationale":"override envvar set","adapter":"override","window_source":null}`.
  - Source `load-change-window-adapter.sh`, call with `--profile-json-path` +
    `--export-file /tmp/...`, eval to get `YCI_CW_ADAPTER_DIR` and `YCI_CW_ADAPTER_NAME`.
  - Invoke `$YCI_CW_ADAPTER_DIR/scripts/check.sh --ts "$ts" --source "$source" --timezone "$tz"`
    (source/tz extracted from profile JSON with
    `python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("change_window",{}).get("source",""))' ...`).
  - Capture stdout; validate shape (has `decision` + `rationale`); on adapter crash / malformed
    output → emit
    `{"decision":"blocked","rationale":"cwg-adapter-error: <details>","adapter":"$YCI_CW_ADAPTER_NAME","window_source":null}`.
- **Validation**: `test_window_decision.sh` stubs adapter and exercises override, success, crash
  paths.

#### 4.3 Hook entrypoint

- **File**: `yci/hooks/change-window-gate/scripts/pretool.sh`
- **Depends on**: [2.1]
- **Worktree**: `~/.claude-worktrees/claude-infra-plugins-change-window-gate-4-3/` (branch:
  `feat/change-window-gate-4-3`)
- **Action**: `#!/usr/bin/env bash` + `set -uo pipefail` (no `-e`; aggregates decision logic like
  customer-guard). Structure:
  1. Read stdin JSON payload; extract `tool_name`, `tool_input`.
  2. Short-circuit on `YCI_CWG_OVERRIDE=1` → exit 0.
  3. Source `destructive-classifier.sh`. If NOT destructive → exit 0.
  4. Resolve `$YCI_DATA_ROOT` (source `yci/skills/_shared/scripts/resolve-data-root.sh`).
  5. Resolve active customer via `yci/skills/customer-profile/scripts/resolve-customer.sh`. If
     resolver refuses:
     - Source `purpose-classifier.sh`.
     - If `cwg_is_init_path` → print stderr advisory
       `yci change-window-gate: no active profile, allowing init path`; exit 0.
     - If `cwg_is_artifact_creation` → source `decision-json.sh` (from customer-guard); emit deny
       with rationale
       `cwg-no-profile-cannot-create: cannot enforce change window without an active profile; run /yci:switch <id> first`;
       exit 0.
     - Else (destructive but neither init nor artifact creation) → emit deny with rationale
       `cwg-no-profile-destructive-write: destructive operation requires an active profile`; exit 0.
  6. Load profile JSON via `load-profile.sh`. On parse error → emit deny with
     `cwg-profile-load-error`; exit 0.
  7. Source `window-decision.sh`; invoke `cwg_decide`.
  8. Dispatch on decision:
     - `allowed` → exit 0.
     - `warning` → print stderr banner with rationale; exit 0 (allow).
     - `blocked` → `YCI_CWG_DRY_RUN=1` → print stderr "[DRY-RUN BLOCKED]: <rationale>" + append to
       `$YCI_DATA_ROOT/logs/change-window-gate.audit.log`; exit 0. Else emit deny JSON; exit 0.
  9. Any unexpected state → emit deny with `cwg-internal-error`; exit 0 (fail-closed for destructive
     ops).
- **Validation**: end-to-end tests in 5.1.

### Batch 5 — Integration tests + fixtures

#### 5.1 Test harness + fixtures

- **Files**: `yci/hooks/change-window-gate/tests/{run-all.sh,helpers.sh,test_*.sh,fixtures/*}`
- **Depends on**: [3.1, 3.2, 3.3, 3.4, 4.0, 4.1, 4.2, 4.3]
- **Worktree**: parent (single tests dir, sequential)
- **Action**: Copy `run-all.sh` and `helpers.sh` shape from `yci/hooks/customer-guard/tests/`. Test
  files:
  - `test_destructive_classifier.sh` — ~20 cases across all tool types.
  - `test_purpose_classifier.sh` — ~15 cases per function in `purpose-classifier.sh`; covers D7
    init/artifact/other axes.
  - `test_ical_adapter.sh` — ts in blackout → blocked; ts 30m before 60m-warn → warning; ts outside
    → allowed; malformed `.ics` → exit 2; TZID vs UTC boundary.
  - `test_json_schedule_adapter.sh` — parallel cases for JSON-schedule.
  - `test_always_open_adapter.sh` — always allowed.
  - `test_none_adapter.sh` — default blocked; `YCI_CWG_OVERRIDE=1` → allowed.
  - `test_window_decision.sh` — orchestrator stubs.
  - `test_dispatcher.sh` — dispatcher resolution, deferred adapters, `--adapter`, `--export`.
  - `test_hook_fails_open_on_read_tools.sh` — Read/Grep/Glob/WebFetch/Bash "ls" → allow regardless
    of window.
  - `test_hook_defers_and_allows_init.sh` (D7) — resolver refusal + path under
    `$YCI_DATA_ROOT/profiles/` → allow with stderr advisory.
  - `test_hook_blocks_creation_without_profile.sh` (D7) — resolver refusal + path under
    `$YCI_DATA_ROOT/artifacts/` → deny with `cwg-no-profile-cannot-create`.
  - `test_hook_blocks_other_destructive_without_profile.sh` (D7) — destructive non-init,
    non-artifact calls without an active profile → conservative deny.
  - `test_hook_blocks_destructive_in_blackout.sh` — e2e: ical adapter + `.ics` covers "now" +
    `Bash rm -rf …` → deny.
  - `test_hook_warning_allows_with_banner.sh` — e2e: adapter returns warning → exit 0 + stderr
    banner.
  - `test_hook_dry_run.sh` — `YCI_CWG_DRY_RUN=1` + would-be-block → allow + stderr banner +
    audit-log entry.
  - `test_hook_override.sh` — `YCI_CWG_OVERRIDE=1` → allow regardless.
  - Fixtures: `blocked.ics`, `open.ics`, `warning.ics`, `blackout.schedule.json`;
    `profile-{ical,json,always-open,none,no-profile}.yaml`. Synthetic orgs only (`acme-test`,
    `widgetco-test`).
- **Validation**: `bash yci/hooks/change-window-gate/tests/run-all.sh --verbose` exits 0.

### Batch 6 — Validator + docs

#### 6.1 Validator wiring

- **File**: `scripts/validate.sh`
- **Depends on**: [5.1]
- **Worktree**: `~/.claude-worktrees/claude-infra-plugins-change-window-gate-6-1/` (branch:
  `feat/change-window-gate-6-1`)
- **Action**: Add three new validation functions alongside existing ones:
  - `validate_change_window_gate_hook()` — checks directory, `hook.json` JSON valid, all
    `scripts/*.sh` executable + shellchecked. Exempts `destructive-classifier.sh`,
    `purpose-classifier.sh`, `window-decision.sh` from the `set -euo pipefail` requirement
    (sourceable libs). Checks `references/`, `targets/codex/` stub presence.
  - `validate_change_window_adapters()` — iterate `yci/skills/_shared/change-window-adapters/*/`;
    for each, check files from `YCI_CW_ADAPTER_REQUIRED_FILES`; `scripts/check.sh` executable +
    bash-shebanged; shellcheck clean.
  - `validate_combined_hooks_manifest()` — verify `yci/hooks/hooks.json` is valid JSON with the
    expected shape (one PreToolUse matcher, at least one command pointing at each of
    customer-guard + change-window-gate); verify `yci/.claude-plugin/plugin.json` `"hooks"` points
    at it.
  - Auto-discovery glob for `yci/**/tests/run-all.sh` — confirm or extend so change-window-gate
    tests execute.
- **Validation**: `./scripts/validate.sh` exits 0.

#### 6.2 Documentation

- **Files**: `yci/hooks/change-window-gate/README.md`,
  `yci/hooks/change-window-gate/references/capability-gaps.md`,
  `yci/hooks/change-window-gate/references/error-messages.md`,
  `yci/hooks/change-window-gate/targets/codex/codex-config-fragment.toml`, `yci/CONTRIBUTING.md`
  (edit)
- **Depends on**: [5.1]
- **Worktree**: `~/.claude-worktrees/claude-infra-plugins-change-window-gate-6-2/` (branch:
  `feat/change-window-gate-6-2`)
- **Action**:
  - `README.md`: parity with `yci/hooks/customer-guard/README.md` — Purpose, Install Check,
    False-positive triage (`YCI_CWG_DRY_RUN=1`), Override envvar (`YCI_CWG_OVERRIDE=1`), Error
    reference, Capability gaps, Security note.
  - `capability-gaps.md`: Claude Code = supported; Cursor = deferred (Phase 1a); Codex =
    unsupported + advisory stub; opencode = deferred (Phase 1a). Copy wording from customer-guard
    doc.
  - `error-messages.md`: catalog `cwg-no-active-profile`, `cwg-no-profile-cannot-create`,
    `cwg-no-profile-destructive-write`, `cwg-profile-load-error`, `cwg-adapter-load-failed`,
    `cwg-adapter-blocked`, `cwg-adapter-warning`, `cwg-adapter-error`, `cwg-none-requires-override`,
    `cwg-missing-tool-input`, `cwg-destructive-in-blackout`, `cwg-internal-error`.
  - `targets/codex/codex-config-fragment.toml`: comment-only advisory stub; copy customer-guard
    shape, replace name.
  - `yci/CONTRIBUTING.md`: insert "Change-window adapters" subsection documenting required files
    (`ADAPTER.md`, `scripts/check.sh`), check.sh interface (`--ts --source --timezone`), emitted
    JSON shape, exit codes (0/2/3), `YCI_CWG_OVERRIDE` semantics.
- **Validation**: files present; markdown lint (if configured) clean.

### Batch 7 — Verification + wrap-up

#### 7.1 Final validate + internal report + PR

- **Files**: `docs/prps/reports/change-window-gate.report.md` (new); repo-root verification
- **Depends on**: [6.1, 6.2]
- **Worktree**: parent
- **Action**:
  1. Merge all child worktrees into `feat/change-window-gate`.
  2. `python3 -m json.tool` on `yci/.claude-plugin/plugin.json`, `yci/hooks/hooks.json`,
     `yci/hooks/change-window-gate/hook.json`, adapters' `schema.json`.
  3. `find yci -name "*.sh" -not -executable` → empty.
  4. `./scripts/validate.sh` → exit 0.
  5. `bash yci/hooks/change-window-gate/tests/run-all.sh --verbose` → exit 0.
  6. Write `docs/prps/reports/change-window-gate.report.md` — outcome summary, locked decisions
     (D1-D7), actual deviations from plan, deferred items (servicenow-cab adapter, Cursor/opencode
     parity, complex iCal RRULE).
  7. Commits:
     - `feat(change-window-gate): add PreToolUse hook + ical/json-schedule/always-open/none adapters (#1)`
     - `docs(internal): change-window-gate implementation report`
  8. Open PR using `.github/pull_request_template.md`, `Closes #1`, labels `type:feature`,
     `area:hooks`, `area:adapters`, `phase:2`, `priority:high`.

## Validation Commands

```bash
# After each batch:
python3 -m json.tool yci/.claude-plugin/plugin.json
find yci -name "*.sh" -not -executable
./scripts/install-shellcheck.sh  # one-time
./scripts/validate.sh
bash yci/hooks/change-window-gate/tests/run-all.sh --verbose  # from B5 onward
```

## Testing Strategy

- **Unit**: `destructive-classifier.sh`, `purpose-classifier.sh` (D7), `window-decision.sh`; each
  adapter's `check.sh` exercised directly.
- **Integration**: end-to-end hook invocation via stdin JSON payloads for each decision outcome ×
  each adapter × destructive/init/creation × dry-run/override.
- **Validator**: `./scripts/validate.sh` covers frontmatter, safety flags, executability,
  shellcheck, adapter completeness, combined-manifest shape, test-harness discovery.
- **Manual smoke** (post-merge, live Claude Code session):
  1. Fresh session with NO active profile.
  2. `Read` any file → allow.
  3. `Bash "npm install …"` → allow (init class per D7).
  4. `Write` to `~/.config/yci/artifacts/acme-test/foo.md` → deny with
     `cwg-no-profile-cannot-create`.
  5. `/yci:switch acme-test`.
  6. Set fixture JSON blackout `now ± 1h`; `Write` → deny with change-window reason.
  7. `export YCI_CWG_OVERRIDE=1`; `Write` → allow with stderr banner.
  8. `unset YCI_CWG_OVERRIDE`; `export YCI_CWG_DRY_RUN=1`; `Write` → allow + stderr banner +
     audit-log entry.
- **No real customer data** in any fixture.

## Risks & Mitigations

- **High — plugin.json pivot breaks customer-guard**: JSON-validate before commit; new
  `validate_combined_hooks_manifest()`; one-line revert rollback.
- **High — destructive/purpose classifier false negatives**: table-driven regex with inline
  rationale; ~35 combined test cases; dry-run envvar for triage; Python `shlex` tokenization for
  Bash commands (no naive regex on full string).
- **Medium — iCal parsing edge cases**: scoped subset documented; fixture-driven; complex RRULE out
  of scope (Phase 1+).
- **Medium — timezone drift**: all comparisons in UTC internally; tests exercise non-UTC profile
  explicitly.
- **Medium — double hook latency**: both scripts `exit 0` fast on read-only / override paths;
  expected overhead <100ms/call.
- **Medium — D7 purpose classification false positive blocks legitimate init**: comprehensive
  `test_purpose_classifier.sh` cases; audit log on block for forensic debugging.
- **Low — Phase-0 scope creep for Cursor/opencode parity**: capability-gaps.md defers explicitly;
  matches customer-guard precedent.
- **Low — `servicenow-cab` referenced but not shipped**: dispatcher emits
  `cwg-adapter-not-implemented` with PRD §11.4 pointer.

## Success Criteria

- [ ] `yci/hooks/change-window-gate/` ships with hook.json, pretool.sh, destructive-classifier.sh,
      purpose-classifier.sh, window-decision.sh, README.md, references/, targets/codex/ stub.
- [ ] Four adapters shipped under `yci/skills/_shared/change-window-adapters/`.
- [ ] Dispatcher `load-change-window-adapter.sh` resolves `change_window.adapter` + validates
      required files.
- [ ] `yci/.claude-plugin/plugin.json` points at `hooks/hooks.json`; combined manifest wires both
      hooks; customer-guard first.
- [ ] Adapter interface: input = ts + profile, output = `{decision,rationale,adapter,window_source}`
      JSON.
- [ ] Codex target stub present.
- [ ] capability-gaps.md documents per-target verdicts.
- [ ] All 16 test files under `yci/hooks/change-window-gate/tests/` green.
- [ ] `./scripts/validate.sh` green.
- [ ] `yci/CONTRIBUTING.md` documents the change-window adapter contract.
- [ ] D7 behavior implemented in `purpose-classifier.sh` + `pretool.sh` + tested.
- [ ] No real customer data in fixtures.
- [ ] PR opened with `Closes #1`, labeled per repo taxonomy.
- [ ] `docs/prps/reports/change-window-gate.report.md` committed with `docs(internal): …`.
