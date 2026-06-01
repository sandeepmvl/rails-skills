# ActiveRecord Callbacks — Deep Dive

> When the one-paragraph summary in SKILL.md isn't enough. Covers the full lifecycle, transactional callbacks, callback objects, and the canonical "callback → service object" refactor.

## Full callback lifecycle

### Creating a record

1. `before_validation`
2. `after_validation` (only if validation passed)
3. `before_save`
4. `around_save` (yield triggers create)
5. `before_create`
6. `around_create` (yield triggers DB INSERT)
7. INSERT issued
8. `after_create`
9. `after_save`
10. `after_commit` *or* `after_rollback` (depending on transaction outcome)

### Updating a record

Same as create but `before_create` / `after_create` are replaced by `before_update` / `after_update`. `before_save` and `after_save` fire for both create and update.

### Destroying a record

1. `before_destroy`
2. `around_destroy` (yield triggers DELETE)
3. DELETE issued
4. `after_destroy`
5. `after_commit` *or* `after_rollback`

## `after_save` vs `after_commit` — pick `after_commit` for side effects

```ruby
class Post < ApplicationRecord
  after_save :send_notification        # WRONG for external effects
  after_commit :send_notification      # RIGHT for external effects
end
```

- `after_save` fires *inside* the transaction. If an exception happens later in the transaction, the row is never written but the callback already fired. External side effects (mail, jobs, third-party API calls) have already gone out — you cannot un-send them.
- `after_commit` fires *after* commit. The row is durable. Side effects are safe.

### Sub-callbacks: `after_create_commit`, `after_update_commit`, `after_destroy_commit`, `after_save_commit`

Rails provides shortcut callbacks that scope `after_commit` to one event:

```ruby
class Post < ApplicationRecord
  after_create_commit  :send_welcome_mail
  after_update_commit  :enqueue_reindex
  after_destroy_commit :purge_files
  after_save_commit    :notify_subscribers  # both create and update
end
```

Prefer these over `after_commit on: :create` for readability.

## Conditional callbacks

```ruby
class Post < ApplicationRecord
  after_update_commit :reindex, if: :saved_change_to_title?
end
```

`saved_change_to_<attr>?` (Rails 5.1+) is true only when that column actually changed in the current save. Use it to avoid re-firing on unrelated saves (a `touch`, a counter cache update, an unrelated attribute change).

For older Rails, use `previous_changes` or `_was` methods (the API has shifted; check your version).

## Callback objects (when a model has many callbacks)

For models with several callbacks, extract them into a class to keep the model thin:

```ruby
# app/models/concerns/post_callbacks.rb
class PostCallbacks
  def after_commit(post)
    Notifier.publish(post)
  end

  def after_destroy(post)
    SearchIndex.remove(post.id)
  end
end

class Post < ApplicationRecord
  after_commit  PostCallbacks.new
  after_destroy PostCallbacks.new
end
```

The class can hold state (less common) or just group callbacks (more common). Cuts model line count without changing semantics.

## When callbacks become anti-patterns

### Anti-pattern 1: Cross-model writes

```ruby
class Order < ApplicationRecord
  after_create :decrement_inventory

  private

  def decrement_inventory
    line_items.each { |li| li.product.update!(stock: li.product.stock - li.quantity) }
  end
end
```

Problems:
- Each `update!` issues its own callback chain — can recurse.
- If a product update fails mid-loop, partial inventory decrement is committed.
- The behavior "creating an order changes product stock" is invisible from `Product`'s perspective — readers of `product.rb` won't find it.

**Refactor to a service object:**

```ruby
class PlaceOrderService
  def call(cart:, user:)
    ActiveRecord::Base.transaction do
      order = user.orders.create!(...)
      cart.items.each do |item|
        item.product.lock!
        item.product.update!(stock: item.product.stock - item.quantity)
      end
      order
    end
  end
end
```

See `service-objects-vs-fat-models` for the full pattern.

### Anti-pattern 2: Conditional callbacks with branchy logic

```ruby
class Subscription < ApplicationRecord
  after_save :sync_to_stripe, if: -> { active? && !canceled? && Rails.env.production? && !skip_stripe_sync }
end
```

Pull the condition into a named method:

```ruby
class Subscription < ApplicationRecord
  after_save :sync_to_stripe, if: :should_sync_to_stripe?

  private

  def should_sync_to_stripe?
    active? && !canceled? && Rails.env.production? && !skip_stripe_sync
  end
end
```

Better still: ask whether the sync belongs on the model at all. A `StripeSyncService.call(subscription)` invoked explicitly from the controller is often cleaner.

### Anti-pattern 3: Enqueuing jobs from `after_save`

```ruby
# WRONG — job picked up by worker before commit
after_save :enqueue_indexing_job

def enqueue_indexing_job
  IndexJob.perform_later(id)
end
```

```ruby
# RIGHT
after_commit :enqueue_indexing_job, on: %i[create update]
```

The worker's `Model.find(id)` raises `RecordNotFound` if the row isn't committed yet. `after_commit` guarantees commit-then-enqueue.

### Anti-pattern 4: Validations in callbacks

```ruby
# WRONG
before_save :check_user_quota
def check_user_quota
  raise "Quota exceeded" if user.posts.count >= 100
end
```

```ruby
# RIGHT — use validates
validate :user_under_quota
def user_under_quota
  errors.add(:base, "Quota exceeded") if user&.posts&.count.to_i >= 100
end
```

Validations produce structured errors that the form layer can render. Raises in callbacks crash the request.

## Skipping callbacks (when you must)

- `update_column(s)` — skips validations AND callbacks.
- `update_columns` — same, multiple columns.
- `decrement!` / `increment!` (without args) skip callbacks.
- `touch` skips most callbacks (still fires `after_touch`).
- `delete` (vs `destroy`) skips callbacks AND associations' `dependent:`.

**Use these sparingly.** Skipping callbacks is technical debt — every reader has to remember "this path is different."

## See also

- `service-objects-vs-fat-models` — when to leave the model entirely
- `solid-queue-and-sidekiq` — idempotent jobs (which is what `after_commit :enqueue_…` requires)
- [Rails Guides — Active Record Callbacks](https://guides.rubyonrails.org/active_record_callbacks.html)
