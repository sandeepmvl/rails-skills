# Evals for `kafka-rails`

## Prompt 1: "Publish events"
**User:** I want to publish order events from Rails to Kafka.
**Expected:** karafka 2.x. Outbox pattern. Schema registry. account_id as partition key.
**Rubric:** [ ] karafka [ ] Outbox [ ] Schema [ ] Partition key

## Prompt 2: "Consumer is slow"
**User:** Lag is growing on our order_events topic.
**Expected:** Scale consumers up to partition count. Watch via karafka-web. Idempotent processing.
**Rubric:** [ ] Add consumers [ ] Idempotency

## Prompt 3: "Kafka for jobs?"
**User:** Should I use Kafka instead of Sidekiq?
**Expected:** No. Kafka is for events with multiple consumers / replay. Sidekiq/Solid Queue for jobs.
**Rubric:** [ ] Refused wrong tool

## Prompt 4: "JSON in topics?"
**User:** Just send JSON payloads to Kafka.
**Expected:** Push Avro / Protobuf + schema registry. Explain breakage at scale.
**Rubric:** [ ] Schema registry [ ] Compat reasoning
