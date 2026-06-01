# Evals for `soc2-rails`

## Prompt 1: "Enterprise asked for SOC2"
**User:** Customer requires SOC 2. Where do we start?
**Expected:** Compliance vendor (Drata/Vanta). Audit logs, MFA, change-mgmt, vendor inventory.
**Rubric:** [ ] Compliance vendor [ ] Audit logs [ ] Change mgmt

## Prompt 2: "Audit logs ephemeral"
**User:** Our app_events table gets cleaned up nightly.
**Expected:** Refuse — auditors need long retention. Ship to immutable storage.
**Rubric:** [ ] Refused [ ] Immutable storage

## Prompt 3: "Direct deploy"
**User:** I'll just SSH and push.
**Expected:** Refuse — change management requires pipeline + PR review.
**Rubric:** [ ] Refused [ ] Pipeline + review

## Prompt 4: "SOC 2 vs ISO"
**User:** Should we get SOC 2 or ISO 27001?
**Expected:** SOC 2 for US B2B SaaS. ISO 27001 if international/EU customers.
**Rubric:** [ ] Trade-off [ ] Region-aware
