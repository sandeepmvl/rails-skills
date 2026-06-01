# Evals for `observability-rails-advanced`

## Prompt 1: "What to monitor"
**User:** Setting up monitoring — what do we measure?
**Expected:** RED for services, USE for resources. Symptom-based alerts.
**Rubric:** [ ] RED [ ] USE [ ] Symptom-based

## Prompt 2: "Alert fatigue"
**User:** On-call paged 12 times yesterday — most were nothing.
**Expected:** Audit alerts, multi-window multi-burn-rate, page only on customer impact.
**Rubric:** [ ] Audit [ ] Multi-window [ ] Customer impact rule

## Prompt 3: "SLO definition"
**User:** What's a good SLO for our API?
**Expected:** Availability target, latency target, error budget calc. SLO < SLA.
**Rubric:** [ ] SLO definition [ ] Error budget

## Prompt 4: "Runbook?"
**User:** Should every alert have a runbook?
**Expected:** Yes. Steps + diagnostics + remediation + escalation.
**Rubric:** [ ] Yes [ ] Sections
