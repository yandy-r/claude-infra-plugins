# claude-infra-plugins

Yandy's Claude Infrastructure (`yci`) plugin for Claude Code — customer profiles, compliance adapters, customer-isolation PreToolUse hook, change-window enforcement, blast-radius analysis, network-change review, and evidence-bundle packaging for consulting and systems-integration engagements.

> **Provenance**: `yci` was originally developed in [`yandy-r/claude-plugins`](https://github.com/yandy-r/claude-plugins) alongside `ycc`. It was extracted into this sibling repo in 2026-04 so the customer-guard PreToolUse hook no longer fires in the ycc dev workspace. Git history for every yci-owned path survives the move (`git log -- yci/` shows the full trail). See [`docs/prps/prds/yci.prd.md`](docs/prps/prds/yci.prd.md) for the product rationale.

## What's inside

- **`yci:customer-profile`** — load / switch / init the active customer profile (engagement-scoped identity, inventory adapter, compliance adapter, change-window adapter, safety posture).
- **`yci:customer-guard`** — PreToolUse hook that fail-closes on cross-customer path / identifier collisions. Catalogued deny reasons; dry-run and fail-open env knobs for development.
- **`yci:hello`** — Phase-0 proof-of-life skill (will be replaced by `yci:whoami` once the customer-profile machinery lands end-to-end).
- **Adapter patterns** — inventory (netbox stub), compliance (HIPAA / PCI / SOC2 / none), change-window (iCal / JSON-schedule / always-open / none). All under `yci/skills/_shared/`.
- **Planned** (Phase 2+): `yci:blast-radius`, `yci:evidence-bundle`, `yci:network-change-review`, `yci:change-window-gate` hook — see [PRD §6](docs/prps/prds/yci.prd.md#6-phased-rollout) for the phased rollout.

## Installation

```bash
# Add the marketplace
/plugin marketplace add yandy-r/claude-infra-plugins

# Install the plugin
/plugin install yci@yci
```

Or enable in `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "yci@yci": true
  }
}
```

## Scope

- **Phase 0 (current)**: Claude-native only. No Cursor / Codex / opencode generator fleet. yci ships at Claude runtime via `yci/.claude-plugin/plugin.json`.
- **Phase 1+**: cross-target bundle support will be scoped once the skill surface stabilizes. Cross-target parity is an explicit non-goal until the compliance-adapter pattern has at least two live customer regimes.

## Repository Layout

```
claude-infra-plugins/
├── .claude-plugin/
│   └── marketplace.json      # single plugin entry (yci)
├── yci/
│   ├── .claude-plugin/
│   │   └── plugin.json       # name: "yci"
│   ├── CONTRIBUTING.md       # yci-specific policy (non-goals, adapter pattern)
│   ├── hooks/
│   │   └── customer-guard/   # PreToolUse hook
│   ├── skills/
│   │   ├── _shared/          # cross-skill helpers (customer-isolation, adapters, schema)
│   │   ├── customer-profile/ # load / switch / init profiles
│   │   ├── customer-guard/   # guard-check operator skill
│   │   └── hello/            # Phase-0 proof-of-life
│   ├── agents/               # (Phase 1+)
│   ├── commands/             # (Phase 1+)
│   └── docs/
│       ├── profiles.md
│       └── profiles/_internal.yaml.example
├── docs/
│   └── prps/
│       ├── prds/yci.prd.md   # product requirements document
│       ├── reports/          # implementation reports (archived)
│       └── plans/            # implementation plans (archived)
└── scripts/
    ├── validate.sh           # single entrypoint; CI runs this on push/PR
    ├── install-shellcheck.sh
    └── lib/shellcheck-resolve.sh
```

## Development

```bash
# One-time: install pinned shellcheck (matches .tool-versions)
./scripts/install-shellcheck.sh

# Validate the bundle
./scripts/validate.sh
```

CI runs `./scripts/validate.sh` on every push and pull request via [`.github/workflows/validate.yml`](.github/workflows/validate.yml).

## Contributing

Before proposing a new skill, command, or agent, read the Scope & Guardrails policy in [`CONTRIBUTING.md`](CONTRIBUTING.md) and the yci-specific non-goals and compliance-adapter rules in [`yci/CONTRIBUTING.md`](yci/CONTRIBUTING.md).

## Related

- [`yandy-r/claude-plugins`](https://github.com/yandy-r/claude-plugins) — sibling repo shipping the `ycc` development-workflow plugin.

## License

[MIT](LICENSE)
