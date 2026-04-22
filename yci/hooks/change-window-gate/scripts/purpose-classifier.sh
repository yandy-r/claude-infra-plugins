#!/usr/bin/env bash
# yci — change-window-gate purpose-classifier library.
#
# Sourceable bash library (no top-level side effects). Exposes two pure
# classification functions used by the change-window-gate PreToolUse hook
# entrypoint (pretool.sh) to decide whether a tool call is init/setup or
# customer-artifact creation when no customer profile is active.
#
# Design note (D7 revision): when no profile is loaded the hook cannot consult
# a customer's change-window posture. Rather than blanket-blocking all tool
# calls (which breaks bootstrapping) or blanket-allowing them (which defeats
# the purpose of the gate), the hook classifies the call by purpose:
#   • init/setup/observation → allow
#   • customer-artifact creation → block
#   • anything else destructive → block (handled by the hook's default branch)
#
# Functions:
#   cwg_is_init_path <tool_name> <tool_input_json>
#     Returns 0 when the tool call is init/setup/dependency-resolution safe.
#     Returns 1 otherwise.
#
#   cwg_is_artifact_creation <tool_name> <tool_input_json>
#     Returns 0 when the tool call creates customer artifacts.
#     Returns 1 otherwise.
#
# Both functions are pure (no state, no side effects). Call independently.
# Do NOT add `set -euo pipefail` here — this file is sourced.

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

# _cwg_resolve_data_root
# Prints the resolved YCI data root (no trailing slash).
# Honors $YCI_DATA_ROOT envvar; falls back to $HOME/.config/yci.
_cwg_resolve_data_root() {
    local root
    root="${YCI_DATA_ROOT:-${HOME}/.config/yci}"
    # Strip any trailing slashes.
    root="${root%/}"
    printf '%s' "$root"
}

# _cwg_extract_path_from_input <tool_input_json>
# Prints the file_path or notebook_path from the JSON, or empty string.
_cwg_extract_path_from_input() {
    local tool_input="${1:-}"
    python3 -c \
        'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("file_path") or d.get("notebook_path") or "")' \
        <<< "$tool_input" 2>/dev/null || true
}

# _cwg_extract_command_from_input <tool_input_json>
# Prints the command field from the JSON, or empty string.
_cwg_extract_command_from_input() {
    local tool_input="${1:-}"
    python3 -c \
        'import json,sys; d=json.loads(sys.stdin.read()); print(d.get("command") or "")' \
        <<< "$tool_input" 2>/dev/null || true
}

# _cwg_nth_token <n> <command_string>
# Prints the Nth token (1-based) from command_string using shlex.split.
# Prints empty string when there are fewer than N tokens.
_cwg_nth_token() {
    local n="${1:-1}"
    local cmd="${2:-}"
    python3 -c \
        'import shlex,sys; idx=int(sys.argv[1])-1; t=shlex.split(sys.argv[2]); print(t[idx] if idx < len(t) else "")' \
        "$n" "$cmd" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# cwg_is_init_path <tool_name> <tool_input_json>
# ---------------------------------------------------------------------------
# Returns 0 (is init) for observation tools, profile scaffolding, and
# package-manager / dependency-resolution Bash commands.
# Returns 1 otherwise.
cwg_is_init_path() {
    local tool_name="${1:-}"
    local tool_input="${2:-}"

    case "$tool_name" in
        # Observation / read-only tools: always init-safe.
        Read|Grep|Glob|WebFetch|WebSearch)
            return 0
            ;;

        # Write-family: init-safe only when writing under profiles/.
        Write|Edit|NotebookEdit)
            local file_path data_root
            file_path="$(_cwg_extract_path_from_input "$tool_input")"
            data_root="$(_cwg_resolve_data_root)"
            if [[ -n "$file_path" && "$file_path" == "${data_root}/profiles/"* ]]; then
                return 0
            fi
            return 1
            ;;

        # Bash: classify by first (and optionally second) token.
        Bash)
            local cmd token0 token1
            cmd="$(_cwg_extract_command_from_input "$tool_input")"
            [[ -z "$cmd" ]] && return 1

            token0="$(_cwg_nth_token 1 "$cmd")"
            token1="$(_cwg_nth_token 2 "$cmd")"

            # Basename of token0 to handle absolute paths like /usr/bin/npm.
            local base0
            base0="$(basename "$token0")"

            case "$base0" in
                # Node.js / JS package managers — any subcommand is init.
                npm|pnpm|yarn|bun)
                    return 0
                    ;;

                # Python package managers — any subcommand is init.
                pip|pip3|uv|poetry|pipx)
                    return 0
                    ;;

                # System package managers — any subcommand is init.
                brew|apt|apt-get|dnf|yum|pacman|port)
                    return 0
                    ;;

                # Version / runtime managers — any subcommand is init.
                asdf|mise|rtx|nvm|pyenv|rbenv)
                    return 0
                    ;;

                # Rust, Go, Ruby: only `install` subcommand is init.
                cargo|go|gem)
                    if [[ "$token1" == "install" ]]; then
                        return 0
                    fi
                    return 1
                    ;;

                # Git: only clone and submodule operations are init.
                git)
                    case "$token1" in
                        clone|submodule)
                            return 0
                            ;;
                        *)
                            return 1
                            ;;
                    esac
                    ;;

                # yci-init literal command — init path.
                yci-init)
                    return 0
                    ;;

                *)
                    # Check for /yci:init slash-command syntax embedded in Bash.
                    case "$cmd" in
                        */yci:init*)
                            return 0
                            ;;
                    esac
                    return 1
                    ;;
            esac
            ;;

        # All other tool types: not init.
        *)
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# cwg_is_artifact_creation <tool_name> <tool_input_json>
# ---------------------------------------------------------------------------
# Returns 0 (is artifact creation) for writes under $YCI_DATA_ROOT/artifacts/
# or Bash commands that explicitly redirect/create under that path.
# Returns 1 otherwise.
cwg_is_artifact_creation() {
    local tool_name="${1:-}"
    local tool_input="${2:-}"

    case "$tool_name" in
        # Write-family: artifact when writing under artifacts/.
        Write|Edit|NotebookEdit)
            local file_path data_root
            file_path="$(_cwg_extract_path_from_input "$tool_input")"
            data_root="$(_cwg_resolve_data_root)"
            if [[ -n "$file_path" && "$file_path" == "${data_root}/artifacts/"* ]]; then
                return 0
            fi
            # Also catch paths containing /artifacts/ segment where the
            # leading component is the data root (handles sub-paths).
            if [[ -n "$file_path" && "$file_path" == "${data_root}/"*"/artifacts/"* ]]; then
                return 0
            fi
            return 1
            ;;

        # Bash: match simple shell redirections and mkdir targeting artifacts/.
        Bash)
            local cmd data_root
            cmd="$(_cwg_extract_command_from_input "$tool_input")"
            data_root="$(_cwg_resolve_data_root)"
            [[ -z "$cmd" ]] && return 1

            # Simple redirection patterns: > path or >> path.
            if [[ "$cmd" == *">${data_root}/artifacts/"* || \
                  "$cmd" == *">>${data_root}/artifacts/"* ]]; then
                return 0
            fi

            # mkdir (with or without -p) targeting the artifacts dir.
            local token0
            token0="$(_cwg_nth_token 1 "$cmd")"
            local base0
            base0="$(basename "$token0")"
            if [[ "$base0" == "mkdir" && "$cmd" == *"${data_root}/artifacts/"* ]]; then
                return 0
            fi

            return 1
            ;;

        # Read and all other non-writing tools: not artifact creation.
        *)
            return 1
            ;;
    esac
}
