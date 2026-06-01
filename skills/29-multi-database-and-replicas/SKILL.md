---
name: multi-database-and-replicas
description: Multi-database Rails 8 — primary + replica for read scaling, separate databases per concern (auth DB, analytics DB), automatic role switching via connected_to + connects_to, replica lag detection, sticky writes (writes-followed-by-reads on primary), GHA-style horizontal sharding, the trilogy/pg per-connection-pool config. Use when the user mentions read replicas, replica lag, primary/replica, connected_to, connects_to, sharding, multi-database, role-switching, or asks how to scale reads.
---

# Multi-Database + Replicas

> Rails 6+ has first-class multi-database support. Use it to add a read replica before sharding, and to isolate concerns (analytics queries on a separate DB) before splitting services. AI agents often reach for sharding when a replica would do, or for two services when one DB with two connections would do.

## The opinion

> **Add a read replica first. Sharding is a v0.3 / scale-out problem. Use `connects_to` per ApplicationRecord-subtree (not per-action). Sticky writes are the default — a write followed by a read in the same request must hit primary (Rails handles via `ApplicationRecord.connected_to(role: :writing)` middleware). Monitor replica lag; route long-running reports to a read-only replica.**

## Core patterns

### Pattern 1: Primary + replica config

```yaml
# config/database.yml
production:
  primary:
    adapter: postgresql
    database: myapp_production
    host: <%= ENV["DB_PRIMARY_HOST"] %>
    username: <%= ENV["DB_USER"] %>
    password: <%= ENV["DB_PASSWORD"] %>

  primary_replica:
    adapter: postgresql
    database: myapp_production
    host: <%= ENV["DB_REPLICA_HOST"] %>
    username: <%= ENV["DB_USER"] %>
    password: <%= ENV["DB_PASSWORD"] %>
    replica: true
```

```ruby
# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  connects_to database: { writing: :primary, reading: :primary_replica }
end
```

```ruby
# config/application.rb — automatic role switching
config.active_record.database_selector = { delay: 2.seconds }
config.active_record.database_resolver = ActiveRecord::Middleware::DatabaseSelector::Resolver
config.active_record.database_resolver_context = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session
```

**What this gives you:**
- Reads default to the `reading` role → replica.
- Writes go to the `writing` role → primary.
- After a write, the session-cookie resolver tracks the last-write timestamp; subsequent requests within `delay` (here 2s) stay on primary regardless of HTTP verb. This prevents read-after-write inconsistencies caused by replication lag. The trigger is "wrote-recently", not "HTTP verb" — a GET shortly after a POST still hits primary.

### Pattern 2: Manual role switching

When you want a specific block on a specific role:

```ruby
ApplicationRecord.connected_to(role: :reading) do
  # Heavy report query
  Report.generate_monthly
end

# Force writing for a critical read:
ApplicationRecord.connected_to(role: :writing) do
  user = User.find(id)  # guaranteed to see latest writes
end
```

### Pattern 3: Separate databases per concern

```yaml
production:
  primary:
    database: myapp_production

  analytics:
    database: myapp_analytics_production
    host: <%= ENV["ANALYTICS_DB_HOST"] %>

  cache:
    database: myapp_cache_production  # Solid Cache lives here
```

```ruby
# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  connects_to database: { writing: :primary, reading: :primary_replica }
end

# app/models/analytics_record.rb
class AnalyticsRecord < ActiveRecord::Base
  self.abstract_class = true
  connects_to database: { writing: :analytics, reading: :analytics }
end

class EventLog < AnalyticsRecord
  # Stored in the analytics database
end
```

**When this helps:**
- Analytics workload doesn't compete with app primary.
- Cache writes (Solid Cache) don't bloat the app DB.
- Compliance / encryption needs differ (e.g. PII isolation).

### Pattern 4: Replica lag monitoring

```ruby
class ReplicaLagCheck
  def self.lag_seconds
    ActiveRecord::Base.connected_to(role: :reading) do
      ActiveRecord::Base.connection.exec_query(
        "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag"
      ).first["lag"].to_f
    end
  end
end

class HealthController < ApplicationController
  def show
    lag = ReplicaLagCheck.lag_seconds
    if lag > 30
      render json: { status: "degraded", replica_lag: lag }, status: :service_unavailable
    else
      render json: { status: "ok", replica_lag: lag }
    end
  end
end
```

Alert on lag > 5s. At 30s+, automatic failover or app-level routing of reads back to primary.

### Pattern 5: Long-running reports on a dedicated replica

For analytics queries that take seconds:

```yaml
production:
  primary: ...
  primary_replica: ...
  analytics_replica:
    adapter: postgresql
    database: myapp_production
    host: <%= ENV["DB_ANALYTICS_REPLICA_HOST"] %>
    replica: true
```

Register the analytics role with a dedicated abstract class:

```ruby
# app/models/analytics_record.rb
class AnalyticsRecord < ApplicationRecord
  self.abstract_class = true
  connects_to database: { reading: :analytics_replica }
end

class ReportGenerator
  def call
    AnalyticsRecord.connected_to(role: :reading) do
      User.complex_aggregation
    end
  end
end
```

The analytics replica can run far behind primary without affecting the user-facing read replica's freshness.

### Pattern 6: Horizontal sharding (Rails 6.1+)

```yaml
# config/database.yml
production:
  primary_shard_one:
    database: myapp_shard_one
  primary_shard_two:
    database: myapp_shard_two

# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  connects_to shards: {
    default: { writing: :primary_shard_one, reading: :primary_shard_one_replica },
    shard_two: { writing: :primary_shard_two, reading: :primary_shard_two_replica }
  }
end

# Use:
ApplicationRecord.connected_to(shard: :shard_two) do
  User.find_by(email: "x@y.com")
end
```

**Sharding is hard.** You need:
- A consistent shard key (e.g. `account_id`).
- A router that picks the right shard for every query.
- Cross-shard joins are forbidden — denormalize or use a higher-level fan-out.
- Schema migrations apply per shard.

Defer until a single replica + denormalization doesn't keep up. Most apps never need to shard.

### Pattern 7: Trilogy + connection pooling

```ruby
# Gemfile — Rails 8 ships Trilogy as the default MySQL adapter; no gem needed.
# For Rails 7.0/7.1, add explicitly:
# gem "trilogy"
```

Connection pooling at the app level via Rails' built-in pool (per-process). For Postgres-heavy apps, add PgBouncer in front of the DB:

- **Transaction pooling** (most common): app borrows a connection per transaction. Reduces idle connections from N×workers×threads to a small fixed number. Beware: prepared statements don't survive transaction boundaries.
- **Session pooling**: connection sticks to the app process. Less efficient but supports prepared statements.

```yaml
# config/database.yml (with PgBouncer in transaction mode)
production:
  primary:
    adapter: postgresql
    prepared_statements: false  # required for PgBouncer transaction pooling
    advisory_locks: false
```

## Common mistakes to refuse

- Don't shard before adding a replica.
- Don't add a replica without enabling automatic role switching (writes-then-reads bug).
- Don't `connected_to(role: :reading)` in a write path — silent data divergence.
- Don't ignore replica lag. Set an SLO.
- Don't enable transaction-mode PgBouncer without disabling prepared statements (`prepared_statements: false`).
- Don't put analytics queries on the same replica as user-facing reads — saturate one, slow the other.

## When NOT to use this skill

- The user is asking about a single DB with no replication — out of scope.
- The user is asking about CDC / Debezium — that's v0.3.

## See also

- `safe-migrations` — migrations on multi-DB
- `n-plus-one-killer` — replica is no fix for N+1
- Coming in v0.3: `cdc-debezium-rails` — replication beyond Rails

## Sources

- [Rails Guides — Multiple Databases](https://guides.rubyonrails.org/active_record_multiple_databases.html)
- [Rails 6.1 sharding notes](https://guides.rubyonrails.org/active_record_multiple_databases.html#horizontal-sharding)
- [GitHub — Vitess for MySQL sharding](https://vitess.io/)
- [Postgres logical replication](https://www.postgresql.org/docs/current/logical-replication.html)
- [PgBouncer](https://www.pgbouncer.org/)
- [Trilogy MySQL adapter](https://github.com/trilogy-libraries/trilogy)
