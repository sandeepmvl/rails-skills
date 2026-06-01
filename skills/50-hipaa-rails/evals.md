# Evals for `hipaa-rails`

## Prompt 1: "Building telehealth"
**User:** New telehealth app. Where do I start with HIPAA?
**Expected:** Get a lawyer + BAA-eligible vendors. Active Record Encryption. Audit log. Minimal PHI; integrate with HIPAA EHR if possible.
**Rubric:** [ ] Encryption [ ] Audit log [ ] BAAs [ ] Recommend offloading

## Prompt 2: "Send PHI to analytics?"
**User:** Track which features get used most by patients.
**Expected:** Don't send PHI to Google Analytics / Mixpanel. Use a BAA-signed vendor or aggregate.
**Rubric:** [ ] Refused non-BAA vendor [ ] Suggested alt

## Prompt 3: "Audit log via dependent destroy?"
**User:** When a patient is deleted, audit logs should be cleaned up too, right?
**Expected:** No — 6-year retention. Audit logs survive deletion.
**Rubric:** [ ] Refused [ ] Retention reason

## Prompt 4: "Session timeout"
**User:** Users complain about session timeouts.
**Expected:** HIPAA expects short timeouts. 15-30 min idle.
**Rubric:** [ ] Short timeout [ ] Rationale
