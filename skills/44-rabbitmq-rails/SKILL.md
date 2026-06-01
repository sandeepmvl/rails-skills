---
name: rabbitmq-rails
description: RabbitMQ in Rails — bunny client, sneakers for consumers, exchange topology (direct / fanout / topic / headers), durable queues + persistent messages, acknowledgements, dead-letter exchanges, prefetch tuning, when RabbitMQ is the right tool vs Kafka vs Solid Queue. Use when the user mentions RabbitMQ, bunny gem, sneakers, AMQP, exchange, queue binding, dead-letter, message acknowledgement, "should we use RabbitMQ", or has a workflow needing complex routing or work distribution across heterogeneous workers.
---

# RabbitMQ in Rails

> RabbitMQ is the right tool for complex routing (one publisher, many topologies of consumers), heterogeneous workers (Ruby + Python + Go all reading the same queue), and work distribution. Wrong tool when you need replay, long retention, or stream semantics — that's Kafka.

## The opinion

> **Use `bunny` (synchronous AMQP client) for producing. Use `sneakers` for consuming long-running workers (it integrates with Rails). Always declare durable exchanges + queues + persistent messages. Acknowledge manually (`manual_ack: true`) after work succeeds — autoack drops messages on crash. Set a sane `prefetch` (10-50) per consumer. Use a dead-letter exchange for failures.**

Counter-positions:
- **Kafka** for event streams with replay / fan-out / retention. RabbitMQ deletes messages after ack.
- **Solid Queue / Sidekiq** for in-app jobs. Don't pull in RabbitMQ for a delayed email.
- **Redis Streams** for lightweight Kafka-like patterns (see `redis-streams-rails`).

## Setup

```ruby
# Gemfile
gem "bunny", "~> 2.22"
gem "sneakers", "~> 2.12"
```

```ruby
# config/initializers/rabbitmq.rb
RABBIT = Bunny.new(
  ENV.fetch("RABBITMQ_URL"),
  automatically_recover: true,
  network_recovery_interval: 5,
  threaded: true
)
RABBIT.start

at_exit { RABBIT.close }
```

```ruby
# config/initializers/sneakers.rb
Sneakers.configure(
  amqp: ENV.fetch("RABBITMQ_URL"),
  daemonize: false,
  workers: 4,
  threads: 5,
  prefetch: 10,
  log: STDOUT
)
Sneakers.logger.level = Logger::INFO
```

## Pattern 1: Publishing

```ruby
# Long-lived publisher channel — opening a fresh channel per publish is an
# anti-pattern that exhausts broker channel limits at high publish rates.
class OrderEventPublisher
  CHANNEL = RABBIT.create_channel
  EXCHANGE = CHANNEL.topic("events.orders", durable: true)

  def self.publish(event_type:, payload:)
    EXCHANGE.publish(
      payload.to_json,
      routing_key: event_type,                   # e.g. "order.placed"
      persistent: true,                          # durable on disk
      content_type: "application/json",
      message_id: SecureRandom.uuid,             # idempotency aid for consumers
      timestamp: Time.current.to_i
    )
  end
end

# Usage
OrderEventPublisher.publish(
  event_type: "order.placed",
  payload: { order_id: 42, account_id: 7, total_cents: 12_500 }
)
```

`persistent: true` + `durable: true` exchange + `durable: true` queue = messages survive broker restart.

**Outbox pattern recommended** (same as `kafka-rails` — write to DB + outbox row in one transaction, separate flusher publishes). Inline publish ties your transaction to broker availability.

## Pattern 2: Consuming with sneakers

```ruby
# app/workers/order_placed_worker.rb
class OrderPlacedWorker
  include Sneakers::Worker

  from_queue "orders.placed",
    exchange: "events.orders",
    exchange_type: :topic,
    routing_key: "order.placed",
    durable: true,
    ack: true,         # manual ack
    arguments: { "x-dead-letter-exchange" => "events.orders.dlx" }

  def work(payload)
    data = JSON.parse(payload, symbolize_names: true)

    return ack! if ProcessedEvent.exists?(message_id: data[:order_id])

    ApplicationRecord.transaction do
      ProcessedEvent.create!(message_id: data[:order_id])
      # business work
    end

    ack!
  rescue StandardError => e
    Rails.error.report(e, context: { worker: self.class.name, payload: payload })
    reject!  # → DLX
  end
end
```

Run consumers via the bundled rake task:

```bash
WORKERS=OrderPlacedWorker,OrderShippedWorker bundle exec rake sneakers:run
```

Or programmatically via `Sneakers::Runner` in `config/sneakers.rb`:

```ruby
Sneakers::Runner.new([OrderPlacedWorker, OrderShippedWorker]).run
```

In production, run sneakers as its own role (separate Kamal accessory or docker-compose service).

## Pattern 3: Exchange topology

```
Producer ──── publishes to ────► [exchange]
                                     │
                                     │ routing rules
                                     ▼
                                  [queue 1]──► consumer A
                                  [queue 2]──► consumer B
```

| Exchange | Routing | When |
|---|---|---|
| **direct** | Exact match on routing key | "Process this exact event type" |
| **topic** | Pattern match (`order.*`, `*.placed`) | Default for events; flexible binding |
| **fanout** | Broadcast to all bound queues | Notifications / cache invalidation |
| **headers** | Match on message headers | Rare; use topic instead |

```ruby
# Topic exchange with multiple bindings
channel = RABBIT.create_channel
exchange = channel.topic("events.orders", durable: true)

# Consumer A: only placed orders
queue_a = channel.queue("orders.placed", durable: true)
queue_a.bind(exchange, routing_key: "order.placed")

# Consumer B: all order events, for analytics
queue_b = channel.queue("orders.analytics", durable: true)
queue_b.bind(exchange, routing_key: "order.*")
```

## Pattern 4: Dead-letter exchange

Run this at boot once (e.g., an initializer) — not inside a request:

```ruby
# config/initializers/rabbitmq_topology.rb
channel = RABBIT.create_channel
channel.exchange("events.orders.dlx", type: :topic, durable: true)

channel.queue("orders.placed.dead", durable: true).tap do |q|
  q.bind("events.orders.dlx", routing_key: "order.placed")
end

channel.queue("orders.placed", durable: true,
  arguments: {
    "x-dead-letter-exchange" => "events.orders.dlx",
    "x-message-ttl" => 60 * 60 * 24 * 1000  # 24h TTL on messages
  }
).bind(channel.topic("events.orders", durable: true), routing_key: "order.placed")

channel.close
```

Failed (rejected) messages go to the DLX. Build a tool to:
- Inspect DLX queues.
- Re-publish messages back to the main exchange after fixing the bug.

## Pattern 5: Prefetch tuning

```yaml
# sneakers.rb
prefetch: 10
```

- **prefetch=1** — round-robin, slow workers don't starve others. Good for very heterogeneous work.
- **prefetch=10-50** — default. Good for typical workloads.
- **prefetch=unbounded** — never. One slow consumer hoards messages.

Watch consumer queue depth in RabbitMQ management UI. If depth grows: tune prefetch up OR add more workers.

## Pattern 6: Retry with exponential backoff

```ruby
class OrderPlacedWorker
  include Sneakers::Worker

  from_queue "orders.placed",
    handler: Sneakers::Handlers::Maxretry,
    arguments: {
      "x-dead-letter-exchange" => "events.orders.dlx",
      "x-message-ttl" => 30_000  # 30s before retry
    }

  def work(payload)
    # ... business logic ...
    ack!
  end
end
```

Sneakers' `Maxretry` handler:
- Rejects → goes to retry queue with TTL.
- After TTL → re-enqueued.
- After N total attempts → DLX.

## Pattern 7: Health, alerting

Monitor:
- **Queue depth** — growing = consumer can't keep up.
- **Unacked messages** — workers stuck.
- **DLX depth** — bugs accumulating.
- **Connection / channel count** — exhaustion = leak.

Hook RabbitMQ Prometheus exporter to Grafana. Alert on:
- Queue depth growth rate.
- Unacked > N for > 5 minutes.
- DLX > 0 (any DL = paging-worthy in most cases).

## Pattern 8: Avoid the giant queue

Don't put all event types into one queue. Split by handler:

```
events.orders ─── routing key "order.placed"  → orders.placed ──► worker A
                ── routing key "order.shipped" → orders.shipped ──► worker B
                ── routing key "order.refunded"→ orders.refunded──► worker C
```

If a worker is slow, only its queue backs up — not the whole event stream.

## When NOT to use RabbitMQ

- **Replay needed** — RabbitMQ deletes after ack. Use Kafka.
- **In-app jobs only** — use Solid Queue / Sidekiq. They have native scheduling, retry, web UI.
- **You need ordering across millions of messages with horizontal consumer scaling** — Kafka's partitions are simpler.
- **You're already on Solid Queue and don't have polyglot consumers** — adding RabbitMQ is operational overhead.

## Common mistakes to refuse

- Don't use auto-ack. You lose messages on consumer crashes.
- Don't publish to non-durable exchanges in production. Restart = data loss.
- Don't catch errors silently. Reject → DLX.
- Don't share one queue across many event types. Route via exchange.
- Don't ignore the DLX. Alert on it. Replay or discard manually after fix.
- Don't pull RabbitMQ in for "delayed jobs in 5 minutes" — Solid Queue does that with one fewer service.

## See also

- `kafka-rails` — when replay / retention matters
- `redis-streams-rails` — lightweight alternative
- `solid-queue-and-sidekiq` — for in-app jobs
- `event-driven-architecture` — domain events as the unit of design

## Sources

- [RabbitMQ docs](https://www.rabbitmq.com/documentation.html)
- [bunny gem](https://github.com/ruby-amqp/bunny)
- [sneakers gem](https://github.com/jondot/sneakers)
- [AMQP 0-9-1 reference](https://www.rabbitmq.com/amqp-0-9-1-reference.html)
- [Dead letter exchanges](https://www.rabbitmq.com/dlx.html)
- [Outbox pattern](https://microservices.io/patterns/data/transactional-outbox.html)
