---
name: microservices-decomposition
description: Decomposing a Rails monolith into services — bounded contexts, service boundaries, public-API contracts, ownership of data, service-to-service authentication, the "shared library" trap, distributed-transaction patterns (saga, outbox), how to NOT recreate the monolith over HTTP. Use ONLY after the user has answered YES to the gating questions in when-NOT-to-use-microservices. Use when the user asks how to split the monolith, where to draw service lines, bounded contexts, DDD aggregates, service-to-service auth, or has 50+ engineers and is past the modular-monolith stage.
---

# Microservices Decomposition

> If you're reading this skill instead of [`when-NOT-to-use-microservices`](../40-when-NOT-to-use-microservices/SKILL.md), you've already justified the operational uplift. This skill is about HOW, not WHETHER. The wrong cuts produce distributed monoliths — same coupling, worse latency.

## The opinion

> **Decompose by bounded context, not by entity. A "Users service" is wrong. An "Identity service" or a "Billing service" is right. Each service owns its data — no cross-service joins, no cross-service foreign keys. Communicate via async events for non-critical flows and HTTP for synchronous queries. Authenticate service-to-service with short-lived JWTs or mTLS. Never write a "shared models gem."**

## Step 1: Identify bounded contexts

A bounded context is a chunk of business capability with its own ubiquitous language. In an e-commerce monolith:

- **Catalog** — products, SKUs, categories, descriptions. Owned by content team.
- **Inventory** — stock levels, reservations, warehouse locations. Owned by ops.
- **Orders** — cart, checkout, fulfillment state. Owned by commerce.
- **Billing** — payment methods, invoices, refunds. Owned by finance.
- **Identity** — users, sessions, OAuth, 2FA. Owned by platform.
- **Shipping** — carriers, labels, tracking. Owned by logistics.

These are NOT the same as your AR models. A `User` row might be touched by Identity (auth) and Billing (Stripe customer ID) and Orders (purchase history) — each context has its own view.

### How to find boundaries

1. **Map the language.** What words do business folks use? "Order" might mean different things in Cart context vs Fulfillment context.
2. **Look at team ownership.** Who gets paged when X breaks? That person's team should own the service.
3. **Track who edits what.** `git log --pretty=format: --name-only` for the last 6 months. Files churned by exactly one team are good candidates for extraction.
4. **Conway's law check.** If two teams constantly merge-conflict in the same file, that file is in the wrong service.

### Bad cuts (red flags)

- **"User Service"** — every service needs user data; this becomes the chokepoint.
- **"Database Service"** — wrapping the DB in HTTP is the worst of both worlds.
- **"Notification Service"** — too small. Notifications are a feature of every domain.
- **"Utils Service"** — what does it own? Nothing. Don't.

## Step 2: Define the contract

Each service exposes:

1. **A public HTTP/gRPC API.** Versioned. Documented. Backward-compatible.
2. **Events it publishes.** With a schema (Avro, Protobuf, or strict JSON Schema).
3. **Events it consumes.** Also schema'd.

```yaml
# billing-service/api/openapi.yaml
openapi: 3.1.0
info:
  title: Billing Service
  version: 1.0.0
paths:
  /v1/customers/{id}/invoices:
    get:
      ...
```

```ruby
# billing-service/app/events/invoice_finalized.rb
class Events::InvoiceFinalized
  SCHEMA = {
    type: "object",
    required: %w[invoice_id customer_id amount_cents currency finalized_at],
    properties: {
      invoice_id: { type: "string" },
      customer_id: { type: "string" },
      amount_cents: { type: "integer" },
      currency: { type: "string", enum: %w[USD EUR GBP] },
      finalized_at: { type: "string", format: "date-time" }
    }
  }
end
```

## Step 3: Own your data

Each service has its own database. Period.

```
[Catalog Service]──own DB──┐
[Inventory Service]──own DB──┐
[Orders Service]──own DB──┐
[Billing Service]──own DB──┘
```

**No shared DB.** If two services need the same data, one OWNS it and the other CACHES a denormalized copy via events.

```ruby
# In Orders Service, when we need the product name on the order line:
class OrderLine < ApplicationRecord
  # We store product_id, product_name, product_price_cents AT THE TIME OF ORDER.
  # We don't query Catalog Service for the name when rendering.
  validates :product_id, :product_name_snapshot, :unit_price_cents_snapshot, presence: true
end
```

**Why snapshots:** the product name in Catalog can change. The order's historical price must not.

## Step 4: Communicate

### Synchronous (HTTP / gRPC)

When the caller needs an immediate answer.

```ruby
# orders-service/app/services/inventory_client.rb
class InventoryClient
  def reserve(sku:, quantity:, order_id:)
    response = http.post("/v1/reservations", json: {
      sku: sku, quantity: quantity, order_id: order_id
    })
    raise InsufficientInventory unless response.status == 201
    JSON.parse(response.body)
  end

  private

  def http
    @http ||= Faraday.new(url: ENV.fetch("INVENTORY_URL")) do |f|
      f.request :json
      f.response :json
      f.request :retry, max: 3
      f.options.timeout = 2  # 2s hard ceiling
    end
  end
end
```

Wrap in a circuit breaker (`stoplight`). Set a strict timeout (1-5s). See `external-api-integration`.

### Asynchronous (events)

When the caller doesn't need an immediate answer.

```ruby
# catalog-service emits:
EventBus.publish("catalog.product_renamed", {
  product_id: product.id,
  old_name: previous_name,
  new_name: product.name,
  changed_at: Time.current
})

# orders-service consumes and updates ITS denormalized copy:
class CatalogProductRenamedConsumer
  def consume(event)
    OrderLine.where(product_id: event[:product_id]).update_all(
      product_name_for_display: event[:new_name]
    )
    # Note: historical SKU snapshot stays unchanged.
  end
end
```

See `event-driven-architecture` and `kafka-rails` for transport details.

## Step 5: Service-to-service auth

Don't use long-lived API keys. Use short-lived signed JWTs minted by an internal IdP.

```ruby
# Signing a request — HMAC: same secret on both sides.
class ServiceTokenSigner
  def self.for(audience:)
    JWT.encode({
      iss: Rails.application.name,
      aud: audience,
      iat: Time.current.to_i,
      exp: 60.seconds.from_now.to_i
    }, ENV.fetch("SERVICE_SHARED_SECRET"), "HS256")
  end
end

# Verifying on the receiving end — same secret as signer (HS256 is symmetric).
class ServiceTokenVerifier
  def self.verify!(token, expected_audience:)
    payload, = JWT.decode(token, ENV.fetch("SERVICE_SHARED_SECRET"), true, {
      algorithm: "HS256",
      aud: expected_audience,
      verify_aud: true
    })
    payload
  end
end
```

Better: mTLS at the mesh layer (Istio, Linkerd) — every service has a cert, every connection is authenticated, no app code change. See `distributed-tracing-rails` for service mesh integration.

## Step 6: Distributed transactions = sagas

You CAN'T `BEGIN; do stuff in 3 services; COMMIT` across services. Instead:

```
Order placed →
  1. Reserve inventory (call Inventory Service)
  2. Charge payment (call Billing Service)
  3. If charge fails → release inventory reservation
  4. If charge succeeds → confirm order
```

Implement as a saga with compensating actions:

```ruby
class PlaceOrderSaga
  def call(cart)
    steps = []

    reservation = InventoryClient.reserve(sku: cart.sku, quantity: cart.qty, order_id: cart.id)
    steps << -> { InventoryClient.release(reservation.id) }

    charge = BillingClient.charge(customer_id: cart.user_id, cents: cart.total)
    steps << -> { BillingClient.refund(charge.id) }

    order = Order.create!(cart: cart, charge_id: charge.id, reservation_id: reservation.id)
    order
  rescue => e
    steps.reverse.each do |compensate|
      compensate.call rescue Rails.error.report($!)
    end
    raise
  end
end
```

In practice, run sagas via a workflow engine (Temporal, AWS Step Functions) once they get complex — manual compensation is error-prone.

## Step 7: The shared library trap

DON'T:

```yaml
# bad: a "common_models" gem shared between Orders and Billing
# Every change requires a coordinated deploy of both. You've recreated the monolith.
gem "myapp-common-models", git: "..."
```

DO:

- Publish events with schemas the other side parses with **its own** models.
- Share thin client gems for HTTP/gRPC contracts ONLY (generated from OpenAPI / proto).
- Never share business logic between services.

## Step 8: Observability

Each service emits:

- Structured logs with `request_id` / `trace_id` propagated across hops.
- Metrics (RED: rate, errors, duration).
- Traces (OpenTelemetry — see `distributed-tracing-rails`).

Without these, debugging cross-service issues is impossible.

## Common mistakes to refuse

- Don't split on entity boundaries. Split on capability boundaries.
- Don't share a database between services.
- Don't make a "Notification Service." It's not a capability; it's a feature of every capability.
- Don't write a "common models" gem.
- Don't do synchronous fan-out (Service A calls 5 services in series). Use events.
- Don't migrate everything at once. See `monolith-to-services-extraction`.
- Don't skip versioning. v1 of your service API is contract; breaking it breaks consumers.

## See also

- `when-NOT-to-use-microservices` — read this FIRST
- `monolith-to-services-extraction` — strangler fig pattern
- `event-driven-architecture` — domain events as glue
- `kafka-rails` / `rabbitmq-rails` — transport choices
- `distributed-tracing-rails` — observability across services
- `external-api-integration` — Faraday, circuit breakers, timeouts

## Sources

- [Domain-Driven Design — Eric Evans](https://www.dddcommunity.org/)
- [Building Microservices — Sam Newman, 2nd ed.](https://samnewman.io/books/building_microservices_2nd_edition/)
- [Microservices — Martin Fowler](https://martinfowler.com/articles/microservices.html)
- [Saga pattern — Microservices.io](https://microservices.io/patterns/data/saga.html)
- [Temporal](https://temporal.io/)
- [Conway's Law](https://www.melconway.com/Home/Conways_Law.html)
- [event-storming](https://www.eventstorming.com/) — boundary discovery technique
