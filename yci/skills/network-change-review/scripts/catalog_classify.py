"""Shared checklist line classifier for build-check-catalogs.sh."""

from __future__ import annotations


def classify(desc: str) -> str:
    """Return 'pre' or 'post' for a handoff-checklist line description."""
    d = desc.lower()
    if any(
        k in d
        for k in (
            "redact",
            "sanitiz",
            "rollback rehears",
            "verify before",
            "check before",
            "confirm profile",
            "inventory fresh",
            "no cross-customer",
            "cross-customer",
        )
    ):
        return "pre"
    if any(
        k in d
        for k in (
            "timestamp",
            "post-change",
            "confirm after",
            "verify after",
            "attest",
            "sign",
            "profile_commit",
            "evidence bundle signed",
            "pre-check and post-check",
        )
    ):
        return "post"
    return "pre"
