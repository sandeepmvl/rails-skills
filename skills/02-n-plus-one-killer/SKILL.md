---
name: n-plus-one-killer
description: Detect, diagnose, and eliminate N+1 queries in Ruby on Rails. Use when the user mentions slow Rails endpoints, slow queries, "N+1", Bullet, prosopite, includes/preload/eager_load, eager loading, query count is high, page is slow to render, or asks why a Rails controller is slow. Also use proactively when reviewing any controller action that iterates a collection and accesses associations, or any view that loops and calls `.author`, `.comments.count`, etc. Bundles a Bullet config script and an EXPLAIN ANALYZE reference for Rails devs.
---

# N+1 Killer

> Find every N+1 in a Rails app and remove it. AI agents generate N+1s constantly — they write `.each` in a controller and call `.author` in the view without realizing each row triggers a fresh SELECT. This skill makes the agent detect first, then fix, then prevent.

## Why this matters

The single most common Rails performance issue. A list endpoint with 20 rows and a hidden N+1 issues 21+ queries per request. At 100 RPS that's 2100 queries/second the DB didn't need to handle. The fix is one method call; the detection is what people miss.

## The opinion (Rails 8 default)

> **Detect with Bullet in development + test, fail tests on N+1, fix with `includes` (or `preload` / `eager_load` when the trade-off is explicit). For the queries Bullet misses, add Prosopite. Reach for `counter_cache` and small denormalizations when the eager-loaded query is still too heavy.**

Counter-position: gems like `ar_lazy_preload` and `goldiloader` automatically eager-load on first access in a loop. They eliminate the symptom but hide the cost — and they can over-eager-load (loading associations you only sometimes need). Use them only if the team has agreed to the trade-off; default to explicit eager loading.

## Core patterns

### Pattern 1: Detect with Bullet (dev + test)

**Before** (typical AI-generated controller, no detection in place):

```ruby
class PostsController < ApplicationController
  def index
    @posts = Post.order(created_at: :desc).limit(20)
  end
end
```

Template:
```erb
<% @posts.each do |post| %>
  <%= post.title %> by <%= post.author.name %> (<%= post.comments.count %> comments)
<% end %>
```

This issues:
- 1 query for posts
- 20 queries for `post.author` (N+1 on belongs_to)
- 20 queries for `post.comments.count` (N+1 on counts)

Total: **41 queries**.

**After** (Bullet wired up + fix applied):

```ruby
# config/environments/development.rb
config.after_initialize do
  Bullet.enable        = true
  Bullet.alert         = false        # browser popup off
  Bullet.bullet_logger = true         # log/bullet.log
  Bullet.console       = true         # browser JS console
  Bullet.rails_logger  = true         # tail with `tail -f log/development.log`
  Bullet.add_footer    = true         # banner at the bottom of the page
end

# config/environments/test.rb
config.after_initialize do
  Bullet.enable = true
  Bullet.raise  = true                # fail the spec on any N+1
end
```

```ruby
# spec/rails_helper.rb
RSpec.configure do |config|
  config.before(:each) { Bullet.start_request if Bullet.enable? }
  config.after(:each) do
    Bullet.perform_out_of_channel_notifications if Bullet.notification?
    Bullet.end_request if Bullet.enable?
  end
end
```

Then the fix:

```ruby
class PostsController < ApplicationController
  def index
    @posts = Post
      .includes(:author)
      .order(created_at: :desc)
      .limit(20)
  end
end
```

Plus add a counter cache for `comments_count` (see Pattern 3).

Total after fix: **2 queries** (posts + authors WHERE id IN (…)). 20× reduction.

**Why:** Bullet hooks into ActiveRecord and tracks which associations were loaded vs accessed per request. If accessed without loading, it's an N+1. In test mode with `raise = true`, the spec fails — the regression is caught at PR time, not in prod.

Bundled config: [`scripts/bullet-config.rb`](scripts/bullet-config.rb) is a drop-in starting point with sane defaults.

### Pattern 2: Catch what Bullet misses — Prosopite

Bullet tracks *association access*. It misses N+1s that look like repeated `where()` calls in a loop:

```ruby
@orders.each do |order|
  # No association — direct query inside a loop.
  user = User.where(email: order.user_email).first
  # Bullet doesn't see this; Prosopite does.
end
```

Prosopite detects query *patterns*: the same SQL skeleton issued more than N times with different parameters in one request.

```ruby
# Gemfile (development + test)
gem "prosopite"

# config/initializers/prosopite.rb (development + test only)
if Rails.env.development? || Rails.env.test?
  Prosopite.rails_logger = true
  Prosopite.raise        = true if Rails.env.test?
end

# spec/rails_helper.rb
RSpec.configure do |config|
  config.before(:each) { Prosopite.scan }
  config.after(:each)  { Prosopite.finish }
end
```

**When you need both Bullet AND Prosopite:** large codebases with mixed access patterns. Bullet is association-aware (cheaper to satisfy); Prosopite catches the rest.

### Pattern 3: COUNT N+1 — counter cache

**Before** (per-post COUNT in a loop):

```ruby
# View
<%= post.comments.count %>
# SQL per post: SELECT COUNT(*) FROM comments WHERE post_id = ?
```

**After** (counter cache):

```ruby
class Comment < ApplicationRecord
  belongs_to :post, counter_cache: true
end
```

Migration adds only the column (no inline backfill — see `safe-migrations`):
```ruby
class AddCommentsCountToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :comments_count, :integer, null: false, default: 0
  end
end
```

Backfill runs as a separate post-deploy job (don't reference models in migrations on large tables):
```ruby
class BackfillCommentsCountJob < ApplicationJob
  def perform
    Post.unscoped.in_batches(of: 1000) do |relation|
      relation.each { |p| Post.reset_counters(p.id, :comments) }
      sleep(0.01)
    end
  end
end
```

In views, use `.size` — it auto-reads the counter cache column when declared:
```erb
<%= post.comments.size %>
<!-- Reads from cached comments_count column — zero extra queries. -->
```

**Drift gotcha:** counter caches only update through ActiveRecord. Direct SQL inserts bypass. Add a periodic reset job for any model whose children may be touched outside AR. See `activerecord-patterns` Pattern 8.

### Pattern 4: `includes` vs `preload` vs `eager_load` — decision tree

```
Do I need to filter/order by the associated table's columns?
├─ No  → preload(:assoc)       — 2 queries, no JOIN
├─ Yes → eager_load(:assoc)    — 1 query, LEFT OUTER JOIN
└─ Mixed / not sure → includes(:assoc) + .references(:assoc) when needed
```

Full SQL and edge cases in `activerecord-patterns/references/includes-preload-eager-load.md`.

### Pattern 5: Nested eager loading

**Before** (N+M+P queries):

```ruby
@posts.each do |post|
  post.comments.each do |comment|
    comment.user.name  # N (posts) × M (comments) — exponential
  end
end
```

**After**:

```ruby
@posts = Post.includes(comments: :user).limit(20)
```

Three queries: posts; comments WHERE post_id IN (…); users WHERE id IN (…).

For deeply nested:

```ruby
Post.includes(author: :profile, comments: [:user, :likes])
```

### Pattern 6: When eager loading is the wrong fix — denormalize

If the eager-loaded query is still slow (5+ JOINs, gigabyte sort, complex WHERE), the answer isn't more eager loading. It's denormalization:

- **Counter caches** for counts (Pattern 3).
- **Cached aggregate columns**: `total_comment_count`, `last_activity_at`, `avg_rating`. Update in `after_commit` or via a periodic recalc job.
- **Materialized views** (Postgres): for complex aggregations that change less often than they're queried.

**Trade-off:** denormalized data drifts. Always have a recalc job. Always have a reconciliation check that runs in CI or staging.

### Pattern 7: When N+1 is fine

Not every N+1 is a bug. Skip the fix when:

- The set is **small and fixed** (< ~5 rows, never grows). Two queries on an admin debug page aren't worth refactoring.
- The associated data is **already cached** (request-level cache, page cache).
- The "fix" requires loading huge amounts of data the user won't see (a list of 1000 posts where the user scrolls to 20 — eager loading all 1000 authors is worse).

Add a `Bullet.add_safelist` entry to silence Bullet on the known-safe path:

```ruby
Bullet.add_safelist type: :n_plus_one_query, class_name: "AdminAuditLog", association: :user
```

### Pattern 8: Production diagnosis — query log tailing

For an N+1 you only see in production:

```ruby
# config/application.rb (Rails 7+)
config.active_record.query_log_tags_enabled = true
config.active_record.query_log_tags = [
  :application, :controller, :action, :job,
  { request_id: ->(context) { context[:controller]&.request&.request_id } }
]
```

Now every SQL statement in `production.log` is **annotated with a trailing SQL comment** like `/*application:MyApp,controller:posts,action:index,request_id:abc-123*/`. Grep the log for a slow request_id and you see exactly which controller action issued which queries. The comment also surfaces in `pg_stat_statements`, so DB-side query analysis shows app-level attribution.

For Rails < 7, use [`marginalia`](https://github.com/basecamp/marginalia) (the precursor that Basecamp donated to Rails). It's effectively legacy now — the built-in `query_log_tags` covers the same ground on Rails 7+.

### Pattern 9: APM-based detection

For prod-only N+1s, APM tools catch them at the transaction level:

| Tool | N+1 detection | Best for |
|---|---|---|
| Scout APM | First-class N+1 trace view; identifies which line of which template | Rails-focused teams; cheap |
| Skylight | "Endpoints" view shows queries per request; flags suspicious counts | Medium-traffic Rails apps |
| New Relic / Datadog APM | Generic transaction trace; you spot N+1s by reading the waterfall | Multi-language teams |

The skill is technology-agnostic on the choice — but every prod Rails app needs *some* APM that surfaces query count per endpoint.

### Pattern 10: Detection at the SQL layer — `pg_stat_statements`

When the app-level tools miss a pattern, look at the database:

```sql
-- Top 20 queries by total time (PostgreSQL):
SELECT
  query,
  calls,
  total_exec_time,
  mean_exec_time,
  rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

A query with high `calls` and low `mean_exec_time` is suspicious — likely fired many times per request. Grep for that SQL skeleton in the app to find the culprit.

For full EXPLAIN ANALYZE workflow (reading plans, spotting seq scans, identifying missing indexes), see [`references/query-explained.md`](references/query-explained.md).

## Decision matrix — pick the tool

| Situation | Use |
|---|---|
| New Rails app, want N+1 detection from day one | Bullet (dev + test, `raise: true` in test) |
| Bullet misses your pattern (raw `where().first` in loop) | Add Prosopite |
| COUNT(*) in a loop | `counter_cache` |
| 5+ JOINs in the eager-loaded query, still slow | Denormalize (cached aggregate column) |
| N+1 only happens in prod | APM (Scout / Skylight) + query_log_tags |
| Need to find which SQL pattern is firing 1000×/request | `pg_stat_statements` (Postgres) |
| Team wants "no N+1 ever" automatically | `ar_lazy_preload` / `goldiloader` — explicit risk of over-eager-loading |

## Common mistakes to refuse

- Don't ignore Bullet's notifications. Either fix the N+1, or `add_safelist` it with a comment explaining why.
- Don't replace `.count` with `.length` to silence the query — `.length` loads all rows then counts in Ruby; worse than the COUNT.
- Don't reach for `goldiloader` / `ar_lazy_preload` as the first fix. They mask the issue.
- Don't `.includes(:assoc)` "just in case" — eager-loading associations you don't render wastes memory.
- Don't skip the counter-cache backfill (`reset_counters`) on an existing table. Without it, every existing row reads 0.
- Don't disable Bullet in tests because "it's failing the suite" — the failing tests are surfacing real bugs.

## When NOT to use this skill

- The user is asking how to *write* a Rails query (no perf context). Use `activerecord-patterns` instead.
- The query is slow but the EXPLAIN shows a missing index — that's an index issue, not N+1. Pull the index discussion from `references/query-explained.md`.

## See also

- `activerecord-patterns` — Patterns 2, 4, 8, 11 cover the underlying query idioms
- `rails-caching-strategy` — when caching beats eager loading
- `safe-migrations` — for adding counter cache columns to large tables
- Coming in v0.2: `multi-database-and-replicas` — when read-replica routing changes the fix

## Bundled assets

- [`scripts/bullet-config.rb`](scripts/bullet-config.rb) — drop-in dev + test config
- [`references/query-explained.md`](references/query-explained.md) — EXPLAIN ANALYZE for Rails devs

## Sources

- [Bullet README](https://github.com/flyerhzm/bullet) — detection mechanics, notifier list, safelist API
- [Prosopite README](https://github.com/charkost/prosopite) — query-pattern N+1 detection
- [Rails Guides — Active Record Querying §17 Eager Loading](https://guides.rubyonrails.org/active_record_querying.html#eager-loading-of-associations)
- [Rails Guides — Active Record Querying §13 Pluck](https://guides.rubyonrails.org/active_record_querying.html#pluck)
- [API — ActiveRecord::QueryMethods#includes](https://api.rubyonrails.org/classes/ActiveRecord/QueryMethods.html)
- [ActiveSupport::Notifications — sql.active_record event](https://guides.rubyonrails.org/active_support_instrumentation.html#sql-active-record)
- [Rails 7 query log tags](https://guides.rubyonrails.org/active_record_querying.html#enabling-query-log-tags) — production attribution
- [Marginalia README](https://github.com/basecamp/marginalia) — SQL comment attribution (alternative to built-in)
- [pg_stat_statements docs](https://www.postgresql.org/docs/current/pgstatstatements.html) — DB-side query stats
- [Scout APM Rails docs](https://scoutapm.com/docs/ruby/rails) — APM-based N+1 detection
- [Skylight docs](https://www.skylight.io/) — endpoint-level performance
