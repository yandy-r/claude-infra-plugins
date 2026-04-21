# Consultant Brand Block

This file is the consultant-side brand block embedded in every artifact produced by
`yci:network-change-review`. `render-artifact.sh` reads this file verbatim, resolves
the `{{yci_commit}}` slot, then uses the result as the `{{consultant_brand_block}}`
slot value. The `**Prepared by**` heading MUST appear verbatim — the end-to-end
acceptance test (step 6.1) greps for it to assert the consultant-brand block is
present in every rendered artifact.

---

## Prepared by

**Consulting:** Yandy Consulting Infrastructure (yci)
**Contact:** <consultant@example.invalid>
**Skill:** `yci:network-change-review`
**Version:** {{yci_commit}}

> This deliverable was prepared under an active engagement. Redistribution is
> restricted per SOW.

---
