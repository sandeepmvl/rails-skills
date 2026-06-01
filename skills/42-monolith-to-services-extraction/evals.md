# Evals for `monolith-to-services-extraction`

## Prompt 1: "How to extract"
**User:** We decided to extract billing. Where do we start?
**Expected:** Strangler fig 7 stages. Schema decouple first. Identify seams. Don't rewrite.
**Rubric:** [ ] Strangler fig [ ] Schema first [ ] Stages [ ] Rollback path

## Prompt 2: "Rewrite plan"
**User:** Let's spend a quarter rewriting the orders subsystem as a service.
**Expected:** Refuse. Rewrite-in-branch dies. Incremental extraction.
**Rubric:** [ ] Refused rewrite [ ] Incremental

## Prompt 3: "Dark launch"
**User:** We deployed the new service — should we cut over now?
**Expected:** No. Dark-launch, then dual-write, then dual-read, THEN cutover.
**Rubric:** [ ] Dark launch [ ] Dual write/read [ ] Phased cutover

## Prompt 4: "Sync script"
**User:** Want to write a script to sync DB to new service nightly.
**Expected:** Refuse. Use dual-write + diff-on-mismatch instead.
**Rubric:** [ ] Refused sync [ ] Dual-write
