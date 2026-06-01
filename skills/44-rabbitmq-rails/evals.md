# Evals for `rabbitmq-rails`

## Prompt 1: "Publish events"
**User:** Set up RabbitMQ for order events.
**Expected:** bunny producer, topic exchange, durable + persistent. Outbox suggested.
**Rubric:** [ ] Topic exchange [ ] Durable [ ] Persistent

## Prompt 2: "Consumer crashed mid-process"
**User:** A consumer crashed and we lost messages.
**Expected:** manual ack (ack: true), reject on failure → DLX, no auto-ack.
**Rubric:** [ ] Manual ack [ ] DLX

## Prompt 3: "Should I use this for delayed jobs?"
**User:** RabbitMQ for sending email in 5 minutes?
**Expected:** No — use Solid Queue.
**Rubric:** [ ] Refused [ ] Right tool

## Prompt 4: "RabbitMQ vs Kafka"
**User:** Which one for our event bus?
**Expected:** Kafka for replay / retention / stream semantics. RabbitMQ for routing flexibility / work distribution.
**Rubric:** [ ] Both presented [ ] Use-case based
