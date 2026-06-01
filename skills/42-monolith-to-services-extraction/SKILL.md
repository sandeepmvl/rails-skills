---
name: monolith-to-services-extraction
description: Incrementally extracting a service from a Rails monolith — the strangler fig pattern, dark-launching, dual-writes with reconciliation, the cutover, the rollback plan, schema-level decoupling before code-level decoupling. Use after the user has decided to extract (see when-NOT-to-use-microservices) and needs to plan or execute the extraction. Use when the user mentions strangler fig, parallel run, dual-write, shadow read, extracting a service, splitting the monolith, cutover plan, or "we want to pull X out of the app."
---

# Monolith → Services Extraction

> "Rewrite as services" never works. "Extract one service incrementally over 3-6 months" sometimes does. This skill walks the strangler fig pattern that keeps the monolith working while the new service grows.

## The opinion

> **Use the strangler fig pattern. Do schema-level decoupling FIRST (separate tables / DB). Dark-launch the new service (production traffic, results discarded). Then dual-write (both systems write, old is source of truth). Then dual-read (both serve, compare). Finally, cut over. Keep the rollback path open until you've gone a full month without rolling back.**

The whole point: at no time should production be broken. Every step is reversible until the very last cleanup.

## The 7-stage strangler fig

```
1. Identify the seam
2. Decouple at the schema layer (in the monolith)
3. Stand up the new service (parallel infrastructure)
4. Dark-launch (shadow traffic)
5. Dual-write
6. Dual-read with diff
7. Cut over
8. Cleanup (remove old code)
```

You can spend weeks on each. That's fine.

### Stage 1: Identify the seam

The seam is the place where the monolith TALKS to the future-service.

```ruby
# Current monolith
class OrderController < ApplicationController
  def create
    order = Order.new(order_params)
    InventoryReserver.new(order).reserve!     # ← this will become a service call
    order.save!
    BillingProcessor.new(order).charge!       # ← this too
    render json: order
  end
end
```

You're going to extract Inventory and Billing. The seams are `InventoryReserver` and `BillingProcessor`. Make sure they have well-defined interfaces (a `call` method, an explicit success/failure result) before going further.

### Stage 2: Schema-level decoupling

Before code is in two places, the DATA must be cleanly owned by one place.

```ruby
# Before — inventory data scattered:
class Product < ApplicationRecord
  has_one :stock_level
end

class Order < ApplicationRecord
  has_many :inventory_reservations  # in same DB, with FKs
end
```

```ruby
# After (still in the monolith) — distinct schema namespace:
# Move inventory tables into a separate schema (Postgres) or separate logical DB.
# Drop cross-schema FKs in favor of application-level integrity.

class InventoryRecord < ApplicationRecord
  self.abstract_class = true
  connects_to database: { writing: :inventory_db, reading: :inventory_db_replica }
end

class StockLevel < InventoryRecord; end
class InventoryReservation < InventoryRecord; end
```

You're now using the multi-DB pattern from `multi-database-and-replicas`. The monolith reads from two databases. If this step breaks, you find out NOW, not after extraction.

**Why this step matters:** most "we extracted it in 6 months" stories elide that the painful 3 months were spent untangling foreign keys.

### Stage 3: Stand up the new service

Empty Rails 8 app, its own repo, its own CI, its own DB.

```bash
rails new inventory-service --api --database=postgresql --skip-action-cable --skip-action-mailer
```

Models = same schema. Endpoints = the operations the monolith currently performs in-process. Same database connection string as the monolith's `inventory_db` (initially — they share the DB at this point).

Deploy. Smoke-test endpoints in isolation. Don't connect to the monolith yet.

### Stage 4: Dark-launch (shadow traffic)

The monolith continues to do the work IN-PROCESS. After completing its work, it ALSO sends the operation to the new service. The new service's response is logged and compared, but NOT used.

```ruby
class InventoryReserver
  def reserve!
    result = perform_legacy   # in-process, source of truth

    # Shadow call — failures don't affect the user
    DarkLaunch.shadow("inventory.reserve", legacy_result: result) do
      InventoryServiceClient.reserve(order_id: @order.id, sku: @order.sku, qty: @order.qty)
    end

    result
  end
end

class DarkLaunch
  def self.shadow(operation, legacy_result:, &block)
    Thread.new do
      shadow_result = yield
      Rails.logger.info(
        operation: operation,
        match: results_match?(legacy_result, shadow_result),
        legacy: legacy_result.summary,
        shadow: shadow_result.summary
      )
    rescue => e
      Rails.error.report(e, context: { operation: operation, phase: "shadow" })
    end
  end
end
```

**Watch:**
- Latency of shadow calls (should be low — same DB).
- Mismatch rate. Investigate every diff.
- Error rate from the new service. Aim for 0%.

Let it run a week. Fix every mismatch.

### Stage 5: Dual-write (still legacy as source of truth)

Now both systems WRITE. Legacy is still authoritative. Reads still go to legacy.

```ruby
def reserve!
  ActiveRecord::Base.transaction do
    legacy_result = perform_legacy
    service_result = InventoryServiceClient.reserve(...)

    unless results_match?(legacy_result, service_result)
      raise InventoryMismatch, "legacy=#{legacy_result} service=#{service_result}"
    end

    legacy_result
  end
end
```

Now if the new service is wrong, your transaction rolls back. The new service is forced to be correct.

Run for 2-4 weeks. Reconcile any drift via a nightly job that compares `inventory_legacy.*` vs the new service's state.

### Stage 6: Dual-read with diff

Switch reads — the new service is now the source of truth. Legacy still serves as a fallback.

```ruby
def stock_for(sku)
  service_result = InventoryServiceClient.stock(sku: sku)
  legacy_result  = StockLevel.find_by(sku: sku)&.quantity

  if service_result != legacy_result
    Rails.error.report(
      InventoryDrift.new("stock_for #{sku}: service=#{service_result} legacy=#{legacy_result}")
    )
  end

  service_result  # authoritative
end
```

Watch the drift metric trend toward 0. If it doesn't, you have a bug — don't proceed.

### Stage 7: Cut over

Remove the legacy writes and reads. The new service is the only source.

```ruby
def reserve!
  InventoryServiceClient.reserve(order_id: @order.id, sku: @order.sku, qty: @order.qty)
end
```

Gate behind a feature flag:

```ruby
def reserve!
  if Flipper.enabled?(:inventory_service_only)
    InventoryServiceClient.reserve(...)
  else
    perform_legacy  # in-process
  end
end
```

Ramp the flag 1% → 10% → 100%. Keep the legacy code path for at least a month after 100%.

### Stage 8: Cleanup

After 30+ days at 100% with no rollbacks:

- Delete `perform_legacy` and the `InventoryReserver` in-process logic.
- Remove the legacy database tables (after backups).
- Remove the dual-write reconciliation jobs.
- Update CLAUDE.md / README to reflect ownership.

The flag stays for 90 days, then deleted.

## Rollback path

At every stage, you must be able to revert:

| Stage | Rollback |
|---|---|
| 1. Identify seam | (no code change) |
| 2. Schema decouple | Revert migration (still in the monolith). |
| 3. Stand up service | Decommission instance. |
| 4. Dark-launch | Disable shadow flag. |
| 5. Dual-write | Disable dual-write flag — legacy is still source. |
| 6. Dual-read | Flip read source back to legacy. |
| 7. Cut over | Flip the feature flag back. |
| 8. Cleanup | Restore deleted code from git. |

Never delete the legacy path until you're at stage 8 and confidence is unshakeable.

## The "data sync" trap

You'll be tempted to write a one-off script that "syncs" the legacy DB to the new service. Don't:

- Sync scripts have bugs. The bugs leave the systems out of sync.
- A "sync" script implies an asymmetric truth. Pick ONE source of truth and force the other to follow.
- Dual-write with diff-on-mismatch is your sync — and it catches divergence in production, immediately.

## Common mistakes to refuse

- Don't rewrite the monolith into services in a separate branch. The branch will go stale. The product will move on. You'll abandon the rewrite.
- Don't skip the dark-launch stage. You don't know what you don't know about production traffic.
- Don't cut over without dual-write running for at least 2 weeks.
- Don't delete the legacy code until 30+ days post-cutover with zero rollbacks.
- Don't extract more than one service at a time. Each extraction is its own 3-6 month effort.

## See also

- `when-NOT-to-use-microservices` — read first
- `microservices-decomposition` — bounded contexts, service contracts
- `multi-database-and-replicas` — schema-level decoupling first
- `feature-flagging` — gating the cutover
- `event-driven-architecture` — async glue between monolith and new service

## Sources

- [StranglerFigApplication — Martin Fowler](https://martinfowler.com/bliki/StranglerFigApplication.html)
- [How Shopify decoupled their monolith — Shopify Engineering](https://shopify.engineering/)
- [The Strangler Fig — Sam Newman](https://samnewman.io/blog/2020/12/01/strangler-fig/)
- [Scientist gem (used by GitHub for dual-runs)](https://github.com/github/scientist)
- [Branch by abstraction — Trunk Based Development](https://trunkbaseddevelopment.com/branch-by-abstraction/)
