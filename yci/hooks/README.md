# yci hooks

This directory contains all PreToolUse hooks shipped by the yci plugin. Both hooks are registered at
runtime via the combined manifest `hooks.json`, which is what `yci/.claude-plugin/plugin.json`
points at.

## Execution order

Hooks in `hooks.json` run top-to-bottom under a shared `matcher: "*"`. The order is load-bearing:

1. `customer-guard` — fails closed if there is no active profile, blocks cross-customer references.
   See `customer-guard/`.
2. `change-window-gate` — fails closed during freeze / blackout windows per the active profile's
   `change_window.adapter`. See `change-window-gate/`.

customer-guard runs first so its deny decisions short-circuit the chain. change-window-gate does not
duplicate customer-guard's no-active-profile logic; it classifies by purpose instead (see
`change-window-gate/README.md` §"No active profile").

## Standalone fallbacks

Each hook directory still carries its own `hook.json` for direct invocation / debugging. The
combined `hooks.json` is what the plugin runtime loads.
