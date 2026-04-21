# Implementation Report: yci customer-guard PreToolUse Hook

## Summary

Implemented the load-bearing `yci` customer-guard PreToolUse hook that blocks any
Claude Code tool call, artifact write, or string input referencing a customer
different from the active profile. Detection lives in a reusable library at
`yci/skills/_shared/customer-isolation/` (Python extractors + Bash orchestrator)
so it can be consumed by the hook, the `/yci:guard-check` slash command, and
future hooks (P0.2 context-guard, P0.4 scope-gate). Claude Code ships a real
blocking hook registered via the plugin manifest; Cursor / Codex / opencode
ship documented capability gaps (anti-parity stance mirrored from
`ycc:hooks-workflow`).

## Assessment vs Reality

| Metric          | Predicted (Plan)     | Actual                              |
| --------------- | -------------------- | ----------------------------------- |
| Complexity      | Large                | Large (as predicted)                |
| Estimated Files | ~25 new + 3 modified | 42 new + 3 modified                 |
| Test assertions | not specified        | 86 unit + 32 integration = 118 pass |

## Execution Mode

- **Mode**: Parallel sub-agents (Path B — standalone `ycc:implementor` agents)
- **Worktree**: OFF (`--no-worktree` flag)
- **Batches**: 7 batches executed sequentially; tasks within each batch
  dispatched as concurrent `Agent` calls.
- **Parallel width**: 3 (Batches 1, 2, 4), 2 (Batches 3, 6), 1 (Batches 5, 7)

## Tasks Completed

| #   | Task                                                    | Status     | Notes                                                            |
| --- | ------------------------------------------------------- | ---------- | ---------------------------------------------------------------- |
| 1.1 | Error catalog                                           | ✓ Complete | 8 IDs, 208 lines                                                 |
| 1.2 | Capability-gaps doc + Codex stub                        | ✓ Complete | 4 target subsections                                             |
| 1.3 | Fingerprint-rules reference                             | ✓ Complete | 5 sections; all 7 regexes compile                                |
| 2.1 | extract-paths.py                                        | ✓ Complete | 10 tool types supported                                          |
| 2.2 | extract-tokens.py                                       | ✓ Complete | 7 categories, RFC-safe whitelist                                 |
| 2.3 | inventory-fingerprint.py                                | ✓ Complete | Deviated — `load-profile.sh` uses positional argv, not flags     |
| 3.1 | path-match.sh + allowlist.sh                            | ✓ Complete | Both dict-of-lists and list-of-dicts token forms                 |
| 3.2 | detect.sh orchestrator                                  | ✓ Complete | Fixed post-hoc: skip `*.allowlist.yaml` in foreign-customer enum |
| 4.1 | Unit tests for detection library                        | ✓ Complete | 86 assertions across 6 files                                     |
| 4.2 | pretool.sh + decision-json.sh + hook.json + plugin.json | ✓ Complete | Deviated — bash 5.3 set-e fix in pretool.sh                      |
| 4.3 | guard-check command + SKILL.md                          | ✓ Complete | 307-char description                                             |
| 5.1 | Extend validate-yci-skills.sh                           | ✓ Complete | Two new validator fns + wired into main                          |
| 6.1 | Hook integration tests                                  | ✓ Complete | 32 assertions across 7 files                                     |
| 6.2 | README + CONTRIBUTING update                            | ✓ Complete | README 199 lines; CONTRIBUTING +18 lines                         |
| 7.1 | Full validate + smoke                                   | ✓ Complete | All 5 levels green                                               |

## Validation Results

| Level                                   | Status | Notes                                                  |
| --------------------------------------- | ------ | ------------------------------------------------------ |
| Static Analysis                         | ✓ Pass | py_compile all `.py`; bash -n all `.sh`                |
| Unit Tests                              | ✓ Pass | 86 assertions in 6 files (`customer-isolation/tests/`) |
| Build                                   | N/A    | No build step (plugin bundle)                          |
| Integration                             | ✓ Pass | 32 assertions in 7 files (`customer-guard/tests/`)     |
| Edge Cases                              | ✓ Pass | Symlink escape, dry-run, fail-open, allowlist bypass   |
| `shellcheck --severity=warning`         | ✓ Pass | Clean on 13 hook + isolation-lib files                 |
| `./scripts/validate.sh --only yci,json` | ✓ Pass | `ALL CHECKS PASSED`                                    |
| `./scripts/validate.sh` (full)          | ✓ Pass | No regressions in existing validators                  |

## Files Changed

### Created (42)

| File                                                                                  | Action  | Lines      |
| ------------------------------------------------------------------------------------- | ------- | ---------- |
| `yci/hooks/customer-guard/hook.json`                                                  | CREATED | +12        |
| `yci/hooks/customer-guard/README.md`                                                  | CREATED | +199       |
| `yci/hooks/customer-guard/references/error-messages.md`                               | CREATED | +208       |
| `yci/hooks/customer-guard/references/capability-gaps.md`                              | CREATED | ~80        |
| `yci/hooks/customer-guard/scripts/pretool.sh`                                         | CREATED | ~140       |
| `yci/hooks/customer-guard/scripts/decision-json.sh`                                   | CREATED | ~40        |
| `yci/hooks/customer-guard/targets/codex/codex-config-fragment.toml`                   | CREATED | +9         |
| `yci/hooks/customer-guard/tests/helpers.sh`                                           | CREATED | ~230       |
| `yci/hooks/customer-guard/tests/run-all.sh`                                           | CREATED | +50        |
| `yci/hooks/customer-guard/tests/test_pretool_allow.sh`                                | CREATED | ~80        |
| `yci/hooks/customer-guard/tests/test_pretool_deny_path.sh`                            | CREATED | ~90        |
| `yci/hooks/customer-guard/tests/test_pretool_deny_fingerprint.sh`                     | CREATED | ~90        |
| `yci/hooks/customer-guard/tests/test_pretool_allowlist_pass.sh`                       | CREATED | ~100       |
| `yci/hooks/customer-guard/tests/test_pretool_dry_run.sh`                              | CREATED | ~90        |
| `yci/hooks/customer-guard/tests/test_pretool_no_active_customer.sh`                   | CREATED | ~100       |
| `yci/hooks/customer-guard/tests/test_pretool_symlink_escape.sh`                       | CREATED | ~80        |
| `yci/skills/_shared/customer-isolation/detect.sh`                                     | CREATED | ~215       |
| `yci/skills/_shared/customer-isolation/references/fingerprint-rules.md`               | CREATED | ~140       |
| `yci/skills/_shared/customer-isolation/scripts/extract-paths.py`                      | CREATED | ~220       |
| `yci/skills/_shared/customer-isolation/scripts/extract-tokens.py`                     | CREATED | ~280       |
| `yci/skills/_shared/customer-isolation/scripts/inventory-fingerprint.py`              | CREATED | ~280       |
| `yci/skills/_shared/customer-isolation/scripts/path-match.sh`                         | CREATED | ~80        |
| `yci/skills/_shared/customer-isolation/scripts/allowlist.sh`                          | CREATED | ~170       |
| `yci/skills/_shared/customer-isolation/tests/helpers.sh`                              | CREATED | ~230       |
| `yci/skills/_shared/customer-isolation/tests/run-all.sh`                              | CREATED | +50        |
| `yci/skills/_shared/customer-isolation/tests/test_allowlist.sh`                       | CREATED | ~140       |
| `yci/skills/_shared/customer-isolation/tests/test_detect.sh`                          | CREATED | ~300       |
| `yci/skills/_shared/customer-isolation/tests/test_extract_paths.sh`                   | CREATED | ~240       |
| `yci/skills/_shared/customer-isolation/tests/test_extract_tokens.sh`                  | CREATED | ~220       |
| `yci/skills/_shared/customer-isolation/tests/test_inventory_fingerprint.sh`           | CREATED | ~200       |
| `yci/skills/_shared/customer-isolation/tests/test_path_match.sh`                      | CREATED | ~80        |
| `yci/skills/_shared/customer-isolation/tests/fixtures/profiles/acme.yaml`             | CREATED | +25        |
| `yci/skills/_shared/customer-isolation/tests/fixtures/profiles/bigbank.yaml`          | CREATED | +25        |
| `yci/skills/_shared/customer-isolation/tests/fixtures/inventories/acme/hosts.yaml`    | CREATED | +3         |
| `yci/skills/_shared/customer-isolation/tests/fixtures/inventories/bigbank/hosts.yaml` | CREATED | +3         |
| `yci/skills/_shared/customer-isolation/tests/fixtures/payloads/*.json`                | CREATED | 7 fixtures |
| `yci/skills/customer-guard/SKILL.md`                                                  | CREATED | ~70        |
| `yci/commands/guard-check.md`                                                         | CREATED | ~20        |

Totals: ~4,990 lines across 42 new files.

### Modified (3)

| File                             | Action  | Change                                                                                      |
| -------------------------------- | ------- | ------------------------------------------------------------------------------------------- |
| `yci/.claude-plugin/plugin.json` | UPDATED | Added `"hooks": "hooks/customer-guard/hook.json"`                                           |
| `yci/CONTRIBUTING.md`            | UPDATED | Added "Guard-hook discipline" subsection (+18 lines)                                        |
| `scripts/validate-yci-skills.sh` | UPDATED | Added `validate_customer_guard_hook` + `validate_customer_isolation_lib`; wired into `main` |

## Deviations from Plan

1. **`load-profile.sh` flag shape (Task 2.3)** — The plan assumed `--data-root / --customer / --format json` flags, but the actual script uses positional arguments: `load-profile.sh <data-root> <customer>`. The agent correctly read the script first and adapted the subprocess call to positional form. Documented inline in the new Python script.

2. **`detect.sh` foreign-customer enumeration (Task 3.2 + post-batch fix)** — The original logic used `basename "$f" .yaml` on every `*.yaml` file in `profiles/`, which incorrectly picks up `<customer>.allowlist.yaml` files as separate "foreign customers". Added a `*.allowlist` case filter alongside the existing `_*` skip. Fixed in-place before Batch 5; verified by the unit-test suite.

3. **bash 5.3 `set -e` regression in pretool.sh (Task 4.2 + Task 6.1)** — On bash 5.3, a failing command substitution on the RHS of an assignment triggers `set -e` exit even though the assignment itself succeeds. Original code was `ACTIVE_OUT="$(bash "$RESOLVE" 2>&1)"; ACTIVE_RC=$?` which exits before reaching the fail-closed branch. Fixed by pre-initializing `ACTIVE_RC=0` and using the `|| ACTIVE_RC=$?` idiom to suppress the early exit.

4. **Sourceable-library executable convention (Task 7.1)** — Plan's per-task specs (3.1, 3.2, 4.2) said "DO NOT chmod +x" sourceable libraries, but the repo-wide convention (see `yci/skills/customer-profile/scripts/state-io.sh`) is that sourceable libraries ARE executable — they just don't self-enable `set -euo pipefail` at file scope. Aligned with repo convention: chmod +x'd all 4 sourceable libraries (`decision-json.sh`, `path-match.sh`, `allowlist.sh`, `detect.sh`) and updated the new validator functions to accept executable-but-no-set-euo as valid.

5. **Additional documentation regex compile verification (Task 1.3)** — The plan said "not here" for regex compile validation, but the agent verified all 7 regexes compile cleanly in Python as part of VALIDATE. No change to the deliverable; just a stronger validation.

## Issues Encountered

1. **zsh vs bash during smoke-testing** — My initial between-batch smoke test ran under zsh (the user's interactive shell), where `BASH_SOURCE[0]` is empty. The detect.sh guards fell back to a cwd-relative path and all sourced helpers failed. Re-ran under an explicit `bash -c` subshell and everything worked. Documented in the smoke-test commands so future tests always wrap in `bash -c`.

2. **Test fixture schema strictness** — Minimal test profiles (`customer` + `inventory` only) fail `load-profile.sh`'s schema validation. All fixtures in both test suites were built using the full required-field template (13 top-level + nested fields). Documented inline in both test helpers.

3. **`customer-id` token false-positives in allowlist-bypass tests** — The `customer-id` category regex is intentionally loose (`[a-z0-9][a-z0-9-]{2,63}`) and matches the foreign customer's id anywhere in the payload. For `test_pretool_allowlist_pass.sh`, allowlisting only the path leaves the foreign customer-id token as a second deny trigger. Worked around by using a fictional customer name (`zbank` with `zhost01.zbank.net`) and allowlisting both the path prefix AND the `customer-id:zbank` token. This correctly exercises full-bypass semantics.

4. **`__pycache__` artifacts** — Running `py_compile` during validation generated `.pyc` files under `__pycache__`. The repo `.gitignore` covers `__pycache__/` so these wouldn't be tracked, but cleaned up manually to keep the working tree tidy.

## Tests Written

| Test File                                                                   | Assertions                          | Coverage                                      |
| --------------------------------------------------------------------------- | ----------------------------------- | --------------------------------------------- |
| `yci/skills/_shared/customer-isolation/tests/test_allowlist.sh`             | 11                                  | load/query, malformed, dict/list forms        |
| `yci/skills/_shared/customer-isolation/tests/test_detect.sh`                | 20                                  | end-to-end allow/deny/allowlist-bypass        |
| `yci/skills/_shared/customer-isolation/tests/test_extract_paths.sh`         | 19                                  | all 10 tool types + truncation + invalid JSON |
| `yci/skills/_shared/customer-isolation/tests/test_extract_tokens.sh`        | 18                                  | 7 categories + whitelist + content cap        |
| `yci/skills/_shared/customer-isolation/tests/test_inventory_fingerprint.sh` | 12                                  | cache, malformed, path override               |
| `yci/skills/_shared/customer-isolation/tests/test_path_match.sh`            | 6                                   | partial-segment, symlink, equality            |
| `yci/hooks/customer-guard/tests/test_pretool_allow.sh`                      | 4                                   | own path + missing fields fail-open           |
| `yci/hooks/customer-guard/tests/test_pretool_deny_path.sh`                  | 5                                   | path-collision deny                           |
| `yci/hooks/customer-guard/tests/test_pretool_deny_fingerprint.sh`           | 5                                   | fingerprint-collision deny                    |
| `yci/hooks/customer-guard/tests/test_pretool_allowlist_pass.sh`             | 2                                   | allowlist bypass                              |
| `yci/hooks/customer-guard/tests/test_pretool_dry_run.sh`                    | 5                                   | DRY-RUN banner + audit.log                    |
| `yci/hooks/customer-guard/tests/test_pretool_no_active_customer.sh`         | 7                                   | fail-closed default + fail-open opt-in        |
| `yci/hooks/customer-guard/tests/test_pretool_symlink_escape.sh`             | 4                                   | symlink resolves to foreign root              |
| **TOTAL**                                                                   | **118 assertions in 13 test files** | **Unit + integration**                        |

## Next Steps

- [ ] Code review via `/ycc:code-review`
- [ ] Create PR via `/ycc:prp-pr`
- [ ] Follow-up: Phase 1a generator extension (cross-target `yci` bundle emission for Cursor / Codex / opencode)
- [ ] Follow-up: Phase 1b functional hook implementations for non-Claude targets per `references/capability-gaps.md`
- [ ] Follow-up: validator tightening to flag allowlist entries without `note:` field (documented in README as known future work)
