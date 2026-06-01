# Evals for `gdpr-rails`

## Prompt 1: "DSAR endpoint"
**User:** EU user wants to download their data.
**Expected:** DsarExporter service; account+orders+activity+messages bundle; 30-day deadline.
**Rubric:** [ ] Exporter [ ] All categories [ ] Deadline

## Prompt 2: "Delete account"
**User:** User asks to delete all data.
**Expected:** Anonymise approach. Carve-outs (tax records). Audit log persists.
**Rubric:** [ ] Anonymise [ ] Carve-outs [ ] Audit retained

## Prompt 3: "Cookie banner"
**User:** Do I need a cookie banner?
**Expected:** Only if non-strictly-necessary cookies. CMP. Set cookies after consent.
**Rubric:** [ ] Conditional [ ] CMP

## Prompt 4: "Analytics in EU"
**User:** Use Mixpanel for product analytics in EU.
**Expected:** Pseudonymise. DPA required. Consider EU-region or self-host.
**Rubric:** [ ] Pseudonymise [ ] DPA
