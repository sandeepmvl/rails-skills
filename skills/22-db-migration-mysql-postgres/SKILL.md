---
name: db-migration-mysql-postgres
description: Migrate a Ruby on Rails application's primary database from MySQL to PostgreSQL — schema upgrades (JSON to JSONB for queryability, ENUMs to native types or check constraints, TINYINT to BOOLEAN, case-sensitivity changes), data export/import via pgloader, the dual-write cutover pattern, the gem switch (mysql2/trilogy to pg), Rails-side caveats. Use when migrating from MySQL to Postgres, the user mentions pgloader, JSONB upgrade, ENUM migration, TINYINT to BOOLEAN, or asks how to move a Rails app to Postgres.
---

# MySQL → Postgres Migration

> Going from MySQL to Postgres is mostly an upgrade. You gain JSONB with rich operators, partial indexes, true booleans, ARRAY columns, generated columns since 12, and rich CHECK constraints. Plan for the data conversion carefully — `pgloader` handles most of it.

## The opinion

> **`pgloader` for bulk migration. Dual-write cutover for zero-downtime. Plan for the schema upgrades — don't just translate, take advantage of Postgres features (JSONB instead of JSON, BOOLEAN instead of TINYINT, partial indexes, generated columns).**

## Pre-migration: what improves

| MySQL | Postgres | Why it matters |
|---|---|---|
| `JSON` | `JSONB` | Indexed queries via GIN; `@>` containment |
| `TINYINT(1)` for booleans | `BOOLEAN` | Type-safe; no 0/1 ambiguity |
| `ENUM` | Native enum OR `CHECK` constraint + ActiveRecord enum | Rename without table lock |
| No partial indexes | Partial indexes | Index only relevant rows; smaller, faster |
| No `ARRAY` columns | `ARRAY` columns | Native array storage for simple cases |
| LIKE case-insensitive | LIKE case-sensitive (use `ILIKE`) | Match-semantics change |
| No deferrable FK | Deferrable FK | Bulk-load patterns easier |
| Generated columns (5.7+) | Generated columns (12+) | Both have them; syntax slightly different |

## Core patterns

### Pattern 1: pgloader migration

```bash
brew install pgloader

cat > migrate.load <<EOF
LOAD DATABASE
  FROM mysql://user:pass@source-host/myapp_production
  INTO postgresql://user:pass@target-host/myapp_production

WITH include drop, create tables, create indexes, reset sequences,
     workers = 8, concurrency = 1, multiple readers per thread

SET PostgreSQL PARAMETERS
     maintenance_work_mem to '512MB',
     work_mem to '32MB'

CAST type tinyint when (= precision 1) to boolean drop typemod,
     type datetime to timestamptz drop default drop not null using zero-dates-to-null
;
EOF

pgloader migrate.load
```

Key casts:
- `tinyint(1) → boolean` — Rails treats 0/1 TINYINT as bool but the schema is more explicit as BOOLEAN.
- `datetime → timestamptz` — Postgres has true timezone support; bring data forward as UTC.
- `zero-dates-to-null` — MySQL allows `0000-00-00`; Postgres doesn't.

### Pattern 2: Dual-write cutover

Same shape as Postgres → MySQL (see `db-migration-postgres-mysql` Pattern 2): set up secondary, dual-write, verify, swap primary, decommission.

### Pattern 3: Gem swap

```ruby
# Gemfile — before
gem "mysql2"  # or "trilogy"

# After
gem "pg"
```

```yaml
# config/database.yml
production:
  adapter: postgresql
  encoding: unicode
  database: myapp_production
  username: ...
  password: ...
  host: ...
  prepared_statements: false  # if pgbouncer in transaction-pooling mode
```

### Pattern 4: Schema upgrades — take advantage of Postgres

**JSON → JSONB:**

```ruby
# Migration after the bulk move
class ConvertMetadataToJsonb < ActiveRecord::Migration[8.0]
  def change
    change_column :users, :metadata, :jsonb, using: "metadata::jsonb"
    add_index :users, :metadata, using: :gin
  end
end

# Now you can query:
User.where("metadata @> ?", { tier: "pro" }.to_json)
User.where("metadata ? :key", key: "tier")
```

**TINYINT → BOOLEAN:**

pgloader handles the cast. Rails models that used TINYINT for booleans (`is_active` integer 0/1) now use true booleans — verify any code that compared `is_active == 1`.

**MySQL ENUM → Rails ActiveRecord enum + CHECK constraint:**

```ruby
# MySQL had: ENUM('draft', 'published', 'archived')
# Postgres post-migration:
class Post < ApplicationRecord
  enum :status, { draft: 0, published: 1, archived: 2 }
end

# Migration to add the constraint
class AddStatusCheckConstraint < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :posts, "status IN (0, 1, 2)", name: "posts_status_check"
  end
end
```

**Case sensitivity:**

```yaml
# MySQL: where("email LIKE ?", "%FOO%") matched "foo@example.com"
# Postgres: same query is case-sensitive — won't match.
# Use ILIKE:
User.where("email ILIKE ?", "%FOO%")
```

Audit every LIKE query. Some teams add a `WHERE LOWER(email) LIKE LOWER(?)` index for safety.

### Pattern 5: Sequence reset

```bash
# After pgloader migration, the sequences may not match the max(id) in each table.
# Reset:
psql myapp_production -c "
  DO \$\$ DECLARE r RECORD;
  BEGIN
    FOR r IN SELECT n.nspname, c.relname FROM pg_class c
             JOIN pg_namespace n ON c.relnamespace = n.oid
             WHERE c.relkind = 'S'
    LOOP
      EXECUTE 'SELECT setval(''' || r.nspname || '.' || r.relname || ''', (SELECT MAX(id) FROM ' || replace(r.relname, '_id_seq', '') || '))';
    END LOOP;
  END \$\$;
"
```

Without this, the first INSERT can hit "duplicate key" errors.

## Common mistakes to refuse

- Don't run `pgloader` against production while writes continue.
- Don't skip the LIKE → ILIKE audit. Subtle data leak.
- Don't migrate ENUM as a string column — use Rails enum + check constraint.
- Don't skip the sequence reset post-migration.
- Don't swap `mysql2` → `pg` in the same PR as schema changes.

## See also

- `db-migration-postgres-mysql` — the reverse direction
- `safe-migrations` — schema changes during cutover
- `postgres-patterns` (skill in installed library; non-rails-specific) — Postgres ergonomics

## Sources

- [pgloader docs](https://pgloader.readthedocs.io/)
- [Postgres JSONB docs](https://www.postgresql.org/docs/current/datatype-json.html)
- [Postgres array docs](https://www.postgresql.org/docs/current/arrays.html)
- [Rails Guide — Multiple Databases](https://guides.rubyonrails.org/active_record_multiple_databases.html)
- [pg gem](https://github.com/ged/ruby-pg)
- [GitHub — moving from MySQL to Postgres](https://github.blog/) — case study
