#!/usr/bin/env bash
# validate-yci-skills.sh — yci skill validator
#
# Checks:
#   1. yci/.claude-plugin/plugin.json exists and parses as valid JSON.
#   2. yci/skills/hello/SKILL.md exists with valid YAML frontmatter.
#   3. yci/skills/customer-profile — full surface validation.
#
# Intentional: no -e flag; validator must aggregate failures.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/shellcheck-resolve.sh
source "${SCRIPT_DIR}/lib/shellcheck-resolve.sh"

ERRORS=0

fail() { printf '  ✗ fail: %s\n' "$*" >&2; ERRORS=$((ERRORS + 1)); }
ok()   { printf '  ✓ ok:   %s\n' "$*"; }
warn() { printf '  ! warn: %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# Phase-0 hello skill checks (preserved verbatim from original)
# ---------------------------------------------------------------------------
validate_hello_skill() {
    echo "--- hello skill ---"

    local plugin_json="${REPO_ROOT}/yci/.claude-plugin/plugin.json"
    local skill_md="${REPO_ROOT}/yci/skills/hello/SKILL.md"

    # 1. plugin.json
    if [[ ! -f "${plugin_json}" ]]; then
        fail "yci/.claude-plugin/plugin.json missing"
    elif ! python3 -m json.tool "${plugin_json}" > /dev/null 2>&1; then
        fail "yci/.claude-plugin/plugin.json is not valid JSON"
    else
        ok "yci/.claude-plugin/plugin.json valid JSON"
    fi

    # 2. SKILL.md exists
    if [[ ! -f "${skill_md}" ]]; then
        fail "yci/skills/hello/SKILL.md missing"
        return
    fi
    ok "yci/skills/hello/SKILL.md present"

    # 3. Validate frontmatter
    if python3 - "${skill_md}" <<'PY'; then
import re
import sys
from pathlib import Path

try:
    import yaml
    def load_frontmatter(text: str) -> dict:
        m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
        return (yaml.safe_load(m.group(1)) or {}) if m else {}
except ImportError:
    def load_frontmatter(text: str) -> dict:
        m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
        if not m:
            return {}
        out: dict = {}
        for line in m.group(1).splitlines():
            km = re.match(r"^([a-zA-Z_][a-zA-Z0-9_-]*):\s*(.*)$", line)
            if not km:
                continue
            key, val = km.group(1), km.group(2).strip()
            if val.startswith(('"', "'")):
                val = val.strip("\"'")
            if val.lower() in {"true", "false"}:
                out[key] = (val.lower() == "true")
            else:
                out[key] = val
        return out

skill_md = Path(sys.argv[1])
text = skill_md.read_text(encoding="utf-8")

script_name = "validate-yci-skills.sh"
errors: list[str] = []

if not re.match(r"^---\n.*?\n---\n", text, re.DOTALL):
    errors.append(
        f"{skill_md}: frontmatter delimiters missing or malformed "
        f"(expected opening and closing '---' lines)"
    )
    for err in errors:
        print(f"{script_name}: {err}", file=sys.stderr)
    sys.exit(1)

fm = load_frontmatter(text)

name_val = fm.get("name", "")
if name_val != "hello":
    errors.append(
        f"{skill_md}: frontmatter 'name' must be 'hello', got {name_val!r}"
    )

desc_val = fm.get("description", "")
if not isinstance(desc_val, str) or not desc_val.strip():
    errors.append(
        f"{skill_md}: frontmatter 'description' must be a non-empty string"
    )

if errors:
    for err in errors:
        print(f"{script_name}: {err}", file=sys.stderr)
    sys.exit(1)
PY
        ok "yci/skills/hello/SKILL.md frontmatter valid"
    else
        fail "yci/skills/hello/SKILL.md frontmatter invalid"
    fi
}

# ---------------------------------------------------------------------------
# customer-profile skill checks
# ---------------------------------------------------------------------------
validate_customer_profile_skill() {
    echo "--- customer-profile skill ---"

    local skill_root="${REPO_ROOT}/yci/skills/customer-profile"
    local shared_scripts="${REPO_ROOT}/yci/skills/_shared/scripts"
    local commands_dir="${REPO_ROOT}/yci/commands"

    # --- SKILL.md ---
    if [ -f "${skill_root}/SKILL.md" ]; then
        ok "customer-profile/SKILL.md present"
        if python3 - "${skill_root}/SKILL.md" <<'PY'; then
import sys
import yaml
src = open(sys.argv[1]).read()
parts = src.split('---', 2)
if len(parts) < 3:
    sys.stderr.write("SKILL.md: missing YAML frontmatter\n"); sys.exit(1)
fm = yaml.safe_load(parts[1])
if not isinstance(fm, dict):
    sys.stderr.write("SKILL.md: frontmatter is not a mapping\n"); sys.exit(1)
if fm.get('name') != 'customer-profile':
    sys.stderr.write("SKILL.md: name must be 'customer-profile'\n"); sys.exit(1)
desc = fm.get('description')
if not (isinstance(desc, str) and len(desc) >= 50):
    sys.stderr.write("SKILL.md: description missing or too short (>=50 chars)\n"); sys.exit(1)
if 'argument-hint' not in fm:
    sys.stderr.write("SKILL.md: argument-hint missing\n"); sys.exit(1)
tools = fm.get('allowed-tools')
if not (isinstance(tools, list) and tools):
    sys.stderr.write("SKILL.md: allowed-tools must be a non-empty list\n"); sys.exit(1)
PY
            ok "customer-profile/SKILL.md frontmatter valid"
        else
            fail "customer-profile/SKILL.md: frontmatter invalid"
        fi
    else
        fail "customer-profile/SKILL.md missing"
    fi

    # --- references ---
    for ref in schema.md precedence.md error-messages.md _template.yaml; do
        if [ -s "${skill_root}/references/${ref}" ]; then
            ok "reference ${ref} present and non-empty"
        else
            fail "reference ${ref} missing or empty"
        fi
    done

    # error catalog count
    local id_count
    id_count="$(grep -c '^- \*\*ID\*\*:' "${skill_root}/references/error-messages.md" 2>/dev/null || echo 0)"
    if [ "$id_count" -ge 10 ]; then
        ok "error-messages.md has ${id_count} error IDs"
    else
        fail "error-messages.md too thin: ${id_count} IDs (expected >=10)"
    fi

    # _template.yaml parses
    if python3 -c "import yaml; yaml.safe_load(open('${skill_root}/references/_template.yaml'))" 2>/dev/null; then
        ok "_template.yaml parses as valid YAML"
    else
        fail "_template.yaml: YAML parse error"
    fi

    # --- skill scripts ---
    local skill_scripts=(
        resolve-customer.sh
        state-io.sh
        profile-schema.sh
        load-profile.sh
        switch-profile.sh
        render-whoami.sh
        init-profile.sh
    )
    # Script validation: executable + bash shebang + safety flags. state-io.sh
    # and profile-schema.sh are sourceable libraries that must NOT self-enable
    # `set -euo pipefail` at file scope (would corrupt callers' shell options).
    local -a safety_exempt=(state-io.sh profile-schema.sh)
    for s in "${skill_scripts[@]}"; do
        local p="${skill_root}/scripts/${s}"
        if ! [ -x "$p" ]; then
            fail "script ${s}: not executable or missing"
            continue
        fi
        if ! head -1 "$p" | grep -q '^#!/usr/bin/env bash'; then
            fail "script ${s}: wrong shebang (expected #!/usr/bin/env bash)"
            continue
        fi
        # Safety flags required only on runnable scripts; sourceable libraries
        # must not self-enable strict mode because it leaks into the caller.
        local exempt=0
        for ex in "${safety_exempt[@]}"; do [ "$s" = "$ex" ] && exempt=1; done
        if [ "$exempt" -eq 1 ]; then
            ok "script ${s} present, executable, correct shebang (sourceable library)"
        elif head -20 "$p" | grep -qE '^[[:space:]]*set[[:space:]]+-euo[[:space:]]+pipefail[[:space:]]*$'; then
            ok "script ${s} present, executable, correct shebang, has set -euo pipefail"
        else
            fail "script ${s}: missing 'set -euo pipefail' in first 20 lines"
        fi
    done

    # shared data-root resolver — runnable AND sourceable; require safety flags
    # since it's invoked as a CLI by resolve-customer.sh and init-profile.sh.
    local rdr="${shared_scripts}/resolve-data-root.sh"
    if ! [ -x "$rdr" ]; then
        fail "shared resolve-data-root.sh: missing or not executable"
    elif ! head -1 "$rdr" | grep -q '^#!/usr/bin/env bash'; then
        fail "shared resolve-data-root.sh: wrong shebang"
    elif head -20 "$rdr" | grep -qE '^[[:space:]]*set[[:space:]]+-euo[[:space:]]+pipefail[[:space:]]*$'; then
        ok "shared resolve-data-root.sh present, executable, correct shebang, has set -euo pipefail"
    else
        fail "shared resolve-data-root.sh: missing 'set -euo pipefail' in first 20 lines"
    fi

    # --- slash-command wrappers ---
    for cmd in switch whoami init; do
        local md="${commands_dir}/${cmd}.md"
        if [ -f "$md" ]; then
            if python3 - "$md" <<'PY'; then
import sys
import yaml
src = open(sys.argv[1]).read()
parts = src.split('---', 2)
if len(parts) < 3:
    sys.stderr.write("command.md: missing YAML frontmatter\n"); sys.exit(1)
fm = yaml.safe_load(parts[1])
if not isinstance(fm, dict):
    sys.stderr.write("command.md: frontmatter is not a mapping\n"); sys.exit(1)
if not fm.get('description'):
    sys.stderr.write("command.md: description missing or empty\n"); sys.exit(1)
PY
                ok "command ${cmd}.md frontmatter valid"
            else
                fail "command ${cmd}.md: frontmatter invalid"
            fi
            if grep -q 'yci:customer-profile' "$md"; then
                ok "command ${cmd}.md invokes yci:customer-profile"
            else
                fail "command ${cmd}.md does not reference yci:customer-profile"
            fi
        else
            fail "command ${cmd}.md missing"
        fi
    done

    # --- tests ---
    local tests_dir="${skill_root}/tests"

    if [ -x "${tests_dir}/run-all.sh" ]; then
        ok "run-all.sh present and executable"
    else
        fail "run-all.sh missing or not executable"
    fi

    if [ -s "${tests_dir}/helpers.sh" ]; then
        ok "helpers.sh present"
    else
        fail "helpers.sh missing"
    fi

    local test_count
    test_count="$(ls "${tests_dir}"/test_*.sh 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$test_count" -ge 5 ]; then
        ok "test files: ${test_count}"
    else
        fail "too few test files: ${test_count} (need >=5)"
    fi

    for fx in acme-example.yaml minimal.yaml; do
        local fxp="${tests_dir}/fixtures/${fx}"
        if python3 -c "import yaml; yaml.safe_load(open('${fxp}'))" 2>/dev/null; then
            ok "fixture ${fx} parses as valid YAML"
        else
            fail "fixture ${fx} missing or invalid YAML"
        fi
    done

    # --- run the test harness ---
    printf '\n--- customer-profile test harness ---\n'
    if bash "${tests_dir}/run-all.sh"; then
        ok "test harness passed"
    else
        fail "test harness: one or more tests failed"
    fi

    # --- shellcheck ---
    printf '\n--- shellcheck (customer-profile) ---\n'
    if SHELLCHECK_RESOLVE_OPTIONAL=1 resolve_shellcheck_bin; then
        local sc_files=()
        # collect skill scripts
        while IFS= read -r f; do sc_files+=("$f"); done \
            < <(ls "${skill_root}/scripts/"*.sh 2>/dev/null)
        # shared script
        sc_files+=("${shared_scripts}/resolve-data-root.sh")
        # test files
        while IFS= read -r f; do sc_files+=("$f"); done \
            < <(ls "${tests_dir}/run-all.sh" "${tests_dir}/helpers.sh" \
                    "${tests_dir}/"test_*.sh 2>/dev/null)

        if "$SHELLCHECK_BIN" --severity=warning "${sc_files[@]}"; then
            ok "shellcheck clean on ${#sc_files[@]} files"
        else
            fail "shellcheck reported warnings/errors"
        fi
    else
        warn "shellcheck not installed — skipping"
    fi
}

# ---------------------------------------------------------------------------
# customer-guard hook checks
# ---------------------------------------------------------------------------
validate_customer_guard_hook() {
    echo "--- customer-guard hook ---"

    local plugin_json="${REPO_ROOT}/yci/.claude-plugin/plugin.json"
    local hook_json="${REPO_ROOT}/yci/hooks/customer-guard/hook.json"
    local hook_scripts_dir="${REPO_ROOT}/yci/hooks/customer-guard/scripts"

    # 1. plugin.json has hooks key pointing at hook.json
    if python3 -c "
import json, sys, os
plugin_root = '${REPO_ROOT}/yci'
with open('${plugin_json}') as f: data = json.load(f)
hooks = data.get('hooks')
if not hooks:
    sys.stderr.write('plugin.json: missing or empty hooks key\n'); sys.exit(1)
if isinstance(hooks, str):
    target = os.path.join(plugin_root, hooks)
    if not os.path.isfile(target):
        sys.stderr.write(f'plugin.json: hooks key points to missing file: {target}\n'); sys.exit(1)
" 2>/dev/null; then
        ok "plugin.json hooks key present and resolves"
    else
        fail "plugin.json: missing or empty hooks key, or hooks file not found"
    fi

    # 2. hook.json exists, parses, references pretool.sh
    if [ ! -f "$hook_json" ]; then
        fail "hook.json missing"
        return
    fi
    python3 -m json.tool "$hook_json" > /dev/null 2>&1 || fail "hook.json: invalid JSON"
    if grep -q 'pretool.sh' "$hook_json"; then
        ok "hook.json present, parses, references pretool.sh"
    else
        fail "hook.json: does not reference pretool.sh"
    fi

    # 3. Scripts: pretool.sh (runnable) and decision-json.sh (sourceable, non-executable)
    local -a hook_scripts=(pretool.sh decision-json.sh)
    local -a hook_safety_exempt=(decision-json.sh)
    for s in "${hook_scripts[@]}"; do
        local p="${hook_scripts_dir}/${s}"
        local exempt=0
        for ex in "${hook_safety_exempt[@]}"; do [ "$s" = "$ex" ] && exempt=1; done
        if ! [ -f "$p" ]; then
            fail "hook script ${s}: missing"
            continue
        fi
        if ! head -1 "$p" | grep -q '^#!/usr/bin/env bash'; then
            fail "hook script ${s}: wrong shebang (expected #!/usr/bin/env bash)"
            continue
        fi
        if ! [ -x "$p" ]; then
            fail "hook script ${s}: not executable"
            continue
        fi
        if [ "$exempt" -eq 1 ]; then
            # Sourceable library: executable, but MUST NOT self-enable set -euo pipefail at file scope.
            if head -20 "$p" | grep -qE '^[[:space:]]*set[[:space:]]+-euo[[:space:]]+pipefail[[:space:]]*$'; then
                fail "hook script ${s}: sourceable library must not self-enable set -euo pipefail"
            else
                ok "hook script ${s} (sourceable library): executable, shebang, no set -euo at file scope"
            fi
        else
            # Runnable: must be executable, must have set -euo pipefail
            if ! head -20 "$p" | grep -qE '^[[:space:]]*set[[:space:]]+-euo[[:space:]]+pipefail[[:space:]]*$'; then
                fail "hook script ${s}: missing 'set -euo pipefail' in first 20 lines"
            else
                ok "hook script ${s}: executable, shebang, set -euo pipefail"
            fi
        fi
    done

    # 4a. References: error-messages.md
    local em="${REPO_ROOT}/yci/hooks/customer-guard/references/error-messages.md"
    if [ ! -s "$em" ]; then
        fail "error-messages.md missing/empty"
    else
        local n
        n="$(grep -c '^### ' "$em")"
        if [ "$n" -ge 6 ]; then
            ok "error-messages.md has $n catalog entries"
        else
            fail "error-messages.md: $n entries (need >=6)"
        fi
    fi

    # 4b. References: capability-gaps.md
    local cg="${REPO_ROOT}/yci/hooks/customer-guard/references/capability-gaps.md"
    if [ -s "$cg" ]; then
        ok "capability-gaps.md present and non-empty"
    else
        fail "capability-gaps.md missing or empty"
    fi

    # 4c. Codex advisory stub
    local codex_stub="${REPO_ROOT}/yci/hooks/customer-guard/targets/codex/codex-config-fragment.toml"
    if [ ! -f "$codex_stub" ]; then
        fail "codex advisory stub missing"
    else
        local first
        first="$(grep -v '^[[:space:]]*$' "$codex_stub" | head -1)"
        case "$first" in
            '# Advisory only'*) ok "codex stub starts with '# Advisory only'" ;;
            *)                   fail "codex stub first non-blank line does not start with '# Advisory only'" ;;
        esac
    fi

    # 5. Integration tests (task 6.1 — guard if not yet present)
    local hook_tests_dir="${REPO_ROOT}/yci/hooks/customer-guard/tests"
    if [ -x "${hook_tests_dir}/run-all.sh" ]; then
        printf '\n--- customer-guard integration tests ---\n'
        if bash "${hook_tests_dir}/run-all.sh"; then
            ok "customer-guard integration tests pass"
        else
            fail "customer-guard integration tests failed"
        fi
    else
        warn "customer-guard integration tests not yet present (task 6.1)"
    fi
}

# ---------------------------------------------------------------------------
# customer-isolation library checks
# ---------------------------------------------------------------------------
validate_customer_isolation_lib() {
    echo "--- customer-isolation library ---"

    local lib_root="${REPO_ROOT}/yci/skills/_shared/customer-isolation"
    local lib_scripts_dir="${lib_root}/scripts"
    local lib_tests_dir="${lib_root}/tests"

    # 1. Python scripts compile
    local py
    for py in "${lib_scripts_dir}"/*.py; do
        [ -f "$py" ] || continue
        if python3 -m py_compile "$py" 2>/dev/null; then
            ok "$(basename "$py") compiles"
        else
            fail "$(basename "$py"): py_compile failed"
        fi
    done

    # 2. Shell scripts: shebang check; path-match.sh and allowlist.sh are
    #    sourceable libraries (non-executable, no set -euo at file scope).
    local -a lib_sh_scripts=(path-match.sh allowlist.sh)
    local -a lib_safety_exempt=(path-match.sh allowlist.sh)
    for s in "${lib_sh_scripts[@]}"; do
        local p="${lib_scripts_dir}/${s}"
        local exempt=0
        for ex in "${lib_safety_exempt[@]}"; do [ "$s" = "$ex" ] && exempt=1; done
        if ! [ -f "$p" ]; then
            fail "lib script ${s}: missing"
            continue
        fi
        if ! head -1 "$p" | grep -q '^#!/usr/bin/env bash'; then
            fail "lib script ${s}: wrong shebang (expected #!/usr/bin/env bash)"
            continue
        fi
        if ! [ -x "$p" ]; then
            fail "lib script ${s}: not executable"
            continue
        fi
        if [ "$exempt" -eq 1 ]; then
            if head -20 "$p" | grep -qE '^[[:space:]]*set[[:space:]]+-euo[[:space:]]+pipefail[[:space:]]*$'; then
                fail "lib script ${s}: sourceable library must not self-enable set -euo pipefail"
            else
                ok "lib script ${s} (sourceable library): executable, shebang, no set -euo at file scope"
            fi
        else
            if ! head -20 "$p" | grep -qE '^[[:space:]]*set[[:space:]]+-euo[[:space:]]+pipefail[[:space:]]*$'; then
                fail "lib script ${s}: missing 'set -euo pipefail' in first 20 lines"
            else
                ok "lib script ${s}: executable, shebang, set -euo pipefail"
            fi
        fi
    done

    # 3. detect.sh sources cleanly and exports isolation_check_payload
    #    (detect.sh resolves helpers from CLAUDE_PLUGIN_ROOT or YCI_ROOT)
    local yci_plugin_root
    yci_plugin_root="$(cd "${lib_root}/../../.." && pwd -P)"
    if bash -c "export YCI_ROOT='${yci_plugin_root}'; source '${lib_root}/detect.sh' 2>/dev/null && declare -F isolation_check_payload > /dev/null"; then
        ok "detect.sh sources and exports isolation_check_payload"
    else
        fail "detect.sh: source failed OR isolation_check_payload not exported"
    fi

    # 4. fingerprint-rules.md present and non-empty
    local fp_rules="${lib_root}/references/fingerprint-rules.md"
    if [ -s "$fp_rules" ]; then
        ok "fingerprint-rules.md present and non-empty"
    else
        fail "fingerprint-rules.md missing/empty"
    fi

    # 5. Unit tests (task 4.1 — required)
    if [ -x "${lib_tests_dir}/run-all.sh" ]; then
        printf '\n--- customer-isolation unit tests ---\n'
        if bash "${lib_tests_dir}/run-all.sh"; then
            ok "customer-isolation unit tests pass"
        else
            fail "customer-isolation unit tests failed"
        fi
    else
        fail "customer-isolation tests/run-all.sh missing or not executable"
    fi

    # 6. shellcheck — covers both hook scripts and isolation-lib scripts
    printf '\n--- shellcheck (customer-guard + customer-isolation) ---\n'
    if command -v shellcheck >/dev/null 2>&1; then
        local sc_files=()
        # hook scripts
        while IFS= read -r f; do sc_files+=("$f"); done \
            < <(ls "${REPO_ROOT}/yci/hooks/customer-guard/scripts/"*.sh 2>/dev/null)
        # isolation lib shell scripts
        while IFS= read -r f; do sc_files+=("$f"); done \
            < <(ls "${lib_scripts_dir}"/*.sh 2>/dev/null)
        # detect.sh
        sc_files+=("${lib_root}/detect.sh")
        # test files
        while IFS= read -r f; do sc_files+=("$f"); done \
            < <(ls "${lib_tests_dir}/run-all.sh" "${lib_tests_dir}/helpers.sh" \
                    "${lib_tests_dir}/"test_*.sh 2>/dev/null)

        if shellcheck --severity=warning "${sc_files[@]}"; then
            ok "shellcheck clean on ${#sc_files[@]} files"
        else
            fail "shellcheck reported warnings/errors"
        fi
    else
        warn "shellcheck not installed — skipping"
    fi
}

# ---------------------------------------------------------------------------
main() {
    echo "=== validate-yci-skills.sh ==="
    validate_hello_skill
    echo
    validate_customer_profile_skill
    echo
    validate_customer_guard_hook
    echo
    validate_customer_isolation_lib
    echo

    if [ "$ERRORS" -eq 0 ]; then
        echo "ALL CHECKS PASSED"
        exit 0
    else
        printf 'FAILED: %d check(s)\n' "$ERRORS" >&2
        exit 1
    fi
}

main "$@"
