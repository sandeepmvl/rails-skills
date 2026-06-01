# Evals for `rails-caching-strategy`

## Prompt 1: "Speed up the slow endpoint by caching"

**User prompt:**
> My `/posts` endpoint takes 800ms. Should I add `Rails.cache.fetch` around the controller?

**Expected:**
- Asks what makes it slow. EXPLAIN ANALYZE the query.
- Likely answers: missing index, N+1, structurally expensive query.
- Fix the underlying issue first. Cache is the last resort.
- If still slow after the fix, recommends content-addressed low-level cache.

**Rubric:**
- [ ] Did not auto-cache as first answer
- [ ] Diagnosed first
- [ ] Recommended N+1 / index audit before caching

---

## Prompt 2: "Solid Cache or Redis?"

**User prompt:**
> Rails 8 greenfield app. Solid Cache or Redis for caching?

**Expected:**
- Solid Cache as default.
- Reasons: SSD is fast, no extra service, ships with Rails 8.
- Redis trigger conditions: already running Redis for Sidekiq, sub-ms latency requirement.

**Rubric:**
- [ ] Solid Cache recommended
- [ ] Trade-off explained
- [ ] Redis triggers listed

---

## Prompt 3: "Cache key with TTL only"

**User prompt:**
> I'm using `Rails.cache.fetch("recent_posts", expires_in: 1.hour)`. New posts don't show for an hour.

**Expected:**
- Identifies the TTL = staleness problem.
- Switches to `Post.published.cache_key_with_version`.
- Explains content-addressed keys auto-invalidate.

**Rubric:**
- [ ] cache_key_with_version recommended
- [ ] Auto-invalidation explained
- [ ] TTL-only pattern marked as wrong

---

## Prompt 4: "Cache stampede on a hot endpoint"

**User prompt:**
> When my cache expires, my DB CPU spikes to 100% for 30 seconds.

**Expected:**
- Identifies the stampede: many concurrent requests recompute.
- Recommends `race_condition_ttl`.
- Sets it to roughly the expected recompute time.

**Rubric:**
- [ ] Diagnosed stampede
- [ ] race_condition_ttl recommended
- [ ] Sized appropriately

---

## Prompt 5: "Fragment cache leaks per-user data"

**User prompt:**
> My fragment cache shows User A's data to User B.

**Expected:**
- Identifies the cache key doesn't include user.
- Recommends `cache [:dashboard, current_user, partial]` — user in the key.
- Or, don't cache per-user content unless you have a hit-ratio reason to.

**Rubric:**
- [ ] Identified user-key missing
- [ ] Fixed by including user in key
- [ ] Or suggested not caching per-user content

---

## Prompt 6: "HTTP caching for a public page"

**User prompt:**
> My blog post page is public. How do I cache it at the CDN?

**Expected:**
- `fresh_when(@post, public: true)` in the controller.
- Set `Cache-Control: public, max-age=3600` or similar.
- Mention `stale-while-revalidate` for high-traffic pages.

**Rubric:**
- [ ] fresh_when used
- [ ] public: true
- [ ] CDN Cache-Control set
