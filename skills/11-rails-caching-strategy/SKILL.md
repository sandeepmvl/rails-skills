---
name: rails-caching-strategy
description: Caching strategy for Ruby on Rails 8 — the cache layer hierarchy (HTTP/CDN → fragment cache → low-level cache → DB query cache), Solid Cache as the Rails 8 default, when Redis still wins (distributed pubsub + Sidekiq co-location), cache key design (versioned, content-addressed), Russian doll caching for nested views, Rails.cache.fetch patterns, cache stampede prevention via race_condition_ttl, HTTP caching with stale? / fresh_when, when caching is the wrong answer (fix the query first). Use when the user mentions caching, Rails.cache, Solid Cache, Redis, Memcached, fragment cache, low-level cache, cache_key, cache_version, race_condition_ttl, ETag, Last-Modified, stale?, fresh_when, or asks how to speed up a slow endpoint and the fix isn't a query change.
---

# Rails Caching Strategy

> Cache the right thing at the right layer. AI agents reach for `Rails.cache.fetch` on any slow code path, oblivious to the cache layer above (HTTP), the cache layer below (DB query cache), and the cost of cache invalidation. Caching is the second-hardest thing in computer science — get the layer wrong and you'll have stale data, mysterious bugs, and a 2am page.

## Why this matters

A cache is a contract: "this value is fresh enough for N seconds." Pick the wrong N, the wrong scope, or the wrong key, and you ship a bug that's invisible until users complain. Rails gives you four good caching tools — each is right for one situation.

## The opinion

> **Greenfield Rails 8: Solid Cache for the cache store, no Redis just for caching. Add Redis only when you need pub/sub or are co-locating with Sidekiq. HTTP caching at the edge (CDN) when it fits — biggest win, lowest cost. Fragment caching for view partials that repeat. Low-level (`Rails.cache.fetch`) for computed values keyed by something you control. Always: fix the query first.**

Counter-positions:
- **Redis as cache** — still legitimate for ultra-high-throughput sites or when you already run Redis for jobs. Solid Cache is plenty for most.
- **Memcached** — historical default. No reason to pick over Solid Cache or Redis in 2026.
- **Caching is the answer** — sometimes. The first answer is "fix the N+1, add the index, profile the SQL." Caching covers what's left.

## The cache hierarchy

```
┌────────────────────────────────────────────┐
│  L0: CDN / edge cache (Cloudflare, Fastly) │  ← Best — never hits Rails
│  L1: HTTP cache (Cache-Control headers)    │  ← Browser + reverse proxy
│  L2: Page cache  (rarely used now)         │
│  L3: Action cache (rare)                   │
│  L4: Fragment cache (view partials)        │  ← Most common
│  L5: Low-level cache (Rails.cache.fetch)   │  ← For computed data
│  L6: DB query cache (per-request, automatic)│  ← Rails handles this
└────────────────────────────────────────────┘
```

Cache higher in the stack when you can — it's cheaper. Cache lower only when you must.

## Core patterns

### Pattern 1: Solid Cache — the Rails 8 default

```ruby
# config/environments/production.rb
config.cache_store = :solid_cache_store
```

```yaml
# config/solid_cache.yml
production:
  database: cache_production  # separate connection, separate DB
  store_options:
    max_age: 14.days
    max_size: 256.gigabytes
    namespace: myapp
    encrypt: true
```

**Why DB-backed cache is fine for most apps:**
- SSDs are fast. Modern disks read at 3+ GB/s — comparable to Redis network latency.
- Larger working set: 256GB on disk vs 16GB in RAM is a meaningful difference.
- FIFO eviction (Solid Cache) is simpler than LRU and doesn't need read-tracking.
- One fewer service to operate.

**When Redis wins:**
- Sub-millisecond latency requirement (rare).
- You already have Redis for Sidekiq or Action Cable.
- Multi-region replication needs (Solid Cache works, but Redis Sentinel/Cluster is more mature).

### Pattern 2: Cache keys — version + content

**Before** (AI default — key drift bug):

```ruby
Rails.cache.fetch("posts/recent", expires_in: 1.hour) do
  Post.published.order(created_at: :desc).limit(20).to_a
end
```

Problem: when a new post publishes, this cache is stale for up to 1 hour. The TTL is also the maximum staleness — fine for some data, wrong for others.

**After** (cache key includes a content-addressed version):

```ruby
# Use the collection cache key — invalidates when any post in the set changes.
cache_key = Post.published.cache_key_with_version
Rails.cache.fetch(cache_key, expires_in: 1.day) do
  Post.published.order(created_at: :desc).limit(20).to_a
end
```

`cache_key_with_version` returns something like `posts/published-20260524123456`. As soon as any matching post is touched, the key changes and the cache is naturally invalidated.

**For single objects:**

```ruby
Rails.cache.fetch(@post, expires_in: 1.day) do
  expensive_computation(@post)
end
# Key is automatically "posts/123-20260524123456"
# Invalidates on post.touch / save.
```

**For composite keys:**

```ruby
Rails.cache.fetch(["dashboard", current_user, current_workspace.cache_key_with_version], expires_in: 5.minutes) do
  build_dashboard_data(current_user, current_workspace)
end
```

### Pattern 3: Fragment caching — Russian doll

```erb
<%# app/views/posts/index.html.erb %>
<% cache @posts do %>
  <% @posts.each do |post| %>
    <%= render post %>
  <% end %>
<% end %>
```

```erb
<%# app/views/posts/_post.html.erb %>
<% cache post do %>
  <article>
    <h2><%= post.title %></h2>
    <p><%= post.body %></p>
    <%= render post.author %>
    <%= render partial: "comments/comment", collection: post.comments, cached: true %>
  </article>
<% end %>
```

```erb
<%# app/views/comments/_comment.html.erb %>
<% cache comment do %>
  <div>
    <strong><%= comment.author.name %></strong>: <%= comment.body %>
  </div>
<% end %>
```

**How "Russian doll" works:**
- Each `cache` block uses the object's `cache_key_with_version`.
- When a `Comment` is touched (modified), its outer `Post` cache invalidates *if* you've set up `touch: true` on the association.

```ruby
class Comment < ApplicationRecord
  belongs_to :post, touch: true  # updating a comment touches the post → invalidates the post cache
end
```

- The inner caches (other comments, the author) survive — they don't share keys with the touched one.

**The `cached: true` partial render** is the magic — Rails batch-fetches all the inner cache entries with one Redis/SolidCache call instead of N.

### Pattern 4: Low-level caching — `Rails.cache.fetch`

Use for computed data that isn't view-specific:

```ruby
class Post < ApplicationRecord
  def popularity_score
    Rails.cache.fetch([self, "popularity_score"], expires_in: 1.hour) do
      compute_popularity_score  # expensive
    end
  end
end
```

**With race_condition_ttl** to prevent cache stampedes:

```ruby
Rails.cache.fetch("expensive_aggregate", expires_in: 1.hour, race_condition_ttl: 30.seconds) do
  expensive_aggregate
end
```

**What `race_condition_ttl` does:** when the entry expires, the first request to re-fetch holds the OLD value for an extra 30 seconds while it computes. Concurrent requests during that 30s window get the stale value instead of all stampeding the expensive computation. Critical for any expensive cache that gets hit frequently.

### Pattern 5: HTTP caching — `stale?` and `fresh_when`

For pages/endpoints where the freshness can be expressed as a timestamp or ETag, push caching to the browser and CDN.

```ruby
class PostsController < ApplicationController
  def show
    @post = Post.find(params[:id])

    # Browser sends If-Modified-Since / If-None-Match.
    # If still fresh, render returns 304 Not Modified with no body — no AR, no view render.
    fresh_when(@post, public: true)
  end

  def index
    @posts = Post.includes(:author).limit(20)

    # Use the most recently updated post as the freshness marker
    fresh_when(@posts, last_modified: @posts.maximum(:updated_at), public: true)
  end
end
```

```erb
<%# When you want to set Cache-Control: max-age explicitly %>
<%
  response.set_header("Cache-Control", "public, max-age=3600, stale-while-revalidate=300")
%>
```

**`public: true`** allows CDN caching (vs `private` which limits to browser-only). Use `public: true` for endpoints with no user-specific data.

**`stale-while-revalidate`** lets the CDN serve stale content while it asynchronously refreshes — best of both worlds for high-traffic pages.

### Pattern 6: Cache key versioning vs invalidation

Two strategies for "this cache should refresh":

**Strategy A: Content-addressed key (preferred)**

```ruby
Rails.cache.fetch(["dashboard", current_user.cache_key_with_version], expires_in: 1.day) do
  build_dashboard
end
```

User updates → `cache_key_with_version` changes → next fetch misses and recomputes. The old cache entry expires naturally.

**Strategy B: Explicit invalidation**

```ruby
Rails.cache.delete("dashboard:#{current_user.id}")
```

Explicit but error-prone — you must remember every invalidation point.

**Rule:** prefer A. Use B only when:
- The cache key depends on something not modeled in AR (e.g. external data).
- You need immediate invalidation (B is synchronous; A waits for the next miss).

### Pattern 7: When caching is wrong

Cache is a *bandage*, not a *fix*. If the underlying query is slow:

1. **Profile the query.** EXPLAIN ANALYZE. Add the index.
2. **Fix the N+1.** `.includes`, counter cache (see `n-plus-one-killer`).
3. **Denormalize** if the query is structurally expensive (5+ JOINs).
4. **Only then cache** what's still slow.

Caching a slow query that has a missing index hides the bug. A year later when traffic doubles, the cache miss spikes and the DB melts. Fix the query first.

### Pattern 8: Cache warming

For caches that are expensive and infrequently accessed:

```ruby
class WarmDashboardCacheJob < ApplicationJob
  def perform
    User.active.find_each do |user|
      # Force the cache write
      Dashboard.new(user).data  # internally calls Rails.cache.fetch
    end
  end
end

# Schedule via Solid Queue recurring.yml or sidekiq-cron
```

Warm the cache during off-peak hours so peak-traffic users don't pay the cold-cache cost.

### Pattern 9: Counter cache as an alternative to caching

Often misclassified as a cache; really it's denormalization. See `activerecord-patterns` Pattern 8 and `n-plus-one-killer` Pattern 3.

```ruby
class Comment < ApplicationRecord
  belongs_to :post, counter_cache: true
end
# post.comments.size → reads cached comments_count column, no query
```

This pattern fits between "cache" and "denormalize" — it's a denormalized cache the DB maintains for you.

### Pattern 10: Cache observability

```ruby
# Monitor cache hit ratio
class CacheObserver
  def call(name, started, finished, unique_id, payload)
    hit = name == "cache_read.active_support" && payload[:hit]
    StatsD.increment("rails.cache.#{hit ? 'hit' : 'miss'}")
  end
end

ActiveSupport::Notifications.subscribe(/^cache_/, CacheObserver.new)
```

- Hit ratio < 50%: caching isn't helping; reconsider.
- Hit ratio > 95%: caching is great; consider longer TTLs.
- Sudden drop: a cache_key version is changing too often.

## Decision matrix

| Need | Use |
|---|---|
| Public page, freshness expressible as timestamp/ETag | HTTP caching (`fresh_when`, CDN) |
| Logged-in user dashboard, repeated views | Low-level cache + content-addressed key |
| View partial that renders the same way for everyone | Fragment cache + collection cache |
| View partial that varies per user | Don't cache, OR use `cache [:user, current_user, partial]` |
| Computed value derived from a record | Low-level cache + `[self, "computation_name"]` |
| Count of associated records | counter_cache (not really caching, but solves the problem) |
| Many concurrent users hitting one expensive endpoint | low-level + `race_condition_ttl` |
| Data that must be instantly fresh | Don't cache. Or use content-addressed key (auto-invalidates). |

## Common mistakes to refuse

- Don't cache around a slow query that has a missing index. Fix the index.
- Don't use string TTL alone as the invalidation strategy — use content-addressed keys.
- Don't `Rails.cache.delete` from many code paths — it's error-prone. Use cache_key_with_version.
- Don't cache user-specific data with a non-user-scoped key. The data leaks to other users.
- Don't cache without `race_condition_ttl` on a hot path. Stampedes destroy DBs.
- Don't `Rails.cache.write` huge values (>1MB) — both Solid Cache and Redis slow down on large entries.
- Don't cache around a method that has side effects. The cache hits won't run them.
- Don't reach for Redis "just because it's faster" — Solid Cache is plenty for almost all apps.

## When NOT to use this skill

- The user is asking about HTTP caching specifically — touch lightly here, full coverage might warrant its own future skill.
- The user has an N+1 — that's `n-plus-one-killer`, not caching.

## See also

- `n-plus-one-killer` — fix the query first
- `activerecord-patterns` — counter caches (Pattern 8)
- `solid-queue-and-sidekiq` — cache warming jobs
- Coming in v0.3: `observability-rails-advanced` — cache hit metrics

## Sources

- [Rails Guides — Caching with Rails](https://guides.rubyonrails.org/caching_with_rails.html)
- [Solid Cache README](https://github.com/rails/solid_cache)
- [Solid Cache — Basecamp's production scale](https://dev.37signals.com/) — "10TB of data" anecdote
- [Russian Doll Caching — DHH](https://signalvnoise.com/posts/3113-how-key-based-cache-expiration-works)
- [Cache stampedes — Memcached blog](https://memcached.org/blog/) — pattern background
- [HTTP caching — Mozilla MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching)
- [stale-while-revalidate spec — RFC 5861](https://www.rfc-editor.org/rfc/rfc5861)
- [Rails 8 launch — Solid Cache encryption](https://rubyonrails.org/2024/11/7/rails-8-no-paas-required)
- [SiteSpeed — Cache hit ratio](https://www.sitespeed.io/) — observability defaults
- [pghero — finding slow queries first](https://github.com/ankane/pghero) — alternative to caching
