#!/usr/bin/env bash
# yci — change-window-gate destructive-classifier library.
#
# Sourceable library (no `set -euo pipefail` at file scope).
#
# Implements D6 of the change-window-gate plan: single source of truth for
# "is this Claude tool call destructive?".  Read-only tools (Read, Grep, Glob,
# WebFetch, WebSearch) and read-only Bash invocations fail-open regardless of
# the profile's change-window posture.
#
# Exports:
#   cwg_is_destructive <tool_name> <tool_input_json>
#     Returns 0 (destructive) or 1 (non-destructive).
#     Unknown tool names → 0 (destructive, conservative default).
#
#   cwg_classify_bash_command <raw_command_string>
#     Returns 0 (destructive) or 1 (non-destructive).
#     Used internally by cwg_is_destructive and directly by tests.
#
# LIMITATIONS:
#   - The classifier operates on the TOP-LEVEL command only.  Sub-shell /
#     eval / subprocess chains (e.g. `sh -c "rm -rf /"`) are NOT recursively
#     classified.  Deeper static analysis belongs in a different tool.
#   - Tokenisation uses Python's shlex, which handles POSIX quoting but does
#     not expand variables or aliases.  Commands that obscure their verb via
#     variable indirection (CMD=rm; $CMD -rf /) will NOT be caught.

# ---------------------------------------------------------------------------
# Classification tables — edit here to extend coverage.
# ---------------------------------------------------------------------------

# First tokens that are always destructive regardless of sub-arguments.
CWG_DESTRUCTIVE_BASH_VERBS=(rm mv dd mkfs shutdown reboot)

# First tokens that are always read-only — short-circuit before sub-invocation
# matching to suppress false positives.
CWG_READONLY_VERBS=(
    ls cat grep rg find head tail wc which whereis file stat
    realpath readlink du df free uptime ps top htop
    echo printf pwd date hostname id whoami
)

# Multi-token destructive patterns (longest-match wins; list longer patterns
# first within a given verb group so the 3-token loop sees them first).
CWG_DESTRUCTIVE_SUBINVOCATIONS=(
    # git
    "git push --force"
    "git push -f"
    "git reset --hard"
    "git clean -f"
    "git clean -fd"
    "git checkout ."
    "git restore ."
    # kubectl
    "kubectl apply"
    "kubectl delete"
    "kubectl replace"
    "kubectl patch"
    "kubectl rollout restart"
    "kubectl drain"
    "kubectl cordon"
    "kubectl scale"
    "kubectl exec"
    # terraform
    "terraform apply"
    "terraform destroy"
    "terraform import"
    "terraform state rm"
    "terraform state mv"
    # helm
    "helm upgrade"
    "helm install"
    "helm rollback"
    "helm uninstall"
    # systemctl
    "systemctl start"
    "systemctl restart"
    "systemctl stop"
    "systemctl reload"
    "systemctl disable"
    "systemctl enable"
    "systemctl mask"
    # docker
    "docker compose up"
    "docker compose down"
    "docker run"
    "docker rm"
    "docker kill"
    "docker exec"
    # ansible
    "ansible-playbook"
    # cp -f (forced overwrite)
    "cp -f"
)

# Multi-token read-only patterns — checked after destructive table to ensure
# specific read-only sub-commands (e.g. "kubectl get") suppress false positives
# from a broad verb like kubectl.
CWG_READONLY_SUBINVOCATIONS=(
    # git
    "git status"
    "git log"
    "git diff"
    "git fetch"
    "git show"
    "git blame"
    "git remote -v"
    "git branch --list"
    "git worktree list"
    # kubectl
    "kubectl get"
    "kubectl describe"
    "kubectl logs"
    "kubectl top"
    # terraform
    "terraform plan"
    "terraform show"
    "terraform validate"
    "terraform output"
    # helm
    "helm list"
    "helm get"
    "helm history"
    "helm status"
    # systemctl
    "systemctl status"
    "systemctl list-units"
    "systemctl is-active"
    "systemctl is-enabled"
    # docker
    "docker ps"
    "docker images"
    "docker inspect"
    "docker logs"
    "docker stats"
)

# ---------------------------------------------------------------------------
# cwg_classify_bash_command <raw_command_string>
# ---------------------------------------------------------------------------
cwg_classify_bash_command() {
    local cmd="$1"

    # Tokenise once via Python shlex.  Null-separated output preserves tokens
    # that contain spaces.  The trailing printf '\0' ensures the last token is
    # read even when python omits a trailing newline.
    # Note: `read -a` with IFS=$'\0' does not correctly split on nulls in bash;
    # a while-read loop is required for null-delimited input.
    local tokens=()
    while IFS= read -r -d '' tok; do
        tokens+=("$tok")
    done < <(python3 -c \
        'import shlex,sys; print("\0".join(shlex.split(sys.stdin.read())), end="")' \
        <<< "$cmd"; printf '\0')

    # Empty command — non-destructive.
    if [[ ${#tokens[@]} -eq 0 ]]; then
        return 1
    fi

    local t0="${tokens[0]:-}"
    local t1="${tokens[1]:-}"
    local t2="${tokens[2]:-}"

    # --- 1. First-token: readonly verbs ----------------------------------------
    local rv
    for rv in "${CWG_READONLY_VERBS[@]}"; do
        if [[ "$t0" == "$rv" ]]; then
            return 1
        fi
    done

    # --- 2. First-token: destructive verbs -------------------------------------
    local dv
    for dv in "${CWG_DESTRUCTIVE_BASH_VERBS[@]}"; do
        if [[ "$t0" == "$dv" ]]; then
            return 0
        fi
    done

    # Build prefix strings for multi-token matching.
    local first_two="$t0 $t1"
    local first_three="$t0 $t1 $t2"

    # --- 3. Read-only sub-invocations (check BEFORE destructive to let
    #        e.g. "git status" short-circuit before "git push" patterns) --------
    local ro
    for ro in "${CWG_READONLY_SUBINVOCATIONS[@]}"; do
        # 3-token pattern?
        local ro_words
        read -r -a ro_words <<< "$ro"
        if [[ ${#ro_words[@]} -ge 3 ]]; then
            if [[ "$first_three" == "$ro" ]]; then
                return 1
            fi
        elif [[ ${#ro_words[@]} -ge 2 ]]; then
            if [[ "$first_two" == "$ro" ]]; then
                return 1
            fi
        else
            if [[ "$t0" == "$ro" ]]; then
                return 1
            fi
        fi
    done

    # --- 4. Destructive sub-invocations ----------------------------------------
    local ds
    for ds in "${CWG_DESTRUCTIVE_SUBINVOCATIONS[@]}"; do
        local ds_words
        read -r -a ds_words <<< "$ds"
        if [[ ${#ds_words[@]} -ge 3 ]]; then
            if [[ "$first_three" == "$ds" ]]; then
                return 0
            fi
        elif [[ ${#ds_words[@]} -ge 2 ]]; then
            if [[ "$first_two" == "$ds" ]]; then
                return 0
            fi
        else
            if [[ "$t0" == "$ds" ]]; then
                return 0
            fi
        fi
    done

    # --- 5. Default: non-destructive -------------------------------------------
    # Bash covers an enormous command surface.  Opt-in destructive list is safer
    # than opt-out.  Unknown exotic commands ride through; exotic Write/Edit
    # calls are handled by the tool-name layer above.
    return 1
}

# ---------------------------------------------------------------------------
# cwg_is_destructive <tool_name> <tool_input_json>
# ---------------------------------------------------------------------------
cwg_is_destructive() {
    local tool_name="$1"
    local tool_input_json="$2"

    # Tool-name dispatch — no payload inspection needed for these.
    case "$tool_name" in
        Write|Edit|NotebookEdit)
            return 0
            ;;
        Read|Grep|Glob|WebFetch|WebSearch)
            return 1
            ;;
        Bash)
            # Extract "command" field from the JSON payload.
            local cmd
            cmd="$(python3 -c \
                'import json,sys; d=json.loads(sys.argv[1]); print(d.get("command",""))' \
                "$tool_input_json" 2>/dev/null)" || cmd=""
            cwg_classify_bash_command "$cmd"
            return $?
            ;;
        *)
            # Unknown tool — conservative: treat as destructive.
            return 0
            ;;
    esac
}
