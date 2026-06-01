---
name: event-driven-architecture
description: Event-driven architecture inside a Rails app or across services — domain events, transactional outbox, eventual consistency, idempotent handlers, the difference between domain events and integration events, event sourcing (and when NOT to do it), the rails_event_store gem. Use when the user mentions domain events, event sourcing, CQRS, transactional outbox, eventual consistency, event-driven, rails_event_store, "publish events when X happens", or asks how to decouple components in a Rails app.
---

# Event-Driven Architecture

> Domain events are the cleanest decoupling primitive in a Rails app. `Order#after_create_commit :publish_order_placed` lets billing, notifications, and analytics react without knowing about each other. This skill covers what to emit, how, and where event-driven goes wrong (event sourcing for everything is usually wrong).

## The opinion

> **Emit domain events for cross-cutting concerns (notifications, audit, analytics). Use the transactional outbox so events publish atomically with the business write. Distinguish domain events (what happened in your bounded context) from integration events (what you tell other services). Use `rails_event_store` for in-app event handling. Do NOT adopt event sourcing as the default — it's a powerful but expensive pattern.**

## Domain events vs integration events

| | Domain event | Integration event |
|---|---|---|
| Audience | Code inside your bounded context | Other services / downstream systems |
| Schema | Free to change | Versioned contract |
| Coupling | Loose internal | Hard external |
| Examples | `OrderConfirmed`, `EmailVerified` | `order.placed.v1`, `user.deleted.v1` |
| Transport | In-process pub/sub | Kafka / RabbitMQ |

Don't mix them. Internal domain events are private — change at will. Integration events are public APIs and follow the same compatibility rules as your HTTP API.

## Pattern 1: In-process domain events with rails_event_store

```ruby
# Gemfile
gem "rails_event_store"
```

```ruby
# config/initializers/rails_event_store.rb
require "rails_event_store"

Rails.configuration.event_store = RailsEventStore::Client.new

Rails.configuration.event_store.tap do |store|
  store.subscribe(OrderPlacedHandler, to: [Events::OrderPlaced])
  store.subscribe(NotifyOnOrderPlaced, to: [Events::OrderPlaced])
  store.subscribe(UpdateAnalytics, to: [Events::OrderPlaced])
end
```

```ruby
# app/events/order_placed.rb
module Events
  class OrderPlaced < RailsEventStore::Event
  end
end
```

```ruby
# app/services/place_order.rb
class PlaceOrder
  def call(cart:)
    order = nil
    ApplicationRecord.transaction do
      order = Order.create!(cart_to_attrs(cart))

      Rails.configuration.event_store.publish(
        Events::OrderPlaced.new(data: {
          order_id: order.id,
          account_id: order.account_id,
          total_cents: order.total_cents
        }),
        stream_name: "Order$#{order.id}"
      )
    end
    order
  end
end
```

Handlers:

```ruby
class NotifyOnOrderPlaced
  def call(event)
    OrderConfirmationMailer.with(order_id: event.data[:order_id]).confirmation.deliver_later
  end
end
```

**Gotcha:** sync handlers run INSIDE the publishing transaction by default. If a handler calls `deliver_later`, the job enqueues inside the transaction — if the transaction rolls back, the job stays in the queue and references a record that no longer exists. Use an async dispatcher (`RailsEventStore::AsyncDispatcher` / `AsyncHandler` with `after_commit`) for handlers that enqueue jobs or call external systems.

## Pattern 2: Transactional outbox

When events MUST reach external systems (Kafka, downstream service):

```ruby
# Migration
create_table :outbox_events do |t|
  t.string  :aggregate_type, null: false
  t.string  :aggregate_id, null: false
  t.string  :event_type, null: false
  t.jsonb   :payload, null: false, default: {}
  t.datetime :published_at
  t.timestamps
end
add_index :outbox_events, [:aggregate_type, :aggregate_id]
add_index :outbox_events, :published_at  # for the flusher's pending query
```

```ruby
class Order < ApplicationRecord
  after_create_commit :enqueue_order_placed_event

  private

  def enqueue_order_placed_event
    OutboxEvent.create!(
      aggregate_type: "Order",
      aggregate_id: id.to_s,
      event_type: "order.placed.v1",
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

Separate flusher:

```ruby
class OutboxFlusherJob < ApplicationJob
  def perform
    OutboxEvent.where(published_at: nil).order(:id).find_each(batch_size: 200) do |event|
      EventBus.publish(event.event_type, event.payload)
      event.update!(published_at: Time.current)
    end
  end
end
```

Recurring (every few seconds) via Solid Queue.

**Why this works:**
- Business write + outbox row commit atomically.
- Even if the broker is down for hours, events accumulate locally and publish when it recovers.
- Effectively-once: idempotent consumer + outbox = exactly-once business semantics.

## Pattern 3: Idempotent handlers

Re-delivery is the rule, not the exception. Handlers MUST be idempotent.

```ruby
class GrantStoreCreditOnOrderPlaced
  def call(event)
    return if StoreCreditTransaction.exists?(reason_id: event.data[:order_id], reason: "order_placed")

    StoreCreditTransaction.create!(
      account_id: event.data[:account_id],
      cents: (event.data[:total_cents] * 0.01).to_i,
      reason: "order_placed",
      reason_id: event.data[:order_id]
    )
  end
end
```

Patterns for idempotency:
- **Idempotency key** — a UNIQUE constraint on `(reason, reason_id)`.
- **Event log** — a `ProcessedEvent` table with UNIQUE(event_id).
- **Aggregate state check** — "if order already paid, skip" — works only when state implies the side effect.

## Pattern 4: Event versioning

Events are contracts. Embed the version:

```ruby
# Bad
EventBus.publish("order.placed", payload)

# Good
EventBus.publish("order.placed.v1", payload)
```

When you need to change the schema:

```ruby
EventBus.publish("order.placed.v2", new_shape_payload)
# Keep v1 emitting too, until all consumers migrate.
```

OR transform on the way in:

```ruby
class V1ToV2Upcaster
  def call(v1_payload)
    {
      order_id: v1_payload[:order_id],
      account_id: v1_payload[:account_id],
      total_cents: v1_payload[:total_cents],
      currency: v1_payload[:currency] || "USD"  # new in v2
    }
  end
end
```

## Pattern 5: Event ordering

In-process via rails_event_store: handlers run in subscription order, synchronously by default (in the same transaction as the publish).

For async / cross-service: ordering is per-partition (Kafka) / per-queue (RabbitMQ). Use entity ID as the partition key (see `kafka-rails`).

**Don't assume ordering across entities.** "Order placed for account 7" and "Account 7 upgraded plan" can arrive in either order. Handlers must tolerate both sequences.

## Pattern 6: Read models

Event handlers often update read models — denormalized projections optimized for queries.

```ruby
class UpdateAccountActivitySummary
  def call(event)
    summary = AccountActivitySummary.find_or_create_by!(account_id: event.data[:account_id])
    summary.with_lock do
      summary.update!(
        total_orders: summary.total_orders + 1,
        total_spend_cents: summary.total_spend_cents + event.data[:total_cents],
        last_activity_at: Time.current
      )
    end
  end
end
```

Now `AccountActivitySummary` is fast to read without a JOIN over `orders`.

This is the lite version of CQRS — you don't need full event sourcing to have read models.

## Pattern 7: Event sourcing (use sparingly)

Event sourcing = the events ARE the source of truth. State is replayed from the log.

```ruby
# A pure event-sourced aggregate
class Order
  def self.find(order_id)
    events = event_store.read.stream("Order$#{order_id}").to_a
    new.tap { |o| events.each { |e| o.apply(e) } }
  end

  def apply(event)
    case event
    when Events::OrderPlaced    then @state = :placed
    when Events::OrderPaid      then @state = :paid
    when Events::OrderShipped   then @state = :shipped
    when Events::OrderRefunded  then @state = :refunded
    end
  end
end
```

**Why this is rarely worth it:**
- Querying is hard. You need projections for everything.
- Migrations of historical events are painful — fix-up upcaster code lives forever.
- Tooling (admin panels, debugging) is much harder than CRUD.
- Most "we need an audit trail" problems are solvable with a `change_log` table, not event sourcing.

**When event sourcing IS right:**
- Financial / regulatory systems where the audit trail IS the system.
- Reversible workflows (orders that can be returned, refunded, replayed).
- Complex business logic that benefits from replaying past states.

## Common mistakes to refuse

- Don't publish events inline (without outbox) when consumers need durability.
- Don't write handlers that aren't idempotent.
- Don't share domain events with external systems. Domain events are internal.
- Don't event-source by default. Use it when the audit trail IS the product.
- Don't skip versioning event types.
- Don't assume cross-stream event ordering.
- Don't ignore handler errors silently. Log + DLQ + alert.

## When NOT to use this skill

- Simple CRUD app, no cross-cutting concerns. AR callbacks are enough.
- One-off background work. Solid Queue / Sidekiq.
- Tightly coupled state machines (e.g., a state machine library handles it). `state_machines-activerecord`.

## See also

- `kafka-rails` / `rabbitmq-rails` / `redis-streams-rails` — transports
- `cdc-debezium-rails` — CDC + outbox event router
- `solid-queue-and-sidekiq` — handler execution
- `microservices-decomposition` — integration events between services
- `safe-migrations` — outbox table migration patterns

## Sources

- [rails_event_store](https://railseventstore.org/)
- [Domain Events — Martin Fowler](https://martinfowler.com/eaaDev/DomainEvent.html)
- [Transactional Outbox — Microservices.io](https://microservices.io/patterns/data/transactional-outbox.html)
- [Event Sourcing — Greg Young](https://www.youtube.com/watch?v=8JKjvY4etTY)
- [DDD Reference — Eric Evans](https://www.domainlanguage.com/ddd/reference/)
- [Implementing Domain-Driven Design — Vaughn Vernon](https://www.informit.com/store/implementing-domain-driven-design-9780321834577)
