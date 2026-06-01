---
name: db-migration-postgres-mysql
description: Migrate a Ruby on Rails application's primary database from PostgreSQL to MySQL — schema differences (JSONB to JSON, ARRAY columns, partial indexes, CHECK constraints, sequences), data export/import via pg_dump and mysqlimport or pgloader, the dual-write cutover pattern, the gem switch (pg to mysql2 or trilogy), Rails-side caveats. Use when migrating a Rails app from Postgres to MySQL, the user mentions pgloader, mysql2, trilogy, schema conversion, JSONB to JSON, ARRAY columns, partial indexes, or asks how to move a Rails app off Postgres.
---

# Postgres → MySQL Migration

> Going from Postgres to MySQL is a downgrade in feature set. Plan for what you'll lose (JSONB-style operators, array columns, partial indexes, rich `CHECK` constraints, generated columns until 8.0, true sequences) and design around it.

## The opinion

> **Don't do this unless forced. Postgres is the Rails-community default for good reason. If forced (vendor mandate, hosting choice, cost), use `pgloader` for the bulk migration, dual-write during cutover, and audit every column-type-specific feature in the schema before flipping.**

Counter-position: MySQL 8.0+ has closed many gaps (JSON functions, generated columns, CHECK constraints enforced). For simple Rails schemas, the migration is straightforward. The complexity is per-feature.

## Pre-migration audit

```bash
# Catalog every Postgres-specific feature in your schema
grep -E "jsonb|ARRAY|generated as identity|::regclass|@>|<@|tsvector" db/structure.sql
```

| Feature | Postgres | MySQL 8 equivalent | Migration impact |
|---|---|---|---|
| `JSONB` | Yes — indexed, queryable | `JSON` (no GIN indexes) | Lose `@>` containment operator; queries via `JSON_CONTAINS` |
| `ARRAY` columns (`integer[]`) | Yes | None | Move to a join table or serialized text |
| Partial indexes (`WHERE x IS NULL`) | Yes | No (use generated columns + index) | Per-index migration |
| `CHECK` constraints | Yes, enforced | 8.0.16+ enforced | Verify MySQL version |
| `tsvector` / full-text | Yes | MySQL has its own; different API | Rewrite full-text queries |
| `UUID` type | Yes (`uuid`) | `CHAR(36)` or `BINARY(16)` | App-side normalization |
| Sequences | Yes | AUTO_INCREMENT only | Single-PK sequences fine; named/multi-table sequences need redesign |
| Case sensitivity (LIKE) | Case-sensitive | Case-insensitive by default | Migrate to `LIKE BINARY` for strict; or accept the change |

## Core patterns

### Pattern 1: Schema conversion via `pgloader`

```bash
# Install pgloader
brew install pgloader

# Migration script
cat > migrate.load <<EOF
LOAD DATABASE
  FROM postgresql://user:pass@source-host/myapp_production
  INTO mysql://user:pass@target-host/myapp_production

WITH include drop, create tables, create indexes, reset sequences,
     workers = 8, concurrency = 1

SET MySQL PARAMETERS
     net_buffer_length to '16M',
     max_allowed_packet to '128M'

CAST type jsonb to json,
     type uuid to varchar(36)
;
EOF

pgloader migrate.load
```

pgloader does schema + data in one shot. For >100GB databases, it's slow; use it for a staging-cycle proof and then orchestrate with vendor tools at scale.

### Pattern 2: Dual-write cutover

For zero-downtime migration:

1. **Set up MySQL as a secondary database in Rails:**

```yaml
# config/database.yml
production:
  primary:
    adapter: postgresql
    database: myapp_production
  secondary:
    adapter: mysql2
    database: myapp_production_mysql

# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  connects_to database: { writing: :primary, reading: :primary }
end
```

2. **Dual-write phase:**

```ruby
class User < ApplicationRecord
  after_save :replicate_to_mysql

  def replicate_to_mysql
    ApplicationRecord.connected_to(database: :secondary) do
      Mysql::User.find_or_initialize_by(id: id).update!(attributes.except("id"))
    end
  rescue => e
    Rails.error.report(e, context: { user_id: id, action: "dual_write" })
  end
end
```

3. **Backfill:**

```bash
# pgloader for the historical bulk
pgloader migrate.load
```

4. **Verify:**

```ruby
User.unscoped.in_batches(of: 1000) do |rel|
  rel.each do |pg_user|
    mysql_user = ApplicationRecord.connected_to(database: :secondary) do
      Mysql::User.find_by(id: pg_user.id)
    end
    raise "Mismatch on #{pg_user.id}" if mysql_user.nil? || mysql_user.attributes != pg_user.attributes
  end
end
```

5. **Cutover:** swap primary in `database.yml`, deploy, monitor.

6. **Cleanup:** remove dual-write code, retire Postgres.

### Pattern 3: Gem swap

```ruby
# Gemfile — before
gem "pg"

# After — Rails 8.0 (Trilogy is the default for `rails new`, ships with Rails)
# Existing apps still need to add the gem.
gem "trilogy"
# OR (older Rails, or you prefer libmysqlclient)
# gem "mysql2"
```

```yaml
# config/database.yml — Rails 7.x with mysql2
production:
  adapter: mysql2
  ...

# config/database.yml — Rails 8.0 with Trilogy
production:
  adapter: trilogy
  username: ...
  password: ...
  host: ...
  database: myapp_production
  encoding: utf8mb4
  collation: utf8mb4_unicode_ci
```

**Trilogy notes:**
- C extension (small native build), but does NOT depend on `libmysqlclient` — ships its own embedded client. Much simpler Docker builds.
- Default MySQL adapter in Rails 8.0 (`rails new --database=trilogy`).
- For Rails 7.x: add `gem "trilogy"` manually and set `adapter: trilogy`.
- Slightly different connection parameter names; check the trilogy README.

### Pattern 4: Postgres-specific feature rewrites

**JSONB → JSON:**

```ruby
# Postgres
User.where("metadata @> ?", { tier: "pro" }.to_json)

# MySQL 8+
User.where("JSON_CONTAINS(metadata, ?)", { tier: "pro" }.to_json)
```

**Array columns:**

```ruby
# Postgres
class Post < ApplicationRecord
  # tag_ids stored as integer[]
end

# MySQL — move to a join table
class Post < ApplicationRecord
  has_many :post_tags
  has_many :tags, through: :post_tags
end
```

**Partial indexes:**

```ruby
# Postgres
add_index :users, :email, unique: true, where: "deleted_at IS NULL"

# MySQL — use a generated column
execute <<~SQL
  ALTER TABLE users
    ADD COLUMN email_active VARCHAR(255) GENERATED ALWAYS AS (IF(deleted_at IS NULL, email, NULL)) VIRTUAL,
    ADD UNIQUE INDEX idx_users_active_email (email_active);
SQL
```

## Common mistakes to refuse

- Don't run `pgloader` against production while writes continue — data drift.
- Don't swap `pg` to `mysql2` in the same PR as schema changes.
- Don't skip the schema audit. Postgres-specific features fail silently in queries (MySQL returns wrong results, not errors).
- Don't normalize UUIDs differently in app code than schema — round-trip bugs.

## When NOT to use this skill

- The user is moving Postgres → Postgres (different host) — that's a connection-change, not a migration.
- The user is adding a MySQL read replica — that's `multi-database-and-replicas`.

## See also

- `db-migration-mysql-postgres` — the reverse direction
- `safe-migrations` — schema changes during cutover
- Coming in v0.2: `multi-database-and-replicas`

## Sources

- [pgloader docs](https://pgloader.readthedocs.io/)
- [MySQL 8 JSON functions](https://dev.mysql.com/doc/refman/8.0/en/json-functions.html)
- [trilogy gem](https://github.com/trilogy-libraries/trilogy)
- [Rails multiple databases](https://guides.rubyonrails.org/active_record_multiple_databases.html)
- [Shopify — Migrating to Trilogy](https://shopify.engineering/)
