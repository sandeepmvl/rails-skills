# Zero-Downtime Migration Playbook

> Full deploy / migrate / deploy sequences for every common operation. Copy-pasteable templates. Read top-down.

## TOC

- [Add a column](#add-a-column) (with and without default)
- [Remove a column](#remove-a-column)
- [Rename a column](#rename-a-column)
- [Change column type](#change-column-type)
- [Enforce NOT NULL](#enforce-not-null-on-an-existing-column)
- [Add an index](#add-an-index)
- [Add a foreign key](#add-a-foreign-key)
- [Add a unique constraint](#add-a-unique-constraint)
- [Drop a table](#drop-a-table)
- [Rename a table](#rename-a-table)
- [Add a check constraint](#add-a-check-constraint)
- [General principles](#general-principles)

---

## Add a column

### Case A — nullable, no default (always safe)

```ruby
class AddBioToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :bio, :text
  end
end
```

Deploy once. Done.

### Case B — with default, Postgres 11+ / Rails 5+

```ruby
class AddRoleToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :role, :string, default: "member", null: false
  end
end
```

Safe on PG 11+: the default is stored in the catalog, not back-written into every row.

### Case C — with default, older Postgres or MySQL

Multi-deploy split:

```ruby
# Migration 1
add_column :users, :role, :string

# Deploy 1

# Migration 2
change_column_default :users, :role, "member"

# Migration 3 (separate file; disable_ddl_transaction! for batching)
class BackfillUserRole < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  def up
    User.unscoped.in_batches(of: 1000) do |rel|
      rel.where(role: nil).update_all(role: "member")
      sleep(0.01)
    end
  end
end

# Migration 4
change_column_null :users, :role, false
```

---

## Remove a column

```ruby
# Step 1 — code change
class User < ApplicationRecord
  self.ignored_columns = %w[legacy_email]
end
```

Deploy. Wait until every app server is restarted (rolling deploys; ensure no app server still has the old code).

```ruby
# Step 2 — migration
class RemoveLegacyEmailFromUsers < ActiveRecord::Migration[8.0]
  def change
    safety_assured { remove_column :users, :legacy_email }
  end
end
```

Deploy.

```ruby
# Step 3 — clean up
# Remove the ignored_columns line.
```

Deploy.

---

## Rename a column

There is no safe one-step rename. Treat as: add new column, dual-write, backfill, switch reads, drop old.

```ruby
# Migration 1
add_column :users, :handle, :string  # was `username`

# Deploy 1 — app dual-writes
class User < ApplicationRecord
  before_save { self.handle = username if username_changed? && handle.blank? }
end

# Migration 2 — backfill
class BackfillHandle < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  def up
    User.unscoped.in_batches(of: 1000) do |rel|
      rel.where(handle: nil).update_all("handle = username")
      sleep(0.01)
    end
  end
end

# Deploy 2 — app reads from handle, writes both
# Deploy 3 — app writes only handle (remove the before_save)
# Deploy 4 — remove username (per "Remove a column" pattern)
```

---

## Change column type

The dual-column dance:

```ruby
# Migration 1
add_column :products, :price_decimal, :decimal, precision: 10, scale: 2

# Deploy 1 — dual-write
class Product < ApplicationRecord
  before_save { self.price_decimal = price if price_changed? }
end

# Migration 2 — backfill, set-based UPDATE per batch
class BackfillPriceDecimal < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  def up
    Product.unscoped.in_batches(of: 1000) do |rel|
      rel.where(price_decimal: nil).update_all("price_decimal = price")
      sleep(0.01)
    end
  end
end

# Deploy 2 — read from new
# Deploy 3 — write only new
# Deploy 4 — drop old (per "Remove a column")
# Deploy 5 — rename new to old (per "Rename a column" — yes, another two-deploy dance)
```

Or just live with `price_decimal` as the canonical name. Often the right call.

---

## Enforce NOT NULL on an existing column

Backfill, then change:

```ruby
# Migration 1 — backfill any nulls
class BackfillUserStatus < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  def up
    User.unscoped.in_batches(of: 1000) do |rel|
      rel.where(status: nil).update_all(status: "active")
      sleep(0.01)
    end
  end
end

# Migration 2 — enforce
class EnforceUserStatusNotNull < ActiveRecord::Migration[8.0]
  def change
    change_column_null :users, :status, false
  end
end
```

On Postgres 12+, the NOT NULL enforcement uses an existing CHECK constraint shortcut if you create one first:

```ruby
# Migration 1 — add CHECK NOT VALID
add_check_constraint :users, "status IS NOT NULL", name: "users_status_null_check", validate: false

# Migration 2 — backfill any nulls

# Migration 3 — validate the check
validate_check_constraint :users, name: "users_status_null_check"

# Migration 4 — set NOT NULL using the check (instant, no scan)
change_column_null :users, :status, false
```

---

## Add an index

```ruby
class AddIndexToOrdersUserCreated < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :orders, [:user_id, :created_at],
      algorithm: :concurrently,
      order: { created_at: :desc },
      if_not_exists: true
  end
end
```

`CONCURRENTLY` (Postgres) — required for any table over ~10k rows.

For MySQL, online DDL syntax differs:

```ruby
add_index :orders, [:user_id, :created_at], algorithm: :inplace, lock: :none
```

---

## Add a foreign key

```ruby
# Migration 1
class AddFkOrdersUsers < ActiveRecord::Migration[8.0]
  def change
    add_foreign_key :orders, :users, validate: false
  end
end

# Migration 2
class ValidateFkOrdersUsers < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :orders, :users
  end
end
```

`validate: false` means new rows are FK-checked; existing rows aren't (yet). The `validate_foreign_key` step takes a less-blocking lock.

---

## Add a unique constraint

```ruby
# Step 1 — add a unique index CONCURRENTLY
class AddUniqueIndexEmailToUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!
  def change
    add_index :users, :email, unique: true, algorithm: :concurrently
  end
end
```

Postgres uses the index as the constraint mechanism — no separate UNIQUE constraint needed.

If existing data has duplicates, the index creation fails. Deduplicate in a backfill migration first, then add the index.

---

## Drop a table

```ruby
# Step 1 — remove all code references to the model.
# Step 2 — deploy. Verify no app server still references the model.
# Step 3 — migration:

class DropLegacyEvents < ActiveRecord::Migration[8.0]
  def change
    safety_assured { drop_table :legacy_events }
  end
end
```

Like remove_column but for the whole table.

---

## Rename a table

Same multi-step as rename column: add view or new table, dual-write, switch, drop old.

Often easier: leave the table name and rename the model:

```ruby
class Order < ApplicationRecord
  self.table_name = "legacy_orders"  # model is Order, table stays legacy_orders
end
```

---

## Add a check constraint

```ruby
# Migration 1 — add NOT VALID (no row scan)
class AddPositivePriceCheck < ActiveRecord::Migration[8.0]
  def change
    add_check_constraint :products, "price >= 0", name: "products_price_positive", validate: false
  end
end

# Migration 2 — validate (less-blocking lock)
class ValidatePositivePriceCheck < ActiveRecord::Migration[8.0]
  def change
    validate_check_constraint :products, name: "products_price_positive"
  end
end
```

---

## General principles

### The deploy / migrate / deploy split

For backwards-incompatible code changes:

1. **Pre-deploy migration** — schema change that is backwards-compatible with the OLD code.
2. **Code deploy** — new code that uses the new schema.
3. **Post-deploy migration** — schema cleanup (drop old columns/constraints).

### Lock and statement timeouts

Always set these globally:

```ruby
# config/initializers/strong_migrations.rb
StrongMigrations.lock_timeout = 10.seconds
StrongMigrations.statement_timeout = 1.hour
```

A migration that can't acquire its lock in 10 seconds is far less harmful than one that waits 30 minutes and holds the queue.

### Replica lag

Large backfills generate write traffic that replicas struggle to keep up with. Sleep briefly between batches (`sleep(0.01)`), or pause when replica lag exceeds a threshold:

```ruby
def wait_for_replicas
  loop do
    lag = ActiveRecord::Base.connection.exec_query(
      "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag"
    ).first["lag"].to_f
    break if lag < 1.0
    sleep 5
  end
end
```

Call between batches.

### Don't use models in migrations (long term)

Models change over time. A migration that uses `User.create!` may fail in 6 months when validations change.

For inline data work, use raw SQL via `execute(...)` or define a throwaway class:

```ruby
class BackfillUserSettings < ActiveRecord::Migration[8.0]
  class User < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    User.in_batches(of: 1000).update_all(settings: "{}")
  end
end
```

The inner `User` class is locked to this migration's schema knowledge.
