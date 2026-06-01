# Evals for `n-plus-one-killer`

## Prompt 1: "My posts index is slow"

**User prompt:**
> The `/posts` page takes 800ms. The controller is `@posts = Post.order(created_at: :desc).limit(20)` and the view shows post.author.name and post.comments.count per post. Help.

**Expected behavior:**
- Identifies the two N+1s (author + comments.count).
- Adds `.includes(:author)` for the author N+1.
- Recommends counter cache (`comments_count`) for the count N+1 — including the migration with `reset_counters` backfill.
- Recommends adding Bullet config so this regression is caught next time.

**Rubric:**
- [ ] Both N+1s diagnosed
- [ ] `.includes(:author)` applied
- [ ] Counter cache recommended (not just COUNT-in-query)
- [ ] Bullet wiring mentioned

---

## Prompt 2: "Bullet says my page has N+1 but I do use `.includes`"

**User prompt:**
> Bullet flags my action as N+1. I have `Post.includes(:author).where(authors: { active: true }).limit(20)`. What am I missing?

**Expected behavior:**
- Notes that hash-form `where(authors: {...})` auto-escalates `includes` to `eager_load` since Rails 4 — no Rails-version trap here.
- The Bullet flag is likely on a *different* association the controller didn't preload. Common culprits: nested calls in the view (`post.author.profile.bio`), iterated counts (`.comments.count`), or `each` blocks calling associations not in `.includes`.
- Tells the user to read Bullet's exact log message — it names the class and association.

**Rubric:**
- [ ] Did not invent a Rails 6→7 cliff
- [ ] Pointed at the view / nested associations / counts
- [ ] Mentioned reading Bullet's actual message

---

## Prompt 3: "Should I use goldiloader?"

**User prompt:**
> Should I add goldiloader so I never have to worry about N+1?

**Expected behavior:**
- Acknowledges the appeal but recommends against as default.
- Notes the trade-off: over-eager-loading associations the request doesn't render.
- Recommends explicit eager loading + Bullet/Prosopite + test-fail-on-N+1 as the production-quality pattern.
- Concedes goldiloader is fine for teams that have explicitly accepted the trade-off.

**Rubric:**
- [ ] Did not silently install goldiloader
- [ ] Surfaced the over-eager-load risk
- [ ] Recommended detection-first approach

---

## Prompt 4: "JOIN is too slow — query plan shows a 5-way join"

**User prompt:**
> Adding `.includes` made the query slower, not faster. The EXPLAIN ANALYZE shows a 5-way join scanning millions of rows.

**Expected behavior:**
- Recognizes eager loading isn't always the fix.
- Recommends denormalization: cached aggregate columns, counter caches, materialized views.
- Walks through the EXPLAIN ANALYZE output from `references/query-explained.md`.
- Suggests `pg_stat_statements` for production diagnosis.

**Rubric:**
- [ ] Acknowledged that more eager loading isn't always right
- [ ] Recommended denormalization
- [ ] Referenced EXPLAIN ANALYZE workflow

---

## Prompt 5: "Where do I add Bullet config?"

**User prompt:**
> How do I add Bullet to a new Rails app?

**Expected behavior:**
- Provides Gemfile add line for `:development, :test`.
- Provides the dev config (logger, footer, console).
- Provides the test config with `Bullet.raise = true`.
- Provides the RSpec hooks (`before(:each) { Bullet.start_request }`).
- Notes the `add_safelist` API for known-safe cases.

**Rubric:**
- [ ] Both dev and test configs given
- [ ] Test config has `raise: true`
- [ ] RSpec hooks included
- [ ] Safelist mentioned for false-positive handling
