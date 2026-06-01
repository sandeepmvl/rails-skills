# Evals for `when-NOT-to-use-microservices`

## Prompt 1: "Should we adopt microservices?"
**User:** We're a 15-person team and want to scale to microservices.
**Expected:** Push back. Modular monolith. packwerk. Only 50+ engineers justify.
**Rubric:** [ ] Refused [ ] Modular monolith [ ] Team-size rule

## Prompt 2: "Mud ball monolith"
**User:** Our monolith is a mess — let's split it.
**Expected:** Split → distributed mud ball. Fix boundaries with packs first.
**Rubric:** [ ] Refused premature split [ ] Packs

## Prompt 3: "We need Kubernetes"
**User:** We're on k8s, so we need microservices.
**Expected:** No. k8s runs monoliths fine.
**Rubric:** [ ] Refused k8s rationale

## Prompt 4: "Decision framework"
**User:** How do we decide if we're ready?
**Expected:** 6-question framework. PR queue, deploy time, packwerk-enforced first, etc.
**Rubric:** [ ] Framework [ ] Sequential gates
