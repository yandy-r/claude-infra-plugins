#!/usr/bin/env bash
# excludes.sh — canonical list of well-known paths every formatter/linter skips.
#
# Source from any script that filters repo paths:
#   # shellcheck source=./excludes.sh
#   . "${BASH_SOURCE%/*}/excludes.sh"
#
# Consumers: modified-files.sh filter step. Tool-config templates under
# ../templates/ maintain parallel lists by hand — keep them aligned with this
# array (see the "canonical excludes" comment at the top of each template).

if [[ -n "${STYLE_EXCLUDES_LOADED:-}" ]]; then
    return 0
fi
readonly STYLE_EXCLUDES_LOADED=1

# Paths are matched against repo-relative file paths: a path is excluded when
# it equals any entry OR begins with "<entry>/". Keep entries in the form
# they appear in the worktree (no leading or trailing slash).
STYLE_EXCLUDES=(
    # Language package / build output
    node_modules
    target
    build
    dist
    out
    coverage
    vendor

    # Python environments & cache
    .venv
    venv
    env
    __pycache__
    .mypy_cache
    .pytest_cache
    .ruff_cache

    # JS meta-framework caches
    .next
    .nuxt
    .cache

    # Infrastructure tooling
    .terraform

    # Generated plugin bundles (this repo's source-of-truth pattern; harmless
    # as defaults because these names are specific to ycc).
    .cursor-plugin
    .codex-plugin
    .opencode-plugin
)
