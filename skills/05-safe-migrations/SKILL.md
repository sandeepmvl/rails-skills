---
name: safe-migrations
description: Write zero-downtime database migrations for Ruby on Rails — strong_migrations rules, the add-column / set-default / backfill / enforce-NOT-NULL multi-deploy split, disable_ddl_transaction!, concurrent index creation on PostgreSQL, find_each batching, why change_column is dangerous, the deploy/migrate/deploy sequencing. Use when writing or reviewing Rails migrations, adding a column to a large table, removing or renaming columns, adding NOT NULL or foreign keys, adding indexes on big tables, when the user mentions strong_migrations, zero downtime, migration locks, deploy ordering, or asks how to backfill a column safely.
---

# Safe Migrations

> Every Rails developer ships a migration that locks the table for 90 seconds at some point. This skill prevents that. The rules are: never alter a column type, never change a column default on a large table in one step, never enforce NOT NULL on a backfill in the same migration, never index a 100M-row table without `CONCURRENTLY`. AI agents botch every one of these by default.

## Why this matters

A migration locks rows; an unsafe migration locks the whole table; a really unsafe migration locks the table for the duration of a `pg_dump`-sized table rewrite. Users see 502s. The fix isn't smarter Rails — it's *deploy ordering* and the `strong_migrations` gem.

## The opinion

> **Install strong_migrations on day one. Treat every schema change as a multi-deploy split: add → backfill → enforce → cleanup. Use `CONCURRENTLY` on Postgres for every index over ~10k rows. Backfill in batches of 1000 with throttling. Never trust `change_column` to be safe.**

Counter-position: tiny apps (< 100k rows on all tables) can ignore this and just run migrations. We acknowledge that — but installing strong_migrations on day one means the first time you cross a threshold, you get a helpful error instead of an outage.

## The mental model

A schema change is a contract between **the schema** and **the deployed code**. The code expects column `X` to exist (or not exist), to be NOT NULL (or nullable), to have a particular type. If the schema and the code disagree at any point during deploy, requests fail.

So every "big" schema change is at least two deploys:

1. **Deploy 1:** schema change that's backwards-compatible with the old code.
2. **Deploy 2:** code change that uses the new schema. Often followed by a third deploy to clean up the old column / constraint.

Strong_migrations enforces this by refusing the dangerous one-step migrations.

## Core patterns

### Pattern 1: Install strong_migrations

```ruby
# Gemfile
gem "strong_migrations"
```

```bash
bin/rails generate strong_migrations:install
```

```ruby
# config/initializers/strong_migrations.rb
StrongMigrations.start_after = 20260101_000000  # ignore migrations before this date

# Lock and statement timeouts — fail fast if a migration is going to block
StrongMigrations.lock_timeout = 10.seconds
StrongMigrations.statement_timeout = 1.hour

# Run ANALYZE after index creation so the planner picks up the new statistics
StrongMigrations.auto_analyze = true
```

Now every dangerous migration produces a helpful error with the recommended fix.

### Pattern 2: Adding a column to a large table

**Before** (AI default — locks the table on Rails < 5):

```ruby
# WRONG on Rails < 5 on PG; can rewrite the table.
class AddRoleToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :role, :string, default: "member", null: false
  end
end
```

**The problem (pre-Postgres 11 / pre-Rails 5):** setting a default on a new column on an existing table required rewriting every row. Locks the table for the duration. PG 11+ stores the default in `pg_attribute` instead — instant. Rails 5+ knows this on PG 11+.

**Safe pattern (pre-PG-11 or for any change_column_default on existing column):**

```ruby
# Migration 1 — add the column nullable, no default
class AddRoleToUsersV1 < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :role, :string  # nullable, no default
  end
end

# Deploy code that handles role being nil (uses "member" as fallback in app code)

# Migration 2 — change default; new rows get it
class AddRoleDefaultV2 < ActiveRecord::Migration[8.0]
  def change
    change_column_default :users, :role, "member"
  end
end

# Migration 3 — backfill existing nulls
class BackfillUserRoleV3 < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!  # so we can commit per batch

  def up
    User.unscoped.in_batches(of: 1000) do |relation|
      relation.where(role: nil).update_all(role: "member")
      sleep(0.01)  # throttle to avoid replica lag
    end
  end
end

# Migration 4 — enforce NOT NULL after backfill is complete
class EnforceUserRoleNotNullV4 < ActiveRecord::Migration[8.0]
  def change
    change_column_null :users, :role, false
  end
end
```

**PG 12+ caveat:** a bare `change_column_null` still takes an `ACCESS EXCLUSIVE` lock and rescans. Use the strong_migrations safe path: add a `CHECK (col IS NOT NULL) NOT VALID` constraint → `VALIDATE CONSTRAINT` → then `SET NOT NULL` (which is fast because the validated CHECK proves it). strong_migrations rewrites this automatically when you call `change_column_null` with `validate: false` first or use `add_check_constraint`.

**Why split:** the four-step version is non-blocking. The single-step version blocks writes for the table rewrite.

### Pattern 3: Removing a column

**Before** (AI default — breaks the app mid-deploy):

```ruby
class RemoveLegacyEmailFromUsers < ActiveRecord::Migration[8.0]
  def change
    remove_column :users, :legacy_email
  end
end
```

**The problem:** ActiveRecord caches columns at boot. The currently-running app servers still think `legacy_email` exists. They include it in SELECTs (`SELECT users.* FROM users`). The column is gone. Every request crashes.

**Safe pattern:**

```ruby
# Step 1 — tell Rails to ignore the column (deploy this first)
class User < ApplicationRecord
  self.ignored_columns = %w[legacy_email]
end

# Step 2 — deploy this code. App servers now ignore legacy_email.

# Step 3 — once all app servers are restarted, run the migration to drop the column.
class RemoveLegacyEmailFromUsers < ActiveRecord::Migration[8.0]
  def change
    safety_assured { remove_column :users, :legacy_email }
  end
end

# Step 4 — remove the ignored_columns line.
```

`safety_assured` is strong_migrations' explicit override — you're telling the tool you understand the risk because you've handled it.

### Pattern 4: Renaming a column

Never. Renaming a column is two deploys minimum:

```ruby
# Deploy 1
class AddNewEmailColumn < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :new_email, :string
  end
end

# Deploy 2 — app writes to BOTH old and new
class User < ApplicationRecord
  before_save :sync_email_to_new
  def sync_email_to_new
    self.new_email = email if email_changed?
  end
end

# Backfill — separate migration
class BackfillNewEmail < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  def up
    User.unscoped.in_batches(of: 1000) do |rel|
      rel.where(new_email: nil).update_all("new_email = email")
      sleep(0.01)
    end
  end
end

# Deploy 3 — app reads from new_email, writes to both
# Deploy 4 — app reads from new_email, writes only to new_email
# Deploy 5 — drop email column (per Pattern 3: ignored_columns first, then drop)
```

This is why "just rename it" requires a project plan, not a migration.

### Pattern 5: Adding an index — `algorithm: :concurrently` (Postgres)

**Before** (AI default — blocks writes on the table):

```ruby
class AddIndexToOrdersUserId < ActiveRecord::Migration[8.0]
  def change
    add_index :orders, :user_id
  end
end
```

**Safe pattern:**

```ruby
class AddIndexToOrdersUserId < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!  # required for CONCURRENTLY

  def change
    add_index :orders, :user_id, algorithm: :concurrently
  end
end
```

`disable_ddl_transaction!` is mandatory: `CREATE INDEX CONCURRENTLY` can't run inside a transaction (Postgres restriction). Strong_migrations will error if you forget.

**The "if not exists" idempotency:** for the (rare) re-run case:

```ruby
add_index :orders, :user_id, algorithm: :concurrently, if_not_exists: true
```

**MySQL note:** MySQL 5.6+ has online DDL but the syntax differs. strong_migrations gives MySQL-specific guidance.

### Pattern 6: Adding a foreign key on a large table

**Before** (locks both tables):

```ruby
add_foreign_key :orders, :users
```

**Safe pattern (two migrations):**

```ruby
# Migration 1 — add the FK with validate: false (doesn't scan existing rows)
class AddFkOrdersUsers < ActiveRecord::Migration[8.0]
  def change
    add_foreign_key :orders, :users, validate: false
  end
end

# Migration 2 — validate in a separate, less blocking step
class ValidateFkOrdersUsers < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :orders, :users
  end
end
```

`validate: false` means new rows are checked, existing rows aren't (yet). The validate step takes a SHARE UPDATE EXCLUSIVE lock — readers and writers continue.

### Pattern 7: Changing a column type

**Before** (whole-table rewrite, table locked):

```ruby
change_column :products, :price, :decimal, precision: 10, scale: 2
```

**Safe pattern (multi-deploy):**

```ruby
# Deploy 1 — add new column
add_column :products, :price_decimal, :decimal, precision: 10, scale: 2

# Deploy 2 — write to both
class Product < ApplicationRecord
  before_save { self.price_decimal = price if price_changed? }
end

# Backfill — separate migration in batches, set-based UPDATE per batch
class BackfillPriceDecimal < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  def up
    Product.unscoped.in_batches(of: 1000) do |rel|
      rel.where(price_decimal: nil).update_all("price_decimal = price")
      sleep(0.01)
    end
  end
end

# Deploy 3 — read from price_decimal, keep writing to both
# Deploy 4 — write only to price_decimal
# Deploy 5 — drop price column (ignored_columns first)
# Deploy 6 — rename price_decimal to price
```

Six deploys for a "simple" type change. This is why type changes get pushed off until they actually matter.

### Pattern 8: Backfill in batches with throttling

```ruby
class BackfillOrderStatus < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    Order.unscoped.in_batches(of: 1000) do |relation|
      relation.where(status: nil).update_all(status: "pending")

      # Throttle: pause briefly so replicas can catch up
      sleep(0.01) unless Rails.env.test?
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

**Why `in_batches`:**
- Memory stays flat (1k rows per batch, not the whole table).
- Each batch is its own transaction — if the migration fails mid-way, the previous batches are already committed and the next run picks up where it left off.
- `unscoped` bypasses `default_scope` if the model has one — never trust the app's scoping in a migration.

**Why `disable_ddl_transaction!`:** if you wrapped the backfill in a single transaction, an interruption rolls back everything. Per-batch commits let you resume.

**Why throttle:** large backfills generate replication lag. A 1ms sleep per batch is invisible to the running app but keeps replicas current.

### Pattern 9: When the AI says "let's just truncate and refill"

```ruby
# WRONG
execute "TRUNCATE orders"
Order.create!(legacy_data.map { |d| ... })
```

Never truncate production data in a migration. If a backfill genuinely requires a destructive step, do it as a manual rake task with safety prompts, not an automatically-run migration.

### Pattern 10: Migration anti-patterns

| Anti-pattern | Why bad | Fix |
|---|---|---|
| `Order.update_all(...)` in migration | Loads the model class — model in 6 months can have schema knowledge that disagrees with this point in history (e.g. column removed, validation added on relevant action) | Use raw `execute "UPDATE orders SET..."` or a throwaway anonymous model `Class.new(ActiveRecord::Base) { self.table_name = 'orders' }.in_batches.update_all` |
| `Order.all.each { … }` in migration | Loads whole table; OOMs on big tables | `in_batches` |
| Migration that calls a service object | Service depends on model state that may change | Inline the SQL or rake task |
| `def up` and `def down` with the same logic | Duplicate code | Use `def change` for reversible operations |
| Schema change + data backfill in one migration | Locks table during backfill | Split into two migrations |
| Adding a column with `null: false, default: …` on a Rails < 5 app | Whole-table rewrite | Multi-step (see Pattern 2) |
| `change_column` to widen a column | Often safe; sometimes a rewrite | Check strong_migrations output |

## Decision matrix

| Operation | Safe directly? | If not, split into… |
|---|---|---|
| `add_column` nullable, no default (PG 11+) | Yes | — |
| `add_column` with default on PG 11+, Rails 5+ | Yes | — |
| `add_column null: false, default: …` on older | No | nullable → default → backfill → NOT NULL |
| `remove_column` | No | `ignored_columns` → deploy → remove |
| `rename_column` | No | new col → dual-write → backfill → dual-read → switch → drop |
| `change_column` (type or length) | Sometimes | Often: new col → dual-write → backfill → switch → drop |
| `add_index` (large table, Postgres) | No | `algorithm: :concurrently` + `disable_ddl_transaction!` |
| `add_foreign_key` (large table) | No | `validate: false` → `validate_foreign_key` |
| `change_column_null :col, false` | If backfilled first | backfill → then change |
| `change_column_default` (PG 11+) | Yes | — |

## Common mistakes to refuse

- Don't add a column with `null: false, default: …` on a large table — split it.
- Don't drop a column without `ignored_columns` first.
- Don't rename a column. Add new, dual-write, switch, drop old.
- Don't `add_index` on a big Postgres table without `algorithm: :concurrently`.
- Don't add a foreign key on a big table without `validate: false`.
- Don't backfill in a single transaction — use `in_batches`.
- Don't iterate the entire table with `find_each` and a model that has callbacks; use raw `update_all` per batch.
- Don't `safety_assured` away the strong_migrations error without doing the thing the error told you to do.

## When NOT to use this skill

- Schema change on a small table (< 10k rows) where downtime is acceptable. Skip the multi-step dance, but install strong_migrations anyway so the gate is in place when the table grows.
- Pure development scaffolding migrations — `rails g model` and run.

## See also

- `activerecord-patterns` — for what the code-side changes look like
- `n-plus-one-killer` — `references/query-explained.md` for index planning
- Coming in v0.2: `multi-database-and-replicas` — replica lag during backfills
- Coming in v0.3: `cdc-debezium-rails` — when migrations need to propagate to a CDC stream

## Reference files

For deeper guidance:

- [`references/zero-downtime-playbook.md`](references/zero-downtime-playbook.md) — full deploy / migrate / deploy sequencing per operation, with copy-pasteable migration templates

## Sources

- [strong_migrations README](https://github.com/ankane/strong_migrations) — the canonical safe-migration rules
- [Rails Guides — Active Record Migrations](https://guides.rubyonrails.org/active_record_migrations.html)
- [Postgres docs — CREATE INDEX CONCURRENTLY](https://www.postgresql.org/docs/current/sql-createindex.html)
- [Postgres docs — Locking](https://www.postgresql.org/docs/current/explicit-locking.html)
- [GitLab engineering — Migration style guide](https://docs.gitlab.com/ee/development/migration_style_guide.html) — battle-tested at 100M+ rows
- [Andrew Kane — Safer Migrations](https://ankane.org/safer-migrations) — the rationale behind strong_migrations
- [Shopify — Online migrations](https://shopify.engineering/) — case studies of zero-downtime migrations at scale
- [Stripe — Online Schema Changes](https://stripe.com/blog/online-migrations) — production playbook
