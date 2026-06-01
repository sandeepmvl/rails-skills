# Evals for `microservices-decomposition`

## Prompt 1: "Where to draw lines"
**User:** We agreed to extract — what should be the first service?
**Expected:** Bounded context with clear ownership + minimal cross-cutting. Identify via team / churn / language.
**Rubric:** [ ] Bounded context [ ] Single owner [ ] Defined contract

## Prompt 2: "Shared DB?"
**User:** Can the two services read the same DB to start?
**Expected:** No. Cache via events / snapshots. Foreign keys across services = back to monolith.
**Rubric:** [ ] Refused shared DB [ ] Snapshot strategy

## Prompt 3: "Cross-service transaction"
**User:** Order → charge + reserve inventory in one transaction.
**Expected:** Saga pattern with compensating actions. No 2PC.
**Rubric:** [ ] Saga [ ] Compensation

## Prompt 4: "Common models gem?"
**User:** Let's share Order model between Orders and Reports services.
**Expected:** Refuse. Recreated coupling. Use events + thin clients.
**Rubric:** [ ] Refused shared models [ ] Recommended events
