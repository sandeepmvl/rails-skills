# EXPLAIN ANALYZE for Rails devs

> When Bullet is silent but the page is still slow, drop to SQL. This file is the minimum you need to read a Postgres / MySQL query plan and decide what to do.

## TOC

- Getting the plan
- The shape of a plan
- The five things to look for
- Fixing each
- ActiveRecord's `.explain`
- Postgres-specific
- MySQL-specific

## Getting the plan

In a Rails console:

```ruby
puts Post.includes(:author).where(authors: { active: true }).references(:authors).limit(20).explain
```

Or in psql:

```sql
EXPLAIN ANALYZE
SELECT posts.*, authors.*
FROM posts
LEFT OUTER JOIN authors ON authors.id = posts.author_id
WHERE authors.active = TRUE
ORDER BY posts.created_at DESC
LIMIT 20;
```

`EXPLAIN` shows the planned strategy. `EXPLAIN ANALYZE` *runs* the query and reports actual times. Use `ANALYZE` unless the query is destructive or the cost is unknown.

## The shape of a plan (Postgres)

```
Limit  (cost=0.84..15.62 rows=20 width=312) (actual time=0.05..0.20 rows=20 loops=1)
  ->  Sort  (cost=0.84..1.04 rows=80 width=312) (actual time=0.05..0.15 rows=20 loops=1)
        Sort Key: posts.created_at DESC
        ->  Hash Join  (cost=0.30..0.72 rows=80 width=312)
              Hash Cond: (posts.author_id = authors.id)
              ->  Seq Scan on posts  (cost=0.00..0.30 rows=80 width=200)
              ->  Hash  (cost=0.20..0.20 rows=10 width=112)
                    ->  Seq Scan on authors  (cost=0.00..0.20 rows=10 width=112)
                          Filter: active
Planning time: 0.5 ms
Execution time: 0.25 ms
```

Read it inside-out. Innermost operations run first, outer ones consume their output.

## The five things to look for

### 1. Sequential scans on big tables

```
Seq Scan on posts  (cost=0.00..32891.00 rows=1000000 ...)
```

Postgres is reading every row. Fine on small tables (< ~10k rows). Catastrophic on large ones.

**Fix:** add an index on the WHERE / JOIN / ORDER BY column. For a query like `WHERE author_id = ? ORDER BY created_at DESC LIMIT 20`, the right index is composite: `(author_id, created_at DESC)`.

### 2. Nested loop with high row count

```
Nested Loop  (cost=0..15000 rows=10000)
  ->  Seq Scan on posts (rows=10000)
  ->  Index Scan on comments (rows=1 for each)
```

The inner side runs once per outer row. Fine when the outer is small; horrible when it's not.

**Fix:** force a hash join with statistics (`ANALYZE table_name`) or by re-shaping the query. Often, eager loading at the app level beats trying to coerce the planner.

### 3. Sort with disk

```
Sort  (cost=...)  Sort Method: external merge  Disk: 80000kB
```

The sort overflowed `work_mem` and spilled to disk. 50–500× slower than in-memory.

**Fix:** add an index that pre-orders the rows (`ORDER BY` column comes from an index), or increase `work_mem` for the query.

### 4. Rows estimate way off

```
Hash Join  (cost=... rows=1000) (actual rows=1000000 loops=1)
```

Estimated 1k, actually 1M. The planner picked a bad strategy because its stats are stale.

**Fix:** `ANALYZE table_name;` to refresh statistics. If still off, consider extended statistics or histograms.

### 5. Filter (not Index Cond)

```
Index Scan using idx_posts_author_id
  Index Cond: (author_id = 5)
  Filter: (status = 'published')
```

The index narrowed by `author_id`, then a *filter* discarded the rows where `status` wasn't 'published'. The filter pass is non-indexed.

**Fix:** if `status` is highly selective, add a composite index `(author_id, status)` or a partial index `WHERE status = 'published'`.

## ActiveRecord's `.explain`

```ruby
Post.where(author_id: 5).order(:created_at).limit(20).explain
```

Returns the plan formatted as a string. Pipe it through your terminal or paste it into a query-plan visualizer (e.g. [explain.depesz.com](https://explain.depesz.com/) for Postgres) for color-coded annotation.

## Adding an index — the safe-migrations way

```ruby
# db/migrate/20260524_add_index_to_posts_author_created_at.rb
class AddIndexToPostsAuthorCreatedAt < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!  # required for CONCURRENTLY

  def change
    add_index :posts, [:author_id, :created_at], algorithm: :concurrently, order: { created_at: :desc }
  end
end
```

`algorithm: :concurrently` avoids locking the table on Postgres. See `safe-migrations` for the full zero-downtime playbook.

## Postgres-specific tools

- `pg_stat_statements` — top queries by total time (enable extension; restart not needed).
- `auto_explain` — log the plan for any query slower than N ms (`auto_explain.log_min_duration = '500ms'`).
- `pg_stat_user_indexes` — find unused indexes (drop them).
- [pgHero](https://github.com/ankane/pghero) — dashboard over `pg_stat_*` views. Rails-friendly.

## MySQL-specific

```sql
EXPLAIN FORMAT=TREE SELECT ... ;        -- MySQL 8+, similar to Postgres tree output
EXPLAIN ANALYZE SELECT ... ;            -- MySQL 8+, runs the query
```

Look for:
- `type: ALL` — full table scan (bad on large tables).
- `Using filesort` — sort happens outside an index (often fixable with index).
- `Using temporary` — temp table created.

## When EXPLAIN says "the plan is fine" but the query is still slow

- Lock waits — check `pg_locks` / `SHOW ENGINE INNODB STATUS`.
- Replica lag — read query running on stale replica.
- Network latency between app and DB.
- N+1 in the *app*, not the SQL — go back to Bullet.

## See also

- `n-plus-one-killer/SKILL.md` — the parent skill
- `safe-migrations` — for adding indexes without locking
- `rails-caching-strategy` — when caching beats indexing
- Coming in v0.2: `multi-database-and-replicas` — when the slow query lands on the wrong DB
