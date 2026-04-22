#!/usr/bin/env bash
# Unit tests for cwg_is_destructive and cwg_classify_bash_command.
# shellcheck disable=SC1091
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# Source the classifier library directly (no side effects)
# shellcheck source=../scripts/destructive-classifier.sh
source "${YCI_CWG_SCRIPTS_DIR}/destructive-classifier.sh"

# ---------------------------------------------------------------------------
# cwg_classify_bash_command tests
# ---------------------------------------------------------------------------

# Read-only verbs — must return non-destructive (1)
if cwg_classify_bash_command "ls -la /tmp"; then
    _yci_test_report FAIL "classify: ls is read-only" "expected non-destructive"
else
    _yci_test_report PASS "classify: ls is read-only"
fi

if cwg_classify_bash_command "cat /etc/hosts"; then
    _yci_test_report FAIL "classify: cat is read-only" "expected non-destructive"
else
    _yci_test_report PASS "classify: cat is read-only"
fi

if cwg_classify_bash_command "grep foo /tmp/file"; then
    _yci_test_report FAIL "classify: grep is read-only" "expected non-destructive"
else
    _yci_test_report PASS "classify: grep is read-only"
fi

if cwg_classify_bash_command "echo hello"; then
    _yci_test_report FAIL "classify: echo is read-only" "expected non-destructive"
else
    _yci_test_report PASS "classify: echo is read-only"
fi

if cwg_classify_bash_command "find /tmp -name '*.log'"; then
    _yci_test_report FAIL "classify: find is read-only" "expected non-destructive"
else
    _yci_test_report PASS "classify: find is read-only"
fi

# Destructive verbs — must return destructive (0)
if cwg_classify_bash_command "rm -rf /tmp/x"; then
    _yci_test_report PASS "classify: rm is destructive"
else
    _yci_test_report FAIL "classify: rm is destructive" "expected destructive"
fi

if cwg_classify_bash_command "mv /tmp/a /tmp/b"; then
    _yci_test_report PASS "classify: mv is destructive"
else
    _yci_test_report FAIL "classify: mv is destructive" "expected destructive"
fi

if cwg_classify_bash_command "dd if=/dev/zero of=/tmp/x"; then
    _yci_test_report PASS "classify: dd is destructive"
else
    _yci_test_report FAIL "classify: dd is destructive" "expected destructive"
fi

# Multi-token destructive patterns
if cwg_classify_bash_command "git push --force origin main"; then
    _yci_test_report PASS "classify: git push --force is destructive"
else
    _yci_test_report FAIL "classify: git push --force is destructive" "expected destructive"
fi

if cwg_classify_bash_command "git reset --hard HEAD~1"; then
    _yci_test_report PASS "classify: git reset --hard is destructive"
else
    _yci_test_report FAIL "classify: git reset --hard is destructive" "expected destructive"
fi

if cwg_classify_bash_command "kubectl delete pod mypod"; then
    _yci_test_report PASS "classify: kubectl delete is destructive"
else
    _yci_test_report FAIL "classify: kubectl delete is destructive" "expected destructive"
fi

if cwg_classify_bash_command "terraform destroy -auto-approve"; then
    _yci_test_report PASS "classify: terraform destroy is destructive"
else
    _yci_test_report FAIL "classify: terraform destroy is destructive" "expected destructive"
fi

if cwg_classify_bash_command "helm uninstall myrelease"; then
    _yci_test_report PASS "classify: helm uninstall is destructive"
else
    _yci_test_report FAIL "classify: helm uninstall is destructive" "expected destructive"
fi

if cwg_classify_bash_command "systemctl restart nginx"; then
    _yci_test_report PASS "classify: systemctl restart is destructive"
else
    _yci_test_report FAIL "classify: systemctl restart is destructive" "expected destructive"
fi

if cwg_classify_bash_command "ansible-playbook site.yml"; then
    _yci_test_report PASS "classify: ansible-playbook is destructive"
else
    _yci_test_report FAIL "classify: ansible-playbook is destructive" "expected destructive"
fi

# Multi-token read-only patterns — must NOT be classified as destructive
if cwg_classify_bash_command "git status"; then
    _yci_test_report FAIL "classify: git status is read-only" "expected non-destructive"
else
    _yci_test_report PASS "classify: git status is read-only"
fi

if cwg_classify_bash_command "kubectl get pods"; then
    _yci_test_report FAIL "classify: kubectl get is read-only" "expected non-destructive"
else
    _yci_test_report PASS "classify: kubectl get is read-only"
fi

if cwg_classify_bash_command "terraform plan"; then
    _yci_test_report FAIL "classify: terraform plan is read-only" "expected non-destructive"
else
    _yci_test_report PASS "classify: terraform plan is read-only"
fi

if cwg_classify_bash_command "helm list"; then
    _yci_test_report FAIL "classify: helm list is read-only" "expected non-destructive"
else
    _yci_test_report PASS "classify: helm list is read-only"
fi

if cwg_classify_bash_command "systemctl status nginx"; then
    _yci_test_report FAIL "classify: systemctl status is read-only" "expected non-destructive"
else
    _yci_test_report PASS "classify: systemctl status is read-only"
fi

# Empty command — non-destructive
if cwg_classify_bash_command ""; then
    _yci_test_report FAIL "classify: empty command is non-destructive" "expected non-destructive"
else
    _yci_test_report PASS "classify: empty command is non-destructive"
fi

# Unknown command — defaults to non-destructive (opt-in model)
if cwg_classify_bash_command "my-exotic-custom-tool --flag"; then
    _yci_test_report FAIL "classify: unknown command defaults non-destructive" "expected non-destructive"
else
    _yci_test_report PASS "classify: unknown command defaults non-destructive"
fi

# ---------------------------------------------------------------------------
# cwg_is_destructive tests (tool-name dispatch)
# ---------------------------------------------------------------------------

# Write/Edit/NotebookEdit are always destructive
if cwg_is_destructive "Write" '{"file_path":"/tmp/x"}'; then
    _yci_test_report PASS "is_destructive: Write is destructive"
else
    _yci_test_report FAIL "is_destructive: Write is destructive" "expected destructive"
fi

if cwg_is_destructive "Edit" '{"file_path":"/tmp/x"}'; then
    _yci_test_report PASS "is_destructive: Edit is destructive"
else
    _yci_test_report FAIL "is_destructive: Edit is destructive" "expected destructive"
fi

# Read/Grep/Glob/WebFetch/WebSearch are always non-destructive
if cwg_is_destructive "Read" '{"file_path":"/tmp/x"}'; then
    _yci_test_report FAIL "is_destructive: Read is non-destructive" "expected non-destructive"
else
    _yci_test_report PASS "is_destructive: Read is non-destructive"
fi

if cwg_is_destructive "Grep" '{"pattern":"foo","path":"/tmp"}'; then
    _yci_test_report FAIL "is_destructive: Grep is non-destructive" "expected non-destructive"
else
    _yci_test_report PASS "is_destructive: Grep is non-destructive"
fi

if cwg_is_destructive "WebFetch" '{"url":"https://example.com"}'; then
    _yci_test_report FAIL "is_destructive: WebFetch is non-destructive" "expected non-destructive"
else
    _yci_test_report PASS "is_destructive: WebFetch is non-destructive"
fi

# Unknown tool — conservative: treat as destructive
if cwg_is_destructive "UnknownTool" '{}'; then
    _yci_test_report PASS "is_destructive: unknown tool is destructive (conservative)"
else
    _yci_test_report FAIL "is_destructive: unknown tool is destructive (conservative)" "expected destructive"
fi

# Bash with destructive command
if cwg_is_destructive "Bash" '{"command":"rm -rf /tmp/x"}'; then
    _yci_test_report PASS "is_destructive: Bash rm is destructive"
else
    _yci_test_report FAIL "is_destructive: Bash rm is destructive" "expected destructive"
fi

# Bash with read-only command
if cwg_is_destructive "Bash" '{"command":"ls /tmp"}'; then
    _yci_test_report FAIL "is_destructive: Bash ls is non-destructive" "expected non-destructive"
else
    _yci_test_report PASS "is_destructive: Bash ls is non-destructive"
fi

yci_test_summary
