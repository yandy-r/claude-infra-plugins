# Contributing to claude-infra-plugins

Thanks for your interest. This repo ships the `yci` Claude Code plugin — Yandy's Claude
Infrastructure toolkit for consulting and systems-integration work.

This document covers the cross-cutting repo policy (scope, structure, validation, commits).
Plugin-specific rules (non-goals, compliance-adapter pattern, customer-data policy) live in
[`yci/CONTRIBUTING.md`](yci/CONTRIBUTING.md).

## Before You Start

1. **Read `CLAUDE.md`** at the repo root for repo-wide conventions.
2. **Read `yci/CONTRIBUTING.md`** for plugin-specific rules — especially the non-goals, the
   compliance-adapter pattern, and the customer-data policy.
3. **Read the PRD** at `docs/prps/prds/yci.prd.md` for product rationale and phased rollout.
4. **File an issue first** for any non-trivial change so scope can be discussed.

## Scope & Guardrails

This repository is deliberately **single-plugin**. The `yci` plugin is the sole entry in
`.claude-plugin/marketplace.json`. Adding new capability should land inside `yci/` as a new skill,
command, agent, hook, or adapter — not as a second plugin.

The bar for splitting yci into multiple plugins is high: a scope that cannot coexist with the rest
of yci without harming it (cross-contamination, descriptor pollution, fragility-cliff proximity).
The existing sibling split — [`yandy-r/claude-plugins`](https://github.com/yandy-r/claude-plugins)
shipping `ycc`, and this repo shipping `yci` — is the reference example of the level of rigor
required: problem statement, audience, threat model, non-goals, phased rollout, success criteria.
The original yci PRD (`docs/prps/prds/yci.prd.md`) documents the decision that drove that split.

### Decision gate for new surface

Before proposing a new skill / command / agent:

- Does this belong in `yci`? If yes, add it under `yci/skills/`, `yci/commands/`, or `yci/agents/`.
- Does this belong in `ycc` (dev-workflow)? If yes, PR it in
  [`yandy-r/claude-plugins`](https://github.com/yandy-r/claude-plugins) instead.
- Does this warrant a new top-level plugin? Write a PRD under `docs/prps/prds/` first and open an
  issue to discuss. Default answer is no.

## Structure Requirements

- Plugin source: `yci/`
- Claude source plugin manifest: `yci/.claude-plugin/plugin.json`
- Marketplace registry: `.claude-plugin/marketplace.json` (single entry)
- Hooks: `yci/hooks/<hook-name>/{hook.json,scripts/pretool.sh,README.md,references/}`
- Skills: `yci/skills/<skill-name>/{SKILL.md,references/,scripts/,tests/}`
- Shared helpers: `yci/skills/_shared/`
- Cross-skill adapter tables:
  `yci/skills/_shared/<category>-adapters/<adapter>/{ADAPTER.md,scripts/}`
- Validator: `scripts/validate.sh` (single entrypoint; CI runs this)

## Validation

Before opening a PR:

```bash
# One-time: install pinned shellcheck
./scripts/install-shellcheck.sh

# Validate the bundle
./scripts/validate.sh
```

JSON manifests must be parseable:

```bash
python3 -m json.tool .claude-plugin/marketplace.json
python3 -m json.tool yci/.claude-plugin/plugin.json
```

Every shell script must be executable:

```bash
find yci scripts -name "*.sh" -not -executable  # should be empty
```

CI runs `./scripts/validate.sh` on every push and PR via
[`.github/workflows/validate.yml`](.github/workflows/validate.yml). The local validator and the CI
validator are the same binary path; if it passes locally, it passes in CI.

## Commits

Use **Conventional Commits 1.0.0**. Every commit title must match:

```text
<type>[optional scope]: <description>
```

Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`. Scope is the
skill, hook, or adapter (e.g., `feat(customer-profile): …`).

Internal-docs changes under `docs/plans`, `docs/prps`, or `docs/internal` use `docs(internal): …`
and stay out of release notes.

Breaking changes: append `!` (`feat!: …`) or add a `BREAKING CHANGE: …` footer.

## Pull Requests

- Fill in the PR template — every checklist item honestly.
- Link the issue (`Closes #…`).
- Keep PRs focused. Prefer several small PRs to one large omnibus.
- Label the PR using the project taxonomy (`type:`, `area:`, `priority:`). Do not invent ad-hoc
  labels.

## Labels

Use only the project's defined label taxonomy. Common families:

- `type:` bug, feature, docs, refactor, compatibility, build, migration
- `area:` customer-profile, customer-guard, blast-radius, evidence-bundle, network-change-review,
  change-window-gate, adapters
- `priority:` critical, high, medium, low
- `status:` needs-triage, in-progress, blocked, needs-info
- Standalone: `good first issue`, `help wanted`, `duplicate`, `wontfix`

## License

By contributing you agree that your contributions are licensed under the repository's
[MIT license](LICENSE).
