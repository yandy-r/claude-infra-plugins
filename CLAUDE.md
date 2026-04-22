# claude-infra-plugins — Project Instructions

## Overview

This repository ships the `yci` Claude Code plugin from a single marketplace at
`.claude-plugin/marketplace.json`. `yci` — Yandy's Claude Infrastructure toolkit — covers consulting
and systems-integration workflows: customer profiles, compliance adapters, customer-guard PreToolUse
hook, change-window enforcement, blast-radius analysis, network-change review, and evidence-bundle
packaging. Source lives under `yci/`; reached at Claude runtime as `yci:{skill}`, `/yci:{command}`,
and `subagent_type: "yci:{agent}"`.

> **Provenance**: `yci` was extracted from `yandy-r/claude-plugins` in 2026-04. The extraction was
> driven by the customer-guard PreToolUse hook, which fail-closes on every tool call when no
> customer is active — correct for customer-engagement work, wrong for a dev-only repo. Git history
> for every yci-owned path was preserved via `git filter-repo` (`git log -- yci/` shows the full
> pre-extraction trail). See `docs/prps/prds/yci.prd.md` for the product rationale.

## Scope

- **Phase 0 (current)**: Claude-native only. No Cursor / Codex / opencode generator fleet; no
  cross-target bundle regeneration. yci ships at Claude runtime via
  `yci/.claude-plugin/plugin.json`.
- **Phase 1+**: cross-target bundle support will be scoped once the skill surface stabilizes and the
  compliance-adapter pattern has at least two live customer regimes. Cross-target parity is an
  explicit non-goal until then.

## Repository Layout

```text
claude-infra-plugins/
├── .claude-plugin/
│   └── marketplace.json      # single plugin entry (yci)
├── yci/                      # yci plugin source
│   ├── .claude-plugin/
│   │   └── plugin.json       # name: "yci"
│   ├── CONTRIBUTING.md       # yci-specific policy (non-goals, adapter pattern)
│   ├── hooks/
│   │   └── customer-guard/   # PreToolUse hook (shipped)
│   ├── skills/
│   │   ├── _shared/          # customer-isolation, inventory-adapters, compliance-adapters
│   │   └── {skill-name}/
│   │       ├── SKILL.md
│   │       ├── references/
│   │       ├── scripts/
│   │       └── tests/
│   ├── agents/               # (Phase 1+)
│   ├── commands/             # (Phase 1+)
│   └── docs/
└── docs/
    └── prps/
        ├── prds/yci.prd.md   # product requirements document
        ├── reports/          # implementation reports
        └── plans/            # implementation plans
```

## Plugin Development Conventions

### Naming

- The plugin namespace `yci:` is stable and must NOT change.
- Skills: `kebab-case` directory under `yci/skills/`. The directory name becomes the skill
  identifier within the plugin's namespace (e.g., `yci/skills/hello/` → `yci:hello`).
- Commands: `kebab-case.md` under `yci/commands/`. The basename becomes the slash command (e.g.,
  `yci/commands/init.md` → `/yci:init`).
- Agents: `kebab-case.md` under `yci/agents/`. The basename becomes the agent identifier (e.g.,
  `yci/agents/blast-radius.md` → `subagent_type: "yci:blast-radius"`).
- Scripts: `kebab-case.sh` with bash shebang.

### Scripts

All scripts must:

- Start with `#!/usr/bin/env bash`
- Use `set -euo pipefail` for safety (hook entrypoints use `set -uo pipefail` — no `-e` — so they
  can aggregate decision logic)
- Include validation guards (check required inputs exist)
- Exit with meaningful codes (0 = success, 1 = error)
- Write output to stdout, errors to stderr

When a script needs to reference its own plugin path, use `${CLAUDE_PLUGIN_ROOT}` — this resolves to
the plugin's source directory at runtime (`yci/`). Paths inside skills follow the form
`${CLAUDE_PLUGIN_ROOT}/skills/{skill-name}/...`.

### Skills

Each skill directory contains:

- `SKILL.md` — the skill prompt (required)
- `references/` — templates, examples, and reference docs
- `scripts/` — validation and helper scripts
- `tests/` — `run-all.sh` + `helpers.sh` + `test_*.sh` + fixtures (validator picks these up)

### Cross-skill helpers

Shared helpers (used by more than one skill within yci) live under `yci/skills/_shared/scripts/`.
Skills source them via `${CLAUDE_PLUGIN_ROOT}/skills/_shared/scripts/{name}.sh`.

### Adapter patterns

yci uses dispatcher-per-adapter tables for inventory, compliance, and (Phase 2+) change-window
enforcement. Each adapter is a directory under
`yci/skills/_shared/<category>-adapters/<adapter-name>/` with `ADAPTER.md` + `scripts/check.sh` (or
equivalent). A shared `load-<category>-adapter.sh` in `yci/skills/_shared/scripts/` dispatches. See
`yci/CONTRIBUTING.md` and the PRD §5.4 for the canonical pattern.

### Registration

The marketplace registry at `.claude-plugin/marketplace.json` contains a single entry: `yci`. Adding
additional plugins would require splitting into a new repo rather than accumulating plugins here —
this repo is deliberately single-plugin to keep the customer-guard hook scope contained.

## Testing Changes

After modifying anything under `yci/`:

1. Validate JSON:
   - `python3 -m json.tool .claude-plugin/marketplace.json`
   - `python3 -m json.tool yci/.claude-plugin/plugin.json`
2. Verify all `${CLAUDE_PLUGIN_ROOT}` paths resolve (no broken references).
3. Confirm shell scripts remain executable: `find yci -name "*.sh" -not -executable` (should output
   nothing).
4. Run the full validator:

   ```bash
   ./scripts/validate.sh
   ```

5. Test the skill or command in a live Claude Code session via its `yci:` prefix.

The validator (`scripts/validate.sh`) is the single CI entrypoint; it covers frontmatter lint,
script shebang / safety flags, executability, shellcheck clean, adapter completeness, catalog
shapes, and all test harnesses under `yci/**/tests/`.

## Precedence

1. System, developer, and explicit user instructions for the task.
2. This file and [`AGENTS.md`](AGENTS.md) as repo policy.
3. [`yci/CONTRIBUTING.md`](yci/CONTRIBUTING.md) for yci-specific rules (compliance-adapter pattern,
   non-goals, customer-data policy).
4. General best practices when nothing above conflicts.

## MUST / MUST NOT

- **Secrets**: **Never** commit `.env`, `.env.encrypted`, tokens, or API keys.
- **Customer data**: **Never** commit customer-identifying data, SOW references, or inventory
  exports. Profiles are documented as secret-free per PRD §11.9; customer data lives outside the
  repo in `$YCI_DATA_ROOT` (defaults to `~/.config/yci/`).
- **Issues**: Use the YAML form templates under `.github/ISSUE_TEMPLATE/` when present.
- **Pull requests**: Follow `.github/pull_request_template.md`. Always link the related issue
  (`Closes #…`).
- **Commits**: Use **Conventional Commits 1.0.0** —
  `feat|fix|docs|refactor|perf|test|build|ci|chore(scope): …`.
- **Internal docs commits**: Files under `docs/plans`, `docs/prps`, or `docs/internal` must use
  `docs(internal): …`.
- **Large features**: Split into smaller phases and tasks with clear dependencies and order of
  execution.
- **File size (~500 lines)**: Aim for **around 500 lines** per file as a soft cap. Files that drift
  meaningfully past that must be refactored into smaller modules.
- **Modularity & reuse**: Decompose into small, cohesive units with minimal cross-module coupling.
  No copy-paste duplication.
- **Single responsibility**: Each function, module, and component must have one clear reason to
  exist.
- **MCP**: When an MCP server fits the task (GitHub, docs, browser, etc.), prefer it. Read each
  tool's schema before calling.

## SHOULD (implementation)

### General

- **Naming**: Intention-revealing names for functions, types, and modules.
- **No dead code**: Remove unused code, imports, and commented-out blocks.
- **Dependency hygiene**: Before adding a new dependency, check whether an existing one does the
  job.
- **Fail fast at boundaries**: Validate inputs at module and system boundaries; propagate via typed
  errors.
- **Tests alongside changes**: New or modified behavior ships with tests in the same change.
- **Default to worktrees**: For non-trivial work, start in a git worktree instead of the main
  checkout.

### Languages

- **Shell** (`scripts/*.sh`, `yci/hooks/*/scripts/*.sh`, `yci/skills/*/scripts/*.sh`):
  `#!/usr/bin/env bash` + `set -euo pipefail` (hook entrypoints may use `set -uo pipefail` if they
  aggregate decision logic); validation guards on required inputs; stdout for results, stderr for
  errors.
- **Python** (embedded in shell scripts for JSON / YAML parsing): stdlib only unless justified; no
  runtime dependencies beyond `pyyaml` (already a dev-dep).

## Git & Conventional Commits

Every commit title must match:

```text
<type>[optional scope]: <description>
```

### Types

| Type       | Purpose                                     | Version bump |
| ---------- | ------------------------------------------- | ------------ |
| `feat`     | New user-facing feature                     | minor        |
| `fix`      | User-facing bug fix                         | patch        |
| `docs`     | Documentation only                          | —            |
| `refactor` | Code change that is neither fix nor feature | —            |
| `perf`     | Performance improvement                     | —            |
| `test`     | Adding or correcting tests                  | —            |
| `build`    | Build system or external dependency changes | —            |
| `ci`       | CI/CD configuration changes                 | —            |
| `chore`    | Other non-user-facing changes               | —            |

### Scope

`feat(customer-profile): …` — scope is the skill, hook, or adapter being changed. Keep it concise.

### Breaking changes

Append `!` after the type/scope (`feat!: …`) **or** add a `BREAKING CHANGE: …` footer.

### Internal docs

Use `docs(internal): …` for files under `docs/plans`, `docs/prps`, or `docs/internal`. These stay
out of release notes.

## Git Worktrees

**Strong preference**: work in a git worktree for any non-trivial task.

- **Preferred parent**: `~/.claude-worktrees/` for all agent-managed worktrees, named
  `<repo>-<branch>/`. Keeps them outside every repo and trivially bulk-clean.
- **Manual creation**: when invoking `git worktree add` yourself, target
  `~/.claude-worktrees/<repo>-<branch>/` — never a path inside the current repo.
- **Repo hygiene**: if the harness has created `.claude/worktrees/`, add `.claude/worktrees/` to
  `.gitignore` before committing.

## GitHub Workflow

- **Labels**: Use only the project's defined label taxonomy (`type:`, `area:`, `priority:`,
  `status:` families). Never create ad-hoc labels.
- **Issues**: File an issue before starting non-trivial work. Link the issue number in the PR
  (`Closes #…`).
- **PRs**: Follow the PR template; fill every checklist item honestly. Small, focused PRs over large
  omnibus ones.

## Stack Overview

| Layer            | Technology                                        | Notes                                                            |
| ---------------- | ------------------------------------------------- | ---------------------------------------------------------------- |
| Primary language | Bash + Python (stdlib mostly)                     | Hook entrypoints, adapter `check.sh`, embedded JSON/YAML parsing |
| Test harness     | Bash-based `tests/run-all.sh` per skill / adapter | Invoked by `scripts/validate.sh`                                 |
| Package manager  | npm (lint/format only)                            | No test or build target via npm                                  |
| CI               | GitHub Actions + pinned shellcheck 0.10.0         | See `.github/workflows/validate.yml`                             |

## Commands

```bash
# One-time: install pinned shellcheck (matches .tool-versions; same binary as CI)
./scripts/install-shellcheck.sh

# Validate the full bundle (what CI runs)
./scripts/validate.sh
```

Testing and validation are defined in `## Testing Changes` above — JSON validation plus the
validator pipeline are the real verification loop for this repository.
