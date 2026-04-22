# claude-infra-plugins

Single-marketplace Claude Code plugin (`yci`) for consulting and systems-integration workflows:
customer profiles, compliance adapters, customer-guard PreToolUse hook, blast-radius analysis,
network-change review, and evidence-bundle packaging.

Full agent rules live in [`CLAUDE.md`](../../CLAUDE.md). Key points surfaced for AI tooling:

## Rules

- Follow Conventional Commits for every commit:
  `feat|fix|docs|refactor|perf|test|build|ci|chore(scope): …`.
- Never commit `.env` / secrets / tokens. Never commit customer-identifying data, SOW references, or
  inventory exports — customer data lives in `$YCI_DATA_ROOT` (defaults to `~/.config/yci/`), not
  the repo.
- Use `.github/ISSUE_TEMPLATE/*.yml` when present; link `Closes #…` in every PR.
- Keep files around ~500 lines (soft cap). Refactor meaningful overruns into smaller modules.
- Modular code: small cohesive units, DRY, composition over inheritance, single responsibility.
- Prefer working in a git worktree for non-trivial changes —
  `git worktree add ~/.claude-worktrees/<repo>-<branch>/`. Use the main checkout only for one-liners
  or when worktree creation is blocked.
- Shell scripts: `#!/usr/bin/env bash` + `set -euo pipefail`; hook entrypoints may use
  `set -uo pipefail` if they aggregate decision logic.
- Python: stdlib only unless justified; runtime deps limited to `pyyaml` (existing dev-dep).
- yci is Claude-native only in Phase 0 — do not attempt to generate Cursor / Codex / opencode
  bundles. See [`CLAUDE.md`](../../CLAUDE.md) § Scope.
- yci-specific policy (non-goals, compliance-adapter pattern, customer-data rule) lives in
  [`yci/CONTRIBUTING.md`](../../yci/CONTRIBUTING.md).

## Verification

Run `./scripts/validate.sh` before marking work complete. The validator covers frontmatter lint,
script shebang/safety flags, executability, shellcheck, adapter completeness, catalog shapes, and
all `yci/**/tests/` harnesses.
