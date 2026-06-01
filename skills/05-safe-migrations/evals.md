# Evals for `safe-migrations`

## Prompt 1: Add a NOT NULL column with default on a 50M-row users table

**User prompt:**
> I need to add a `role` column to my users table. There are 50M rows. Default value should be "member". How?

**Expected:**
- Asks/checks Postgres version. If PG 11+ and Rails 5+, one migration is safe.
- Otherwise: split into 4 migrations (add nullable → change default → backfill in batches → enforce NOT NULL).
- Backfill uses `in_batches(of: 1000)` and `disable_ddl_transaction!`.
- Mentions `sleep(0.01)` for replica lag.

**Rubric:**
- [ ] Asked about PG version
- [ ] Multi-step split if needed
- [ ] Batched backfill with throttle

---

## Prompt 2: Remove a column

**User prompt:**
> I want to drop the `legacy_email` column from users. How?

**Expected:**
- Step 1: add `ignored_columns = %w[legacy_email]` to the model.
- Step 2: deploy.
- Step 3: drop the column in a migration (with `safety_assured`).
- Step 4: remove the ignored_columns line.

**Rubric:**
- [ ] ignored_columns first
- [ ] Two deploys minimum
- [ ] safety_assured used (with rationale)

---

## Prompt 3: Add an index on a big table

**User prompt:**
> I want to add an index on `orders.user_id`. The table has 100M rows.

**Expected:**
- `add_index :orders, :user_id, algorithm: :concurrently`.
- `disable_ddl_transaction!` at the top of the migration.
- Note: required for `CONCURRENTLY` on Postgres.

**Rubric:**
- [ ] algorithm: :concurrently
- [ ] disable_ddl_transaction!
- [ ] No naive add_index

---

## Prompt 4: Rename a column

**User prompt:**
> Can I just rename the `username` column to `handle`?

**Expected:**
- Refuses single-step rename.
- Walks through the 4-deploy dance (add → dual-write → backfill → switch → drop).
- Acknowledges this is the most expensive operation.

**Rubric:**
- [ ] Did not allow rename_column in one step
- [ ] Multi-deploy plan
- [ ] Honest about cost

---

## Prompt 5: Backfill in one big UPDATE

**User prompt:**
> I want to do `User.update_all(status: "active")` in a migration to backfill the new status column.

**Expected:**
- Warns against single-statement UPDATE on a large table (long lock, replica lag).
- Recommends `in_batches(of: 1000)` with `disable_ddl_transaction!`.
- Mentions throttling.

**Rubric:**
- [ ] Refused single-UPDATE pattern
- [ ] Batched alternative
- [ ] Replica-lag concern raised
