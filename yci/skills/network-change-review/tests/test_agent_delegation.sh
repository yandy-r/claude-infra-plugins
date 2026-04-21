#!/usr/bin/env bash
# yci network-change-review — delegation contract tests
#
# Verifies the skill-layer handoff to yci:change-reviewer remains wired and that
# the delegated reviewer is given active-profile context rather than relying on
# implicit runtime state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=./helpers.sh
source "${SCRIPT_DIR}/helpers.sh"

SKILL_MD="${SKILL_ROOT}/SKILL.md"
AGENT_MD="${PLUGIN_ROOT}/agents/change-reviewer.md"
REVIEW_SH="${SKILL_ROOT}/scripts/review.sh"

test_skill_delegates_to_yci_change_reviewer() {
    printf '\n--- delegation: skill delegates to yci reviewer ---\n'

    local skill_text
    [ -f "${SKILL_MD}" ] || { echo "Error: required file ${SKILL_MD} not found" >&2; exit 1; }
    skill_text="$(cat "${SKILL_MD}")"

    assert_contains 'subagent_type: "yci:change-reviewer"' "${skill_text}" \
        'SKILL.md uses yci:change-reviewer for diff review'

    assert_not_contains 'subagent_type: "ycc:code-reviewer"' "${skill_text}" \
        'SKILL.md no longer uses ycc:code-reviewer for diff review'
}

test_skill_passes_profile_context() {
    printf '\n--- delegation: skill passes active profile context ---\n'

    local skill_text
    [ -f "${SKILL_MD}" ] || { echo "Error: required file ${SKILL_MD} not found" >&2; exit 1; }
    skill_text="$(cat "${SKILL_MD}")"

    assert_contains '<profile-json-path>' "${skill_text}" \
        'SKILL.md prompt includes staged profile snapshot path'

    assert_contains '<inventory-root>' "${skill_text}" \
        'SKILL.md prompt includes inventory root'

    assert_contains '<customer-id>' "${skill_text}" \
        'SKILL.md prompt includes resolved customer id'

    assert_contains 'load-profile.sh' "${skill_text}" \
        'SKILL.md stages profile context via load-profile.sh'

    assert_contains 'absolute path, keep' "${skill_text}" \
        'SKILL.md documents absolute inventory-root precedence'

    assert_contains '<resolved-data-root>/profiles/<inventory-root>' "${skill_text}" \
        'SKILL.md documents profiles-relative inventory-root precedence'

    assert_contains '<resolved-data-root>/<inventory-root>' "${skill_text}" \
        'SKILL.md documents data-root-relative inventory-root precedence'
}

test_change_reviewer_contract_mentions_customer_guard() {
    printf '\n--- delegation: reviewer contract documents isolation ---\n'

    local agent_text
    [ -f "${AGENT_MD}" ] || { echo "Error: required file ${AGENT_MD} not found" >&2; exit 1; }
    agent_text="$(cat "${AGENT_MD}")"

    assert_contains 'profile.json' "${agent_text}" \
        'change-reviewer.md references staged profile snapshot'

    assert_contains 'inventory root' "${agent_text}" \
        'change-reviewer.md references inventory root boundary'

    assert_contains 'source of truth for active-customer state' "${agent_text}" \
        'change-reviewer.md treats profile snapshot as customer source of truth'

    assert_contains 'do not require them to live under the inventory root' "${agent_text}" \
        'change-reviewer.md allows caller-supplied diff/profile paths outside inventory root'
}

test_review_sh_text_matches_delegation() {
    printf '\n--- delegation: review.sh help text matches reviewer path ---\n'

    local review_text
    [ -f "${REVIEW_SH}" ] || { echo "Error: required file ${REVIEW_SH} not found" >&2; exit 1; }
    review_text="$(cat "${REVIEW_SH}")"

    assert_contains 'yci:change-reviewer' "${review_text}" \
        'review.sh references yci:change-reviewer'

    assert_not_contains 'ycc:code-reviewer' "${review_text}" \
        'review.sh no longer references ycc:code-reviewer'
}

test_skill_delegates_to_yci_change_reviewer
test_skill_passes_profile_context
test_change_reviewer_contract_mentions_customer_guard
test_review_sh_text_matches_delegation

summary
