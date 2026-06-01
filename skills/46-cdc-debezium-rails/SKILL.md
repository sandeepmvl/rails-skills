---
name: cdc-debezium-rails
description: Change Data Capture (CDC) from a Rails Postgres database via Debezium into Kafka topics — logical replication setup, wal_level=logical, REPLICA IDENTITY FULL, publication / replication slot, Debezium Connect config, transformations, snapshot mode, schema evolution, when CDC fits vs application-emitted events. Use when the user mentions Debezium, CDC, change data capture, logical replication, wal2json, pglogical, "stream DB changes to Kafka", or wants downstream systems (search index, data warehouse) updated from Rails DB writes.
---

# CDC with Debezium

> CDC publishes every row change in your Rails DB as a Kafka event. Downstream consumers (search index, data warehouse, audit log, downstream services) get them without your app emitting anything. Powerful and dangerous — every Rails write becomes a public contract.

## The opinion

> **Use Debezium with Postgres logical replication when you have multiple downstream consumers needing eventually-consistent DB state (search, warehouse, cache invalidation). Do NOT use CDC as your domain event bus — emit explicit domain events from the app layer for that. CDC leaks schema; domain events express intent. Set `REPLICA IDENTITY FULL` on tables you publish from. Use a single publication and replication slot per Debezium connector. Tombstone-handle deletes.**

## When CDC fits

| Use case | CDC fits? |
|---|---|
| Update search index when posts change | ✅ |
| Stream changes to a data warehouse | ✅ |
| Audit trail of every DB write | ✅ |
| Cache invalidation on row updates | ✅ |
| Sync to a downstream service's own DB | ⚠️ (couples on schema — use domain events) |
| Trigger business workflows | ❌ (semantic = "row changed", not "order placed") |
| Eventual consistency between microservices | ❌ (use domain events) |

The litmus test: would a column rename break downstream? If yes, you're using CDC for the wrong thing.

## Postgres setup

```sql
-- postgresql.conf
wal_level = logical
max_replication_slots = 4      -- one per Debezium connector
max_wal_senders = 4

-- Restart Postgres.
```

```sql
-- Create a publication for the tables you want to stream
CREATE PUBLICATION rails_app_pub FOR TABLE posts, users, orders;

-- Or all tables (broad)
-- CREATE PUBLICATION rails_app_pub FOR ALL TABLES;

-- Critical: enables UPDATE/DELETE events to include the previous row state
ALTER TABLE posts REPLICA IDENTITY FULL;
ALTER TABLE users REPLICA IDENTITY FULL;
ALTER TABLE orders REPLICA IDENTITY FULL;

-- Replication user with limited grants
CREATE ROLE debezium WITH REPLICATION LOGIN PASSWORD 'redacted';
GRANT CONNECT ON DATABASE rails_app TO debezium;
GRANT USAGE ON SCHEMA public TO debezium;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO debezium;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO debezium;
```

**`REPLICA IDENTITY FULL` cost:** WAL size grows because the full previous row is logged on UPDATE/DELETE. For high-write tables, evaluate cost. Alternative: `REPLICA IDENTITY USING INDEX my_unique_idx` — log only the indexed columns.

## Debezium connector

```json
{
  "name": "rails-app-postgres",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max": "1",
    "database.hostname": "postgres.internal",
    "database.port": "5432",
    "database.user": "debezium",
    "database.password": "${secrets.DEBEZIUM_PASSWORD}",
    "_comment_password": "Confluent Secret Protection syntax — on plain Kafka Connect or Strimzi, use env vars or an ExternalSecret.",
    "database.dbname": "rails_app",
    "plugin.name": "pgoutput",
    "publication.name": "rails_app_pub",
    "slot.name": "rails_app_slot",
    "topic.prefix": "rails_app",
    "table.include.list": "public.posts,public.users,public.orders",
    "snapshot.mode": "initial",
    "tombstones.on.delete": "true",
    "transforms": "unwrap",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "false"
  }
}
```

POST this to your Kafka Connect cluster (`/connectors`).

Each table becomes a topic: `rails_app.public.posts`, `rails_app.public.users`, etc.

## Event shape

After the `ExtractNewRecordState` transform, events look like the row itself, plus headers:

```json
{
  "id": 42,
  "account_id": 7,
  "title": "Hello world",
  "body": "...",
  "published_at": "2026-05-24T10:00:00Z",
  "__op": "u",
  "__source_ts_ms": 1716548400000
}
```

`__op` values:
- `c` — create (INSERT)
- `u` — update (UPDATE)
- `d` — delete (DELETE; payload is null + tombstone)
- `r` — read (snapshot)

## Consuming CDC in Rails

```ruby
class PostCdcConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      event = message.payload

      if event.nil?  # tombstone
        SearchIndex.delete("posts", message.key)
        next
      end

      case event[:__op]
      when "c", "u", "r"
        SearchIndex.upsert("posts", event[:id], serialize(event))
      when "d"
        SearchIndex.delete("posts", event[:id])
      end
    end
  end

  private

  def serialize(row)
    {
      id: row[:id],
      title: row[:title],
      body: row[:body],
      account_id: row[:account_id]
    }
  end
end
```

See `kafka-rails` for karafka setup.

## Pattern: Snapshot + streaming

`snapshot.mode: "initial"`:
1. On first start, Debezium does a SELECT * on each published table.
2. Then catches up via WAL.

This is how you backfill a new search index without writing a backfill job.

For large tables, `incremental snapshot` (Debezium 1.7+) does it in chunks without blocking writes.

## Pattern: Schema evolution

When you `ALTER TABLE posts ADD COLUMN summary`:

1. Debezium picks up the change automatically.
2. New events include `summary`.
3. Old events (already in topic) don't have it — consumers must handle absence.

**Rule:** never RENAME columns. Add new, deprecate old, drop later. See `safe-migrations`.

For Avro / Protobuf schemas in the registry, use BACKWARD compatibility — new schema can read old data.

## Pattern: Replication slot management

A replication slot retains WAL until consumed. If the connector dies and is not restarted, WAL accumulates:

```sql
SELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag
FROM pg_replication_slots
WHERE slot_name = 'rails_app_slot';
```

Alert if lag > 1GB. Either restart the connector or, if abandoned, drop the slot:

```sql
SELECT pg_drop_replication_slot('rails_app_slot');
```

**Critical:** drop only abandoned slots — dropping an active slot loses unconsumed changes.

## Pattern: Outbox + CDC (the both-worlds pattern)

For semantic events, write to an `outbox_events` table. CDC streams `outbox_events` to Kafka. Consumers see semantic events, not schema changes.

```ruby
class Order < ApplicationRecord
  after_create_commit :emit_event

  private

  def emit_event
    OutboxEvent.create!(
      aggregate_type: "Order",
      aggregate_id: id.to_s,
      event_type: "order.placed",
      payload: { order_id: id, account_id: account_id, total_cents: total_cents }
    )
  end
end
```

Debezium streams `outbox_events`. A Single Message Transform (SMT) routes events to the topic from `event_type`. Debezium has a built-in `EventRouter` SMT for exactly this:

```json
"transforms": "outbox",
"transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
"transforms.outbox.route.by.field": "aggregate_type"
```

Now downstream sees `Order.placed` semantics, decoupled from the actual orders-table schema.

## Common mistakes to refuse

- Don't use CDC as your domain event bus. It exposes schema.
- Don't skip `REPLICA IDENTITY FULL` on tables you publish UPDATE/DELETE events for. You'll get half-events.
- Don't share replication slots across connectors.
- Don't ignore replication-slot lag alerts. WAL accumulates and fills disk.
- Don't expose your DB-side replication user to a public network.
- Don't drop an active slot. You lose unconsumed changes.

## When NOT to use CDC

- The downstream needs domain semantics, not row changes — emit explicit events.
- You only have one consumer that could just call your API. CDC is overkill.
- Your DB is MySQL with binlog — same pattern; Debezium supports it, but check binlog setup separately.
- High-write tables where `REPLICA IDENTITY FULL` is unacceptable.

## See also

- `kafka-rails` — Debezium publishes to Kafka topics
- `event-driven-architecture` — the outbox + CDC pattern
- `safe-migrations` — never rename columns when CDC is downstream
- `multi-database-and-replicas` — different from CDC (multi-DB is for the app; CDC is for downstream)
- `data-warehouse-integration` — CDC → Snowflake / BigQuery

## Sources

- [Debezium docs](https://debezium.io/documentation/)
- [Postgres logical replication](https://www.postgresql.org/docs/current/logical-replication.html)
- [Debezium Outbox event router](https://debezium.io/documentation/reference/transformations/outbox-event-router.html)
- [Debezium Postgres connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Strimzi (Kafka Connect on K8s)](https://strimzi.io/)
- [Confluent Kafka Connect](https://docs.confluent.io/platform/current/connect/index.html)
