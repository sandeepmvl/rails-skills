---
name: kafka-rails
description: Apache Kafka in Rails — producing and consuming with karafka (recommended), racecar as a thin alternative, ruby-kafka legacy notes, schema management with Avro/Protobuf, partitioning strategy, consumer group offsets, exactly-once vs at-least-once delivery semantics, idempotent consumers, the outbox pattern for transactional publish. Use when the user mentions Kafka, karafka, racecar, ruby-kafka, event streaming, Confluent, MSK, schema registry, partitions, consumer group, or asks how to publish/consume events at scale from Rails.
---

# Kafka in Rails

> Kafka is the right tool when you have multiple consumers of the same event stream, need replay, or need to retain events for days. Wrong tool for "I want to send a job" — use Solid Queue / Sidekiq. This skill covers production patterns for Rails apps using karafka, the maintained Ruby Kafka client.

## The opinion

> **Use `karafka` 2.x for both producing and consuming. Use the Confluent Schema Registry with Avro or Protobuf — never raw JSON in production. Pick partition keys by entity (e.g., `account_id`) so per-entity events are ordered. Consumers are at-least-once by default — make them idempotent. For transactional publish, use the outbox pattern (write to DB + outbox in one transaction, separate process flushes to Kafka).**

Counter-positions:
- **racecar** (Heroku) — simpler, but less actively maintained; lacks karafka's web UI, swarm mode, and DLQ support.
- **ruby-kafka** — the underlying low-level client; rarely used directly anymore.
- **rdkafka-ruby** — karafka's underlying high-perf binding to librdkafka. Use directly only if you need very low-latency.

## Setup

```ruby
# Gemfile
gem "karafka", "~> 2.4"
gem "karafka-web"  # admin UI
gem "avro_turf"    # for schema registry; or "google-protobuf"
```

```ruby
# karafka.rb (at the project root)
class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = {
      "bootstrap.servers": ENV.fetch("KAFKA_BROKERS"),
      "client.id": "myapp",
      "compression.type": "zstd"
    }
    config.client_id = "myapp"
    config.consumer_persistence = !Rails.env.development?
  end

  Karafka::Web.enable!

  routes.draw do
    topic "order_events" do
      consumer OrderEventsConsumer
      max_messages 100
      max_wait_time 1_000
      dead_letter_queue topic: "order_events_dlq", max_retries: 5
    end
  end
end
```

## Pattern 1: Producing events (with outbox)

NEVER produce inline. If the broker is down, your business transaction can't commit (or commits with a missing event). Use the **outbox pattern** — canonical schema defined in [`event-driven-architecture`](../47-event-driven-architecture/SKILL.md):

```ruby
# OutboxEvent schema: id, aggregate_type, aggregate_id, event_type, payload (jsonb),
# published_at, timestamps. See event-driven-architecture skill for the migration.
class Order < ApplicationRecord
  after_create_commit :enqueue_order_placed

  private

  def enqueue_order_placed
    OutboxEvent.create!(
      aggregate_type: "Order",
      aggregate_id:   id.to_s,
      event_type:     "order.placed.v1",
      payload: {
        order_id: id,
        account_id: account_id,
        total_cents: total_cents,
        placed_at: created_at.iso8601
      }
    )
  end
end
```

Separate worker process flushes outbox → Kafka. Map the canonical outbox columns to Kafka's wire fields at publish time (topic from `event_type` prefix or a routing table; partition key from `aggregate_id` to preserve per-entity ordering):

```ruby
class OutboxFlusherJob < ApplicationJob
  queue_as :outbox

  TOPIC_MAP = { "Order" => "order_events", "User" => "user_events" }.freeze

  def perform
    OutboxEvent.where(published_at: nil).order(:id).find_each(batch_size: 500) do |event|
      flush(event)
    end
  end

  private

  # At-least-once: if `update!` fails after a successful publish, the next run
  # republishes the event. Consumers must be idempotent (see Pattern 2).
  def flush(event)
    Karafka.producer.produce_sync(
      topic:   TOPIC_MAP.fetch(event.aggregate_type),
      key:     event.aggregate_id,                   # partition key
      payload: event.payload.merge(event_type: event.event_type).to_json
    )
    event.update!(published_at: Time.current)
  rescue WaterDrop::Errors::ProduceError => e
    Rails.error.report(e, context: { event_id: event.id })
    raise  # break the loop; retry on next run
  end
end
```

Run this job continuously (Solid Queue recurring, or a dedicated daemon).

**Why outbox:**
- The DB transaction wraps the business write + outbox row. Atomic.
- If Kafka is down, business work succeeds and events queue up locally.
- Exactly-once-effectively-once: idempotent consumer + outbox replay protection.

## Pattern 2: Consuming

```ruby
class OrderEventsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      payload = message.payload  # already-parsed JSON / Avro / Protobuf

      case payload[:event_type]
      when "order.placed"   then handle_order_placed(payload)
      when "order.paid"     then handle_order_paid(payload)
      when "order.shipped"  then handle_order_shipped(payload)
      end
    end

    # Commit the offset for the LAST processed message in the batch — much cheaper than
    # committing per-message. karafka will also auto-commit on batch success if you
    # leave `automatic_offset_management` at its default.
    mark_as_consumed!(messages.last)
  end

  private

  def handle_order_placed(payload)
    # Idempotency — guard against re-delivery
    return if ProcessedEvent.exists?(event_id: payload[:order_id], event_type: "order.placed")

    ApplicationRecord.transaction do
      ProcessedEvent.create!(event_id: payload[:order_id], event_type: "order.placed")
      # ... actual work
    end
  end
end
```

Run the consumer:

```bash
bundle exec karafka server
```

In Kamal: a separate role, separate container — see `kamal-docker-production`.

## Pattern 3: Schema management (Avro)

```ruby
# Gemfile
gem "avro_turf"
```

```ruby
# config/initializers/avro.rb
require "avro_turf/messaging"

AVRO = AvroTurf::Messaging.new(
  registry_url: ENV.fetch("SCHEMA_REGISTRY_URL"),
  schemas_path: Rails.root.join("avro_schemas")
)
```

```ruby
# Producing
encoded = AVRO.encode(
  { "order_id" => order.id, "amount" => order.total_cents },
  subject: "order_placed",
  version: 1
)
Karafka.producer.produce_sync(topic: "order_events", key: order.account_id.to_s, payload: encoded)

# Consuming
def consume
  messages.each do |message|
    payload = AVRO.decode(message.raw_payload)
    # ...
  end
end
```

**Why Avro / Protobuf over JSON:**
- Schema registry validates compatibility on every produce.
- Breaking changes caught at deploy time, not runtime.
- Smaller payloads.
- Strongly typed downstream consumers.

## Pattern 4: Partitioning strategy

Pick a key such that:

- All events for one entity → same partition (ordering preserved per entity).
- High enough cardinality to distribute load.

```yaml
# Good — orders per account stay ordered
payload: { ... }, key: order.account_id.to_s

# Bad — global ordering, single partition becomes bottleneck
payload: { ... }, key: "all"

# Bad — random; per-entity ordering is lost
payload: { ... }, key: SecureRandom.uuid
```

If you need stricter ordering AND high throughput, partition by a more granular key (e.g., `order_id`) at the cost of cross-entity ordering.

## Pattern 5: Delivery semantics

| Semantic | How |
|---|---|
| At-most-once | Commit offset BEFORE processing. Loses messages on crash. Rarely correct. |
| At-least-once | Commit offset AFTER processing. Default. Requires idempotent consumer. |
| Exactly-once (Kafka transactional) | `transactional.id` on producer + read-process-write in a Kafka transaction. Complex, real overhead. Use only when you must. |

Default to at-least-once + idempotent consumers. The `ProcessedEvent` table is your idempotency log.

## Pattern 6: Dead-letter queue

Failed messages should NOT block the consumer. After N retries, ship to a DLQ topic:

```ruby
routes.draw do
  topic "order_events" do
    consumer OrderEventsConsumer
    dead_letter_queue topic: "order_events_dlq", max_retries: 5
  end
end
```

Build an admin tool to inspect DLQ, fix the underlying issue, and replay messages back to the main topic.

## Pattern 7: Consumer groups in production

```ruby
# config/karafka.rb
config.client_id = "myapp"  # consumer group derived from client_id + topic
```

- Each topic + consumer group has independent offset tracking.
- Add more consumer instances to scale horizontally (up to partition count).
- Re-deploy = consumer rebalance. Use `karafka-web` to monitor lag.

```bash
# Watch consumer lag
bundle exec karafka info
```

If lag grows: add consumers (up to partition count), or look for slow processing.

## Pattern 8: Schema evolution

Backward-compatible: add nullable fields. Never remove fields. Never change types.

```json
{
  "type": "record",
  "name": "OrderPlaced",
  "fields": [
    {"name": "order_id", "type": "string"},
    {"name": "amount_cents", "type": "int"},
    {"name": "currency", "type": "string", "default": "USD"}
  ]
}
```

Add `default` for every new field so old consumers still parse.

## Common mistakes to refuse

- Don't produce inline in the request cycle. Outbox.
- Don't send raw JSON in production. Use a schema registry.
- Don't share consumer groups across services accidentally.
- Don't use a single partition for ordered writes — that's a single-threaded bottleneck.
- Don't catch + ignore consume errors. Let them surface to DLQ.
- Don't pick UUID as the partition key.
- Don't use Kafka for "delayed job in 1 minute." Use Solid Queue.

## When NOT to use Kafka

- Internal job queue. Use Solid Queue / Sidekiq.
- Pub/sub across <5 consumers within the same app. Use ActionCable / Redis pub/sub.
- Database-to-database replication. Use CDC (see `cdc-debezium-rails`).
- Request/response. Use HTTP.

## See also

- `event-driven-architecture` — when to emit which events
- `cdc-debezium-rails` — CDC into Kafka topics
- `solid-queue-and-sidekiq` — for jobs, not events
- `rabbitmq-rails` / `redis-streams-rails` — alternatives
- `observability-rails-advanced` — Kafka consumer lag dashboards

## Sources

- [karafka 2.x docs](https://karafka.io/docs/)
- [Apache Kafka](https://kafka.apache.org/documentation/)
- [Confluent Schema Registry](https://docs.confluent.io/platform/current/schema-registry/index.html)
- [Outbox pattern](https://microservices.io/patterns/data/transactional-outbox.html)
- [Designing Event-Driven Systems — Ben Stopford](https://www.confluent.io/designing-event-driven-systems/)
- [avro_turf](https://github.com/dasch/avro_turf)
- [racecar (alternative)](https://github.com/zendesk/racecar)
