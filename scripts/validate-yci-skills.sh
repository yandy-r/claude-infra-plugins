#!/usr/bin/env bash
# validate-yci-skills.sh — yci skill validator
#
# Checks:
#   1. yci/.claude-plugin/plugin.json exists and parses as valid JSON.
#   2. yci/skills/hello/SKILL.md exists with valid YAML frontmatter.
#   3. yci/skills/customer-profile — full surface validation.
#   4. yci/skills/_shared/telemetry-sanitizer — sanitizer + tests.
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
validate_telemetry_sanitizer_lib() {
    echo "--- telemetry-sanitizer library ---"

    local lib_root="${REPO_ROOT}/yci/skills/_shared/telemetry-sanitizer"
    local lib_scripts="${lib_root}/scripts"
    local lib_tests="${lib_root}/tests"
    local hipaa_rules="${REPO_ROOT}/yci/skills/_shared/compliance-adapters/hipaa/phi-redaction.rules"

    for py in "${lib_scripts}/patterns.py" "${lib_scripts}/sanitize_text.py" "${lib_scripts}/load_adapter_rules.py"; do
        if [ -f "$py" ]; then
            if python3 -m py_compile "$py" 2>/dev/null; then
                ok "$(basename "$py") compiles"
            else
                fail "$(basename "$py"): py_compile failed"
            fi
        else
            fail "missing $py"
        fi
    done

    for s in sanitize-output.sh pre-write-artifact.sh; do
        local p="${lib_scripts}/${s}"
        if ! [ -x "$p" ]; then
            fail "telemetry script ${s}: not executable or missing"
            continue
        fi
        if ! head -1 "$p" | grep -q '^#!/usr/bin/env bash'; then
            fail "telemetry script ${s}: wrong shebang"
            continue
        fi
        if head -20 "$p" | grep -qE '^[[:space:]]*set[[:space:]]+-euo[[:space:]]+pipefail[[:space:]]*$'; then
            ok "telemetry script ${s}: executable, shebang, set -euo pipefail"
        else
            fail "telemetry script ${s}: missing set -euo pipefail in first 20 lines"
        fi
    done

    if [ -s "$hipaa_rules" ]; then
        ok "hipaa/phi-redaction.rules present"
    else
        fail "hipaa/phi-redaction.rules missing or empty"
    fi

    if [ -x "${lib_tests}/run-all.sh" ]; then
        printf '\n--- telemetry-sanitizer unit tests ---\n'
        if bash "${lib_tests}/run-all.sh"; then
            ok "telemetry-sanitizer unit tests pass"
        else
            fail "telemetry-sanitizer unit tests failed"
        fi
    else
        fail "telemetry-sanitizer tests/run-all.sh missing or not executable"
    fi

    printf '\n--- shellcheck (telemetry-sanitizer) ---\n'
    if SHELLCHECK_RESOLVE_OPTIONAL=1 resolve_shellcheck_bin; then
        local sc_files=()
        while IFS= read -r f; do sc_files+=("$f"); done \
            < <(ls "${lib_scripts}/sanitize-output.sh" "${lib_scripts}/pre-write-artifact.sh" 2>/dev/null)
        while IFS= read -r f; do sc_files+=("$f"); done \
            < <(ls "${lib_tests}/run-all.sh" "${lib_tests}/helpers.sh" "${lib_tests}/"test_*.sh 2>/dev/null)
        if "$SHELLCHECK_BIN" --severity=warning "${sc_files[@]}"; then
            ok "shellcheck clean on telemetry-sanitizer (${#sc_files[@]} files)"
        else
            fail "shellcheck reported warnings/errors (telemetry-sanitizer)"
        fi
    else
        warn "shellcheck not installed — skipping"
    fi
}

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
# blast-radius skill checks
# ---------------------------------------------------------------------------
validate_blast_radius_skill() {
    echo "--- blast-radius skill ---"

    local skill_root="${REPO_ROOT}/yci/skills/blast-radius"

    # 1. Skill root exists
    if [ ! -d "${skill_root}" ]; then
        fail "yci/skills/blast-radius/ directory missing"
        return
    fi
    ok "yci/skills/blast-radius/ present"

    # 2. SKILL.md exists with valid frontmatter
    if [ ! -f "${skill_root}/SKILL.md" ]; then
        fail "blast-radius/SKILL.md missing"
    else
        ok "blast-radius/SKILL.md present"
        if python3 - "${skill_root}/SKILL.md" <<'PY'; then
import sys
import re

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

from pathlib import Path
skill_md = Path(sys.argv[1])
text = skill_md.read_text(encoding="utf-8")
script_name = "validate-yci-skills.sh"
errors: list[str] = []

if not re.match(r"^---\n.*?\n---\n", text, re.DOTALL):
    errors.append(f"{skill_md}: frontmatter delimiters missing or malformed")
    for err in errors:
        print(f"{script_name}: {err}", file=sys.stderr)
    sys.exit(1)

fm = load_frontmatter(text)

if fm.get("name") != "blast-radius":
    errors.append(f"{skill_md}: frontmatter 'name' must be 'blast-radius', got {fm.get('name')!r}")

desc = fm.get("description", "")
if not (isinstance(desc, str) and desc.strip()):
    errors.append(f"{skill_md}: frontmatter 'description' must be a non-empty string")

tools = fm.get("allowed-tools")
if not (isinstance(tools, list) and tools):
    errors.append(f"{skill_md}: frontmatter 'allowed-tools' must be a non-empty list")

if errors:
    for err in errors:
        print(f"{script_name}: {err}", file=sys.stderr)
    sys.exit(1)
PY
            ok "blast-radius/SKILL.md frontmatter valid"
        else
            fail "blast-radius/SKILL.md: frontmatter invalid"
        fi
    fi

    # 3. Required scripts exist and are executable
    for s in adapter-file.sh reason.sh render-markdown.sh; do
        local p="${skill_root}/scripts/${s}"
        if [ -x "$p" ]; then
            ok "script ${s} present and executable"
        else
            fail "script ${s}: missing or not executable"
        fi
    done

    # 4. Required reference files exist and are non-empty
    for ref in label-schema.md label-schema.json change-input-schema.md file-adapter-layout.md error-messages.md; do
        if [ -s "${skill_root}/references/${ref}" ]; then
            ok "reference ${ref} present and non-empty"
        else
            fail "reference ${ref} missing or empty"
        fi
    done

    # 5. label-schema.json parses as valid JSON with JSON Schema $schema declaration
    local schema_json="${skill_root}/references/label-schema.json"
    if python3 -c "
import json, sys
with open('${schema_json}') as f:
    doc = json.load(f)
schema_val = doc.get('\$schema', '')
if not schema_val.startswith('https://json-schema.org/draft/2020-12/'):
    sys.stderr.write('label-schema.json: \$schema must start with https://json-schema.org/draft/2020-12/\n')
    sys.exit(1)
" 2>/dev/null; then
        ok "label-schema.json valid JSON with correct \$schema declaration"
    else
        fail "label-schema.json: invalid JSON or \$schema not set to https://json-schema.org/draft/2020-12/"
    fi

    # 6. Tests directory exists with required executable test files
    local tests_dir="${skill_root}/tests"
    if [ -x "${tests_dir}/run-all.sh" ]; then
        ok "tests/run-all.sh present and executable"
    else
        fail "tests/run-all.sh missing or not executable"
    fi

    for t in test_adapter_file.sh test_reason.sh test_render_markdown.sh test_cross_customer_isolation.sh; do
        if [ -x "${tests_dir}/${t}" ]; then
            ok "test file ${t} present and executable"
        else
            fail "test file ${t}: missing or not executable"
        fi
    done

    # 7. shellcheck clean on scripts/*.sh and tests/*.sh
    printf '\n--- shellcheck (blast-radius) ---\n'
    if SHELLCHECK_RESOLVE_OPTIONAL=1 resolve_shellcheck_bin; then
        local sc_files=()
        while IFS= read -r f; do sc_files+=("$f"); done \
            < <(ls "${skill_root}/scripts/"*.sh 2>/dev/null)
        while IFS= read -r f; do sc_files+=("$f"); done \
            < <(ls "${tests_dir}/"*.sh 2>/dev/null)

        if [ "${#sc_files[@]}" -eq 0 ]; then
            warn "shellcheck: no .sh files found yet (skill scripts not yet created)"
        elif "$SHELLCHECK_BIN" --severity=warning "${sc_files[@]}"; then
            ok "shellcheck clean on ${#sc_files[@]} files"
        else
            fail "shellcheck reported warnings/errors"
        fi
    else
        warn "shellcheck not installed — skipping"
    fi

    # 8. allowed-tools must contain the Bash allow-list entry verbatim
    # shellcheck disable=SC2016  # single quotes intentional: literal string for grep -F
    local allow_entry='Bash(${CLAUDE_PLUGIN_ROOT}/skills/blast-radius/scripts/*.sh:*)'
    if grep -qF "${allow_entry}" "${skill_root}/SKILL.md" 2>/dev/null; then
        ok "SKILL.md allowed-tools contains required Bash allow-list entry"
    else
        fail "SKILL.md allowed-tools missing: ${allow_entry}"
    fi
}

# ---------------------------------------------------------------------------
# compliance-adapters checks
# ---------------------------------------------------------------------------
validate_compliance_adapters() {
    echo "--- compliance adapters ---"

    local schema_lib="${REPO_ROOT}/yci/skills/_shared/scripts/adapter-schema.sh"
    local loader="${REPO_ROOT}/yci/skills/_shared/scripts/load-compliance-adapter.sh"
    local adapters_root="${REPO_ROOT}/yci/skills/_shared/compliance-adapters"

    # ---- Check A: Sourceable library shape of adapter-schema.sh ---------------

    # A1. File exists and is readable
    if [ ! -f "$schema_lib" ]; then
        fail "adapter-schema.sh: file not found"
    elif [ ! -r "$schema_lib" ]; then
        fail "adapter-schema.sh: not readable"
    else
        ok "adapter-schema.sh present and readable"

        # A2. First non-comment, non-blank line after shebang must NOT begin with set -
        local first_non_comment
        first_non_comment="$(grep -v '^[[:space:]]*#' "$schema_lib" | grep -v '^[[:space:]]*$' | tail -n +2 | head -1)"
        case "$first_non_comment" in
            set\ -*)
                fail "adapter-schema.sh: first non-comment line begins with 'set -' (sourceable library must not self-enable strict mode at file scope)" ;;
            *)
                ok "adapter-schema.sh: no 'set -' at file scope" ;;
        esac

        # A3. Sources cleanly and exports YCI_ADAPTER_REQUIRED_FILES
        local source_out
        if source_out="$(bash -c ". '${schema_lib}'; echo \"\${YCI_ADAPTER_REQUIRED_FILES[*]}\"" 2>&1)"; then
            if [ -n "$source_out" ]; then
                ok "adapter-schema.sh sources cleanly; YCI_ADAPTER_REQUIRED_FILES non-empty"
            else
                fail "adapter-schema.sh: sourced without error but YCI_ADAPTER_REQUIRED_FILES is empty"
            fi
        else
            fail "adapter-schema.sh: source failed: ${source_out}"
        fi

        # A4. YCI_ADAPTER_REQUIRED_FILES has at least 1 entry (ADAPTER.md)
        local req_count
        req_count="$(bash -c ". '${schema_lib}'; echo \"\${#YCI_ADAPTER_REQUIRED_FILES[@]}\"" 2>/dev/null)"
        if [ "${req_count:-0}" -ge 1 ]; then
            ok "adapter-schema.sh: YCI_ADAPTER_REQUIRED_FILES has ${req_count} entries (>=1)"
        else
            fail "adapter-schema.sh: YCI_ADAPTER_REQUIRED_FILES has ${req_count:-0} entries (need >=1)"
        fi

        # A4b. YCI_ADAPTER_PHASE1_REGIMES has at least 1 entry
        local phase1_count
        phase1_count="$(bash -c ". '${schema_lib}'; echo \"\${#YCI_ADAPTER_PHASE1_REGIMES[@]}\"" 2>/dev/null)"
        if [ "${phase1_count:-0}" -ge 1 ]; then
            ok "adapter-schema.sh: YCI_ADAPTER_PHASE1_REGIMES has ${phase1_count} entries (>=1)"
        else
            fail "adapter-schema.sh: YCI_ADAPTER_PHASE1_REGIMES has ${phase1_count:-0} entries (need >=1)"
        fi

        # A5. YCI_ADAPTER_SCHEMA_EXEMPT has at least 1 entry
        local exempt_count
        exempt_count="$(bash -c ". '${schema_lib}'; echo \"\${#YCI_ADAPTER_SCHEMA_EXEMPT[@]}\"" 2>/dev/null)"
        if [ "${exempt_count:-0}" -ge 1 ]; then
            ok "adapter-schema.sh: YCI_ADAPTER_SCHEMA_EXEMPT has ${exempt_count} entries (>=1)"
        else
            fail "adapter-schema.sh: YCI_ADAPTER_SCHEMA_EXEMPT has ${exempt_count:-0} entries (need >=1)"
        fi

        # A6. yci_adapter_is_schema_exempt none returns 0
        if bash -c ". '${schema_lib}'; yci_adapter_is_schema_exempt none" 2>/dev/null; then
            ok "adapter-schema.sh: yci_adapter_is_schema_exempt none returns 0"
        else
            fail "adapter-schema.sh: yci_adapter_is_schema_exempt none did not return 0"
        fi

        # A7. yci_adapter_is_schema_exempt commercial returns non-zero
        if bash -c ". '${schema_lib}'; yci_adapter_is_schema_exempt commercial" 2>/dev/null; then
            fail "adapter-schema.sh: yci_adapter_is_schema_exempt commercial returned 0 (expected non-zero)"
        else
            ok "adapter-schema.sh: yci_adapter_is_schema_exempt commercial returns non-zero"
        fi
    fi

    # ---- Check B: Loader script safety -----------------------------------------

    if [ ! -f "$loader" ]; then
        fail "load-compliance-adapter.sh: file not found"
    else
        ok "load-compliance-adapter.sh present"

        # B1. Executable
        if [ ! -x "$loader" ]; then
            fail "load-compliance-adapter.sh: not executable"
        else
            ok "load-compliance-adapter.sh: executable"
        fi

        # B2. Shebang on line 1
        if head -1 "$loader" | grep -q '^#!/usr/bin/env bash'; then
            ok "load-compliance-adapter.sh: correct shebang"
        else
            fail "load-compliance-adapter.sh: wrong shebang (expected #!/usr/bin/env bash)"
        fi

        # B3. set -euo pipefail in first 20 lines
        if head -20 "$loader" | grep -qE '^[[:space:]]*set[[:space:]]+-euo[[:space:]]+pipefail[[:space:]]*$'; then
            ok "load-compliance-adapter.sh: has set -euo pipefail in first 20 lines"
        else
            fail "load-compliance-adapter.sh: missing 'set -euo pipefail' in first 20 lines"
        fi

        # B4. Syntactically valid
        if bash -n "$loader" 2>/dev/null; then
            ok "load-compliance-adapter.sh: bash -n passes"
        else
            fail "load-compliance-adapter.sh: bash -n reported syntax errors"
        fi
    fi

    # ---- Check C: Adapter directory structure ----------------------------------
    #
    # Discovery-based: every directory under compliance-adapters/ is validated.
    # This accommodates both Phase-1 baseline adapters (commercial, none) and
    # pre-Phase-1 minimal adapters (hipaa) without hardcoding the regime list.

    local adapter_dir regime is_exempt is_phase1
    for adapter_dir in "${adapters_root}"/*/; do
        [ -d "$adapter_dir" ] || continue
        regime="$(basename "$adapter_dir")"

        ok "compliance-adapters/${regime}/: directory present"

        # C1. ADAPTER.md is the single hard requirement (all adapters ship it).
        if [ -s "${adapter_dir}/ADAPTER.md" ]; then
            ok "compliance-adapters/${regime}/ADAPTER.md: present and non-empty"
        else
            fail "compliance-adapters/${regime}/ADAPTER.md: missing or empty"
        fi

        # C2. Classify the regime.
        if bash -c ". '${schema_lib}'; yci_adapter_is_schema_exempt '${regime}'" 2>/dev/null; then
            is_exempt=1
        else
            is_exempt=0
        fi
        if bash -c ". '${schema_lib}'; yci_adapter_is_phase1 '${regime}'" 2>/dev/null; then
            is_phase1=1
        else
            is_phase1=0
        fi

        # C3. Phase-1 adapters additionally ship evidence-template.md + handoff-checklist.md.
        if [ "$is_phase1" -eq 1 ]; then
            local pf
            for pf in evidence-template.md handoff-checklist.md; do
                if [ -s "${adapter_dir}/${pf}" ]; then
                    ok "compliance-adapters/${regime}/${pf}: present and non-empty (Phase-1 shape)"
                else
                    fail "compliance-adapters/${regime}/${pf}: missing or empty (Phase-1 regime '${regime}' requires this)"
                fi
            done
        fi

        # C4. evidence-schema.json:
        #     - Exempt regimes: MUST NOT ship evidence-schema.json (absence is load-bearing).
        #     - Non-exempt Phase-1 regimes: MUST ship it; must parse as valid JSON.
        #     - Non-exempt non-Phase-1 regimes (e.g. hipaa today): if present, must parse as valid JSON.
        if [ "$is_exempt" -eq 1 ]; then
            if [ ! -f "${adapter_dir}/evidence-schema.json" ]; then
                ok "compliance-adapters/${regime}/: evidence-schema.json correctly absent (exempt regime)"
            else
                fail "compliance-adapters/${regime}/evidence-schema.json: must NOT exist for exempt regime '${regime}'"
            fi
        elif [ "$is_phase1" -eq 1 ]; then
            if [ ! -f "${adapter_dir}/evidence-schema.json" ]; then
                fail "compliance-adapters/${regime}/evidence-schema.json: missing (Phase-1 non-exempt regime '${regime}' requires it)"
            elif python3 -m json.tool "${adapter_dir}/evidence-schema.json" > /dev/null 2>&1; then
                ok "compliance-adapters/${regime}/evidence-schema.json: valid JSON"
            else
                fail "compliance-adapters/${regime}/evidence-schema.json: invalid JSON"
            fi
        else
            if [ -f "${adapter_dir}/evidence-schema.json" ]; then
                if python3 -m json.tool "${adapter_dir}/evidence-schema.json" > /dev/null 2>&1; then
                    ok "compliance-adapters/${regime}/evidence-schema.json: valid JSON (optional for pre-Phase-1)"
                else
                    fail "compliance-adapters/${regime}/evidence-schema.json: invalid JSON"
                fi
            fi
        fi

        # C5. *-redaction.rules files: parse via load_adapter_rules.py to
        #     confirm the NAME:/RE: format is well-formed and every regex compiles.
        #     Non-exempt regimes MUST ship at least one such file.
        local rule_files rule_count=0
        rule_files="$(find "$adapter_dir" -maxdepth 1 -type f -name '*-redaction.rules' 2>/dev/null)"
        if [ -n "$rule_files" ]; then
            local rf
            while IFS= read -r rf; do
                [ -z "$rf" ] && continue
                rule_count=$((rule_count + 1))
                local rf_name
                rf_name="$(basename "$rf")"
                if REPO_ROOT="$REPO_ROOT" RULE_FILE="$rf" python3 - <<'PY' 2>/dev/null; then
import os
import sys
from pathlib import Path
sys.path.insert(0, os.path.join(os.environ["REPO_ROOT"], "yci/skills/_shared/telemetry-sanitizer/scripts"))
from load_adapter_rules import parse_rules_file
rules = parse_rules_file(Path(os.environ["RULE_FILE"]), default_name="unnamed")
if not rules:
    sys.exit(2)
PY
                    ok "compliance-adapters/${regime}/${rf_name}: parses cleanly via load_adapter_rules"
                else
                    fail "compliance-adapters/${regime}/${rf_name}: failed to parse (invalid NAME:/RE: format or empty)"
                fi
            done <<< "$rule_files"
        fi

        if [ "$is_exempt" -eq 0 ] && [ "$rule_count" -eq 0 ]; then
            fail "compliance-adapters/${regime}/: non-exempt regime ships no *-redaction.rules file (expected at least one)"
        elif [ "$is_exempt" -eq 1 ] && [ "$rule_count" -gt 0 ]; then
            fail "compliance-adapters/${regime}/: schema-exempt regime ships ${rule_count} redaction-rules file(s); exempt regimes should have none"
        elif [ "$rule_count" -eq 0 ]; then
            ok "compliance-adapters/${regime}/: no redaction rules (correct for exempt regime)"
        fi
    done

    # ---- Check D: End-to-end smoke: _internal resolves to none adapter ---------

    local tmpdir
    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmpdir}'" EXIT

    local smoke_ok=1

    # D1. Copy _internal.yaml.example into a temporary profiles dir
    local example_profile="${REPO_ROOT}/yci/docs/profiles/_internal.yaml.example"
    if [ ! -f "$example_profile" ]; then
        fail "smoke test: _internal.yaml.example not found at ${example_profile}"
        smoke_ok=0
    else
        mkdir -p "${tmpdir}/profiles"
        cp "$example_profile" "${tmpdir}/profiles/_internal.yaml"

        # D2. Load profile
        local profile_json
        local load_profile="${REPO_ROOT}/yci/skills/customer-profile/scripts/load-profile.sh"
        if profile_json="$(bash "$load_profile" "$tmpdir" _internal 2>/dev/null)"; then
            ok "smoke test: load-profile.sh resolved _internal profile"
        else
            fail "smoke test: load-profile.sh failed for _internal"
            smoke_ok=0
        fi

        if [ "$smoke_ok" -eq 1 ]; then
            # D3. Pipe profile JSON into load-compliance-adapter.sh and capture path
            local adapter_path
            if adapter_path="$(printf '%s\n' "$profile_json" | bash "$loader" 2>/dev/null)"; then
                ok "smoke test: load-compliance-adapter.sh resolved adapter path: ${adapter_path}"
            else
                fail "smoke test: load-compliance-adapter.sh failed (non-zero exit)"
                smoke_ok=0
            fi

            if [ "$smoke_ok" -eq 1 ]; then
                # D4. Assert path ends with /compliance-adapters/none
                case "$adapter_path" in
                    */compliance-adapters/none)
                        ok "smoke test: resolved path ends with /compliance-adapters/none" ;;
                    *)
                        fail "smoke test: resolved path '${adapter_path}' does not end with /compliance-adapters/none" ;;
                esac

                # D5. Assert it is a real directory
                if [ -d "$adapter_path" ]; then
                    ok "smoke test: resolved adapter path is a real directory"
                else
                    fail "smoke test: resolved adapter path '${adapter_path}' is not a directory"
                fi
            fi
        fi
    fi

    # Cleanup trap fires on EXIT; also cancel it now that we are done with tmpdir
    rm -rf "$tmpdir"
    trap - EXIT
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
    validate_blast_radius_skill
    echo
    validate_telemetry_sanitizer_lib
    echo
    validate_compliance_adapters
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
