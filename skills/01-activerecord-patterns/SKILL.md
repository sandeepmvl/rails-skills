---
name: activerecord-patterns
description: Idiomatic ActiveRecord patterns for Ruby on Rails — associations (belongs_to/has_many/has_one/has_many :through), counter_cache, polymorphic, STI vs delegated_type, scopes vs class methods, callbacks vs after_commit, find vs find_by vs where.first, includes vs preload vs eager_load, pluck vs select, exists? vs any?, batch processing with find_each, and fat-models-with-concerns. Use whenever the user writes or reviews ActiveRecord models, asks why a Rails query is slow or wrong, mentions includes/preload/eager_load, says "callback", references scopes, or is generating model code. Also use proactively when reading any Rails model file (app/models/*.rb).
---

# ActiveRecord Patterns

> Senior Rails ActiveRecord conventions, organized as before/after pattern pairs. AI agents routinely violate these — they reach for callbacks where a job belongs, use `where.first` when `find_by` exists, default-scope themselves into corners, and lose database integrity through naïve polymorphic associations. This skill makes the agent write models the way the Rails core team writes them.

## The opinion (DHH-leaning default)

> **Fat models are fine. Put domain logic in the model. Use ActiveSupport::Concern to split fat models into focused mixins. Reach for service objects only when (a) orchestrating multiple models in a single workflow, (b) calling external APIs, or (c) the workflow lives outside an obvious model's domain.**

DHH on this:

> "I far prefer `current_account.posts.visible_to(current_user)` to involving a third query object."  
> — *Put Chubby Models on a Diet with Concerns*

The counter-position: small-object-per-responsibility (the Sandi Metz / 7±2 doctrine) keeps churn cheaper in very large codebases. We acknowledge that and recommend it only at team-size-large (20+) — see `service-objects-vs-fat-models` for the full breakdown.

---

## Core patterns

### Pattern 1: `find` vs `find_by` vs `where.first`

The wrong choice silently hides bugs.

**Before** (AI-typical, semantically wrong):

```ruby
# Returns nil if no slug match, then NoMethodError on `.title` two screens later.
post = Post.where(slug: params[:slug]).first
post.title

# Or this version that hides ordering bugs:
post = Post.where(author_id: current_user.id).first
# No order specified — "first" is whatever the DB happened to return.
```

**After** (Rails-conventional):

```ruby
# `find_by` is the single-record finder. Returns nil if missing — handle it.
post = Post.find_by(slug: params[:slug])
return head :not_found unless post

# Use the bang form when "missing" must crash:
post = Post.find_by!(slug: params[:slug])

# Use `find(id)` for primary-key lookups — it always raises ActiveRecord::RecordNotFound.
post = Post.find(params[:id])

# When you legitimately need the first of an ordered set, order explicitly:
latest = Post.where(author_id: current_user.id).order(created_at: :desc).first
```

**Why:** `where.first` on an unordered relation is non-deterministic — Postgres may return different rows on different days. `find_by` exists for the "one or nil" semantic; `find_by!` for "one or crash"; `find` for primary-key lookup. Picking the right one tells future readers what you mean.

### Pattern 2: `includes` vs `preload` vs `eager_load`

The decision tree most AI agents botch.

**Before** (AI-typical, N+1 hidden):

```ruby
# Causes 1 + N queries when the template renders post.author.name.
@posts = Post.order(created_at: :desc).limit(20)
```

**After** (Rails-conventional):

```yaml
# Default: includes. Rails picks preload or eager_load based on how you use it.
@posts = Post.includes(:author).order(created_at: :desc).limit(20)

# Need WHERE/ORDER on associated columns? Hash-form auto-escalates to eager_load (LEFT OUTER JOIN):
@posts = Post.includes(:author).where(authors: { active: true })

# Only need `.references(:authors)` when filtering with raw SQL strings:
@posts = Post.includes(:author).where("authors.active = ?", true).references(:authors)
```

**Decision matrix:**

| Need | Method | SQL |
|---|---|---|
| Eager-load without conditions on associated table | `preload` | 2 queries: posts; authors WHERE id IN (…) |
| Eager-load AND filter/order by associated columns | `eager_load` | 1 query: posts LEFT OUTER JOIN authors WHERE … |
| You don't care — let Rails decide | `includes` | Rails picks based on `.where` / `.references` |

**Why:** `includes` decides between `preload` and `eager_load` for you. Reach for the lower-level methods when you need explicit control over memory or JOIN cost.

For nested eager loading, conditional escalation, `has_many` + LIMIT gotchas, and the full SQL each method emits, see [`references/includes-preload-eager-load.md`](references/includes-preload-eager-load.md).

### Pattern 3: `pluck` vs `select`

When you don't need model instances.

**Before** (AI-typical, wasted memory):

```ruby
# Instantiates N User objects just to read names.
names = User.where(active: true).map(&:name)
```

**After** (Rails-conventional):

```ruby
# Skips ActiveRecord instantiation — raw array of strings.
names = User.where(active: true).pluck(:name)

# Multiple columns:
id_name_pairs = User.where(active: true).pluck(:id, :name)
# => [[1, "Alice"], [2, "Bob"]]

# Use `select` only when you need a partial model (you'll call methods on the object):
users = User.where(active: true).select(:id, :name)
users.first.name  # works
users.first.email # NoMethodError — not selected
```

**Why:** `pluck` is the right tool when the next thing you do is render strings or build a hash. `select` builds partial AR objects that respond to model methods on the selected columns only. Reaching for `map(&:attr)` is the common AI mistake — it allocates N model objects for no reason.

### Pattern 4: `exists?` vs `any?` vs `present?` vs `count > 0`

For boolean checks, only one is right.

**Before** (AI-typical, wasteful):

```ruby
if Order.where(user: u).count > 0
  # Forces a full COUNT(*) — slow on large tables.
end

if Order.where(user: u).any?
  # Slightly better — uses LIMIT 1 — but still loads relation state.
end

if Order.where(user: u).present?
  # Loads the entire relation into memory then asks if it's non-empty.
end
```

**After**:

```ruby
if Order.exists?(user: u)
  # SELECT 1 FROM orders WHERE user_id = ? LIMIT 1 — terminating boolean check.
end
```

**Why:** `exists?` issues the most-minimal SQL possible for a boolean answer (`SELECT 1 … LIMIT 1`). `count > 0` issues a full `SELECT COUNT(*)` — fine for tiny tables, painful on large ones. `present?` loads the relation into memory then asks if it's non-empty. `any?` (without a block, on an unloaded relation) issues `SELECT 1 … LIMIT 1` so it's close to `exists?` — but `exists?` is the canonical idiom, doesn't risk `.any? { |x| … }` ever being introduced (which loads everything), and reads more clearly.

### Pattern 5: Scopes vs class methods (nil-return foot-gun)

**Before** (AI-typical, breaks chainability):

```ruby
class Post < ApplicationRecord
  def self.published_before(time)
    where(published_at: ...time) if time.present?
    # When time is nil, the method returns nil — caller breaks.
  end
end

Post.published_before(nil).order(:title)  # NoMethodError: undefined method `order' for nil
```

**After** (Rails-conventional, always returns Relation):

```ruby
class Post < ApplicationRecord
  scope :published_before, ->(time) {
    where(published_at: ...time) if time.present?
  }
  # When time is nil, scope returns Post.all — caller chain continues to work.
end

Post.published_before(nil).order(:title)  # SELECT * FROM posts ORDER BY title
```

**Why:** From the Rails guides: "A scope will always return an ActiveRecord::Relation object, even if the conditional evaluates to false, whereas a class method will return nil." Always use scopes for query composition. Reach for class methods only when you need non-relation return values (booleans, counts) or for true class-level operations.

### Pattern 6: `default_scope` — almost always wrong

**Before** (the foot-gun):

```ruby
class Post < ApplicationRecord
  default_scope { where(deleted_at: nil) }
end

# Now every Post query silently filters deleted rows.
# Joins, has_many through this model, even raw .find(id) — all filtered.
# Months later: `Post.unscoped.find(id)` becomes required and nobody remembers why.
```

**After**:

```ruby
class Post < ApplicationRecord
  scope :active, -> { where(deleted_at: nil) }
end

# Explicit at call sites:
Post.active.order(created_at: :desc)
```

**Why:** `default_scope` adds invisible WHERE clauses to *every* query, including associations and `.find`. It makes debugging painful and forces `.unscoped` sprinklings that are easy to miss. The named scope is one extra word at the call site and saves a debugging session a year later. If you need soft delete, use [`discard`](https://github.com/jhawthorn/discard) — it adds explicit `kept` / `discarded` scopes without touching `default_scope`. Avoid [`paranoia`](https://github.com/rubysherpas/paranoia): it overrides `delete`/`destroy` and adds an internal `default_scope { where(deleted_at: nil) }` — the exact pattern we just argued against.

### Pattern 7: Callbacks — `after_save` vs `after_commit`

Side effects belong in `after_commit`. AI agents reach for `after_save` and lose data integrity.

**Before** (AI-typical, double-fires + race condition):

```ruby
class Post < ApplicationRecord
  after_save :enqueue_publish_job

  private

  def enqueue_publish_job
    PublishPostJob.perform_later(id) if status == "scheduled"
    # Problem 1: Fires inside the transaction. Sidekiq picks the job up before commit
    # and the worker SELECTs by id — but the row isn't committed yet → RecordNotFound.
    # Problem 2: Fires on every save (e.g. column touch), not just status transitions.
  end
end
```

**After** (Rails-conventional):

```ruby
class Post < ApplicationRecord
  after_commit :enqueue_publish_job, on: :update, if: :saved_change_to_status?

  private

  def enqueue_publish_job
    PublishPostJob.perform_later(id) if status == "scheduled"
  end
end
```

**Why:**

- `after_save` runs *inside* the transaction. An exception rolls everything back — but external effects (jobs, emails, API calls) already fired and can't be un-sent.
- `after_commit` runs *after* persistence is guaranteed. Use it for `perform_later`, `deliver_later`, file deletion, webhook fanout. Sub-callbacks (`after_create_commit`, `after_update_commit`, `after_destroy_commit`) scope by event.
- `if: :saved_change_to_status?` (Rails 5.1+) limits firing to actual changes.

For full lifecycle order, the four canonical anti-patterns (cross-model writes, validations-in-callbacks, branchy conditional callbacks, `after_save` for jobs), callback objects, and the "callback → service object" refactor, see [`references/callbacks-deep-dive.md`](references/callbacks-deep-dive.md).

### Pattern 8: `counter_cache` (declare + drift fix)

**Before** (AI generates count queries everywhere):

```ruby
# In every view that shows a post:
<%= post.comments.count %>
# SELECT COUNT(*) FROM comments WHERE post_id = ? — once per post in the loop.
```

**After**:

```ruby
class Comment < ApplicationRecord
  belongs_to :post, counter_cache: true
  # Convention: needs an integer column `comments_count` on `posts`.
end
```

Migration (just the column — no inline backfill):

```ruby
class AddCommentsCountToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :comments_count, :integer, null: false, default: 0
  end
end
```

Then a **separate backfill job** (not inline in the migration — see `safe-migrations`):

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

In views, prefer `.size` over the cache column directly — `.size` reads from the cached column when counter_cache is declared, falls back to a query otherwise:

```erb
<%= post.comments.size %>
```

**Drift gotcha + fix:** counter caches only update through ActiveRecord association methods. Raw SQL `INSERT INTO comments` bypasses the cache. Schedule a periodic `reset_counters` job for any model with counter caches that may be touched outside AR:

```ruby
class ResetCommentCountersJob < ApplicationJob
  def perform
    Post.find_each(batch_size: 1000) { |p| Post.reset_counters(p.id, :comments) }
  end
end
```

### Pattern 9: Type variation — polymorphic vs separate-FK vs STI vs `delegated_type`

```
Are subclasses similar attribute-wise?
├─ Yes → STI (e.g. AdminUser < User, GuestUser < User)
└─ No → Are there 2-3 parent types and DB integrity matters?
        ├─ Yes → Separate FK columns + validation + check constraint
        └─ No → delegated_type (Rails 6.1+) or polymorphic (when integrity doesn't matter)
```

**Why polymorphic is the AI default and why it's usually wrong:** `belongs_to :commentable, polymorphic: true` cannot have a foreign key constraint. The DB can't enforce that `commentable_id` points at a real row of `commentable_type`. Orphans accumulate.

**Better, when 2–3 parent types:**

```ruby
class Comment < ApplicationRecord
  belongs_to :post, optional: true
  belongs_to :photo, optional: true
  validate :exactly_one_parent
  # plus a check constraint at the DB level: exactly one FK non-null
end
```

**Better, when many divergent subclasses (Rails 6.1+):**

```ruby
class Entry < ApplicationRecord
  delegated_type :entryable, types: %w[Message Comment Image]
end
# `entries` holds shared cols + entryable_type/id; subclasses get their own narrow tables.
```

**Important:** `delegated_type` does **not** restore DB-level FK integrity. The `entryable_type`/`entryable_id` columns are still polymorphic — no FK constraint can point at multiple tables. The win over a raw polymorphic association is **narrow per-subclass tables** (no NULL-padded columns) and **one query across all types** (`account.entries`), not referential integrity. For integrity, you still need separate FK columns (Option A) or application-level validation.

For full schema, refactor paths, when STI bloats, and the polymorphic-vs-delegated_type decision flow with check-constraint SQL, see [`references/sti-polymorphic-delegated-type.md`](references/sti-polymorphic-delegated-type.md).

### Pattern 10: `dependent:` option

Always specify what happens to children when the parent is destroyed.

| Option | Behavior | Use when |
|---|---|---|
| `:destroy` | Calls `destroy` on each child (fires callbacks) | Children have their own callbacks that must run (audits, cleanup) |
| `:delete_all` | Single SQL DELETE, no callbacks | High-volume children, no cleanup needed (e.g. join tables) |
| `:nullify` | Sets FK to NULL on children | Children should outlive the parent |
| `:restrict_with_error` | Prevents destroy if children exist; adds validation error | Children represent value the user must explicitly handle first |
| `:restrict_with_exception` | Raises `DeleteRestrictionError` if children exist | Same but you want a crash, not a validation message |

```ruby
class Post < ApplicationRecord
  has_many :comments, dependent: :destroy
  has_many :likes, dependent: :delete_all  # 100k likes don't need callbacks
  has_many :scheduled_publishes, dependent: :restrict_with_error
end
```

**Anti-pattern:** Omitting `dependent:`. Default is to do *nothing* — orphan rows accumulate. Always specify.

### Pattern 11: Batch processing — `find_each` over `all.each`

**Before** (loads everything into memory):

```ruby
User.all.each do |user|
  NotificationMailer.daily_digest(user).deliver_later
end
# 500k users → 500k AR objects allocated → OOM.
```

**After**:

```ruby
User.find_each(batch_size: 1000) do |user|
  NotificationMailer.daily_digest(user).deliver_later
end
# Pages through users 1000 at a time. Constant memory.

# Or yield batches as arrays:
User.find_in_batches(batch_size: 5000) do |batch|
  ExportJob.perform_later(batch.map(&:id))
end

# Or use the more composable `in_batches` (yields relations):
User.where(active: true).in_batches(of: 1000) do |relation|
  relation.update_all(notified_at: Time.current)
end
```

**Why:** `find_each` and friends paginate by primary key. Memory stays flat regardless of table size. `in_batches` is the chainable version that yields relations (so you can `update_all` per batch).

### Pattern 12: Fat models with concerns

Once a model exceeds ~200 lines, split with `ActiveSupport::Concern` — keep the *behavior* on the model, just organize the source.

```ruby
# app/models/post.rb (still a fat model — just files broken up)
class Post < ApplicationRecord
  include Searchable
  include Publishable
  include Sluggable

  belongs_to :author
  has_many :comments, dependent: :destroy
end

# app/models/post/searchable.rb (one concern per cohesive behavior cluster)
module Post::Searchable
  extend ActiveSupport::Concern

  included do
    scope :matching, ->(q) { where("title ILIKE ?", "%#{q}%") }
  end

  def search_summary
    "#{title} — #{published_at.to_date}"
  end
end
```

**Why this is preferred over service objects for in-model logic:**

- `post.publish!` reads better than `PostPublisher.new(post).call`.
- The mental model "a Post knows how to publish itself" is closer to the domain than "a publisher knows how to publish a post."
- Concerns split source without splitting *behavior*. The model's public API stays cohesive.

**When to leave the model anyway** (service objects earn their keep):

- Workflow touches 3+ models in one transactional unit.
- Workflow calls an external API.
- Workflow has multiple branching outcomes (success / partial / failure) that need a Result type.

See `service-objects-vs-fat-models` for the full breakdown.

---

## Decision matrix — quick reference

| Question | Default answer |
|---|---|
| Single record, missing means nil? | `find_by(...)` |
| Single record, missing means crash? | `find(id)` (PK) or `find_by!(...)` (attr) |
| First of an ordered set? | Always `.order(...).first` |
| Eager-load without WHERE on association? | `preload(:assoc)` |
| Eager-load with WHERE/ORDER on association? | `eager_load(:assoc)` |
| Don't care, let Rails decide? | `includes(:assoc)` |
| Boolean check? | `Model.exists?(conditions)` |
| Array of values for display/export? | `pluck(...)` |
| Partial model with methods? | `select(...)` |
| Composable filter? | `scope :name, -> { ... }` |
| Filtered children should outlive parent? | `dependent: :nullify` |
| Filtered children must cleanup? | `dependent: :destroy` (or `:delete_all` if no callbacks needed) |
| Polymorphic, with FK integrity needed? | Separate FK columns OR `delegated_type` |
| Subclasses with divergent attributes? | `delegated_type` |
| Side effect needing persistence first? | `after_commit` |
| Loop over a large table? | `find_each(batch_size: …)` |

## Common mistakes to refuse

- Don't write `where(...).first` without `order(...)` — non-deterministic.
- Don't use `count > 0` for boolean checks — use `exists?`.
- Don't write class methods that return `nil` for query composition — use scopes.
- Don't use `default_scope` for soft delete — explicit scope or `discard` gem.
- Don't enqueue jobs / send mail in `after_save` — use `after_commit`.
- Don't omit `dependent:` on `has_many` — pick one explicitly.
- Don't iterate `User.all` over large tables — use `find_each`.
- Don't reach for polymorphic when separate FK columns or `delegated_type` would preserve DB integrity.
- Don't put cross-model writes in callbacks — use service objects or jobs.

## When NOT to use this skill

- Pure association-syntax questions — answer from the guide directly.
- Rails < 6.1 (no `delegated_type`) — fall back to polymorphic + separate-FK.

## See also

- `n-plus-one-killer`, `service-objects-vs-fat-models`, `safe-migrations`, `rspec-testing-pyramid`, `form-objects-query-objects-presenters`

## Sources

- [Rails Guides — Active Record Querying](https://guides.rubyonrails.org/active_record_querying.html)
- [Rails Guides — Associations](https://guides.rubyonrails.org/association_basics.html)
- [Rails Guides — Callbacks](https://guides.rubyonrails.org/active_record_callbacks.html)
- [API — QueryMethods](https://api.rubyonrails.org/classes/ActiveRecord/QueryMethods.html), [DelegatedType](https://api.rubyonrails.org/classes/ActiveRecord/DelegatedType.html), [CounterCache](https://api.rubyonrails.org/classes/ActiveRecord/CounterCache/ClassMethods.html)
- [DHH — Put Chubby Models on a Diet with Concerns](https://signalvnoise.com/posts/3372-put-chubby-models-on-a-diet-with-concerns)
- [discard gem](https://github.com/jhawthorn/discard) — soft-delete alternative
