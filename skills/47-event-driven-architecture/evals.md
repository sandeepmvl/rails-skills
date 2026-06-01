# Evals for `event-driven-architecture`

## Prompt 1: "Decouple notifications"
**User:** When an order is placed, send email + update analytics + fan out to billing.
**Expected:** Domain event with handlers. rails_event_store. Idempotent handlers.
**Rubric:** [ ] Event-based [ ] Handlers separated [ ] Idempotent

## Prompt 2: "Outbox?"
**User:** Should I publish to Kafka in after_create?
**Expected:** No — outbox pattern. Atomic with business write.
**Rubric:** [ ] Outbox [ ] Atomicity

## Prompt 3: "Event sourcing?"
**User:** Should we event-source our domain?
**Expected:** Probably not. Trade-offs. Audit log table often enough.
**Rubric:** [ ] Pushed back [ ] Carve-out for finance/regulatory

## Prompt 4: "Versioning"
**User:** I need to change the order.placed schema.
**Expected:** Emit v2 + keep v1, OR upcaster pattern. Don't break consumers.
**Rubric:** [ ] Versioning [ ] Migration strategy
