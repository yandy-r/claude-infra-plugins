# Handoff Checklist — Commercial Compliance Adapter

Reviewer: complete this checklist before the evidence bundle or deliverable
leaves the engagement. Tick each item or record an explicit waiver comment
explaining why it does not apply.

- [ ] No cross-customer references: search the evidence body for other customer
      IDs, slugs, hostnames, IP ranges, SOW numbers, or project codes that belong
      to a different engagement.
- [ ] Redaction rules applied: secrets, private keys, RFC1918/link-local IP
      addresses, and internal hostnames have been scrubbed per `redaction.rules`.
- [ ] Customer branding applied per engagement profile (header, logo, footer
      match the active profile's `deliverable.header_template`) — OR note
      "intentionally unbranded" with reviewer sign-off if branding is not required
      for this deliverable type.
- [ ] Evidence bundle signed (PGP or sigstore) by the approver named in the
      `approver` field of the bundle frontmatter.
- [ ] Rollback plan rehearsed on a non-production environment prior to the
      change window — OR record `rehearsed: false` with an explicit reviewer
      sign-off comment acknowledging the risk.
- [ ] Pre-check and post-check artifact paths are resolvable (no 404s, no
      broken local paths, no references to ephemeral sessions).
- [ ] `timestamp_utc` is ISO-8601 UTC format and falls within the approved
      change window (or change window is not required per the active profile).
- [ ] `profile_commit` resolves in the customer's profile repository and
      matches the profile version active at the time the change was executed.

## Exit criteria

All items above must be ticked, or carry an explicit waiver comment that
documents the reason and the reviewer's identity, before the bundle ships to
the customer. Unticked items with no waiver are a hard blocker. The reviewer
is accountable for the completeness of this checklist.
