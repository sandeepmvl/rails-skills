# STI vs Polymorphic vs `delegated_type` — Deep Dive

> When the table in SKILL.md isn't enough. Covers each pattern's schema, when it's right, and the concrete refactor path between them.

## Polymorphic associations

### The default that loses DB integrity

```ruby
class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
end
```

Schema:
```
comments:
  id              bigint
  commentable_type varchar  # "Post" or "Photo"
  commentable_id   bigint
```

**Problem:** No way to add a foreign key constraint. The database cannot enforce that `commentable_id = 42` actually points to a row of `commentable_type = "Post"`. Orphans accumulate. Type and id can disagree (e.g. after a refactor that renamed `Post` to `Article`).

### Option A — separate FK columns (2–3 parent types, DB integrity matters)

```ruby
class Comment < ApplicationRecord
  belongs_to :post, optional: true
  belongs_to :photo, optional: true

  validate :exactly_one_parent

  scope :for_post,  ->(post)  { where(post_id: post.id) }
  scope :for_photo, ->(photo) { where(photo_id: photo.id) }

  private

  def exactly_one_parent
    return if [post_id, photo_id].compact.length == 1
    errors.add(:base, "must belong to exactly one of post or photo")
  end
end
```

Migration:
```ruby
class CreateComments < ActiveRecord::Migration[8.0]
  def change
    create_table :comments do |t|
      t.references :post,  foreign_key: true
      t.references :photo, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end
    add_check_constraint :comments,
      "(post_id IS NOT NULL)::int + (photo_id IS NOT NULL)::int = 1",
      name: "comments_exactly_one_parent"
  end
end
```

- FK constraints prevent orphans.
- Check constraint enforces "exactly one parent" at the DB level.
- Querying is straightforward: `post.comments`, `photo.comments`.

**When this stops scaling:** Adding a 5th and 6th parent type means 5–6 nullable FK columns. At that point, switch to delegated type.

### Option B — `delegated_type` (many parent types, divergent attributes)

See the `delegated_type` section below.

### When polymorphic is actually fine

Polymorphic `belongs_to` is the right tool when:
- The "parent" is genuinely a tagging-like relationship (any model can be tagged).
- DB-level integrity isn't required (orphans are tolerable or cleaned up by background jobs).
- The number of parent types is unbounded or grows often.

Example: ActsAsTaggable-style tagging. Activity feed entries pointing at arbitrary models. Pre-aggregated comment counts that don't need to be authoritative.

## Single Table Inheritance (STI)

### When it fits

Subclasses share ~all attributes and differ only in behavior or in a few flags.

```ruby
class User < ApplicationRecord
  # columns: id, email, password_digest, role, type, created_at, updated_at
end

class AdminUser < User
  def can_manage_billing?
    true
  end
end

class GuestUser < User
  def can_manage_billing?
    false
  end
end
```

`users` table has a `type` column (string). `AdminUser.all` issues `WHERE type = 'AdminUser'`. Same table, same columns, just different behavior in Ruby.

### When STI bloats the table

```ruby
class Post < ApplicationRecord; end
class Article < Post; end   # body:text, hero_image:string
class Quote < Post; end     # quote_text:text, attribution:string
class Photo < Post; end     # s3_key:string, dimensions:string, exif_data:jsonb
```

The `posts` table now has every column from every subclass. Each row is null-padded for the columns that don't apply. A `Photo` row has NULL for `body`, `hero_image`, `quote_text`, `attribution`. A `Quote` row has NULL for `s3_key`, `dimensions`, `exif_data`.

This is the STI smell. Switch to `delegated_type`.

### STI gotchas

- `type` is a reserved column name. Don't use it for anything else.
- Renaming a subclass breaks every existing row (`type = "OldName"` no longer resolves). Migrate the column data with the rename.
- `Post.find(id)` returns the right subclass, but `Post.new` doesn't — it returns the base class. Use `Article.new` directly.
- Polymorphic associations with STI parents are confusing — the type column stores the subclass name, but FK constraints can't cover all subclasses. Test carefully.

## `delegated_type` (Rails 6.1+)

### Schema

```
entries:
  id                bigint
  account_id        bigint
  entryable_type    varchar  # "Message", "Comment", "Image"
  entryable_id      bigint
  created_at, updated_at

messages:
  id, subject, body, ...

comments:
  id, body, author_id, ...

images:
  id, s3_key, alt_text, exif_data, ...
```

The `entries` table holds shared attributes (and the type+id pointer). Each subclass has its own table with only its specific attributes.

### Setup

```ruby
class Entry < ApplicationRecord
  belongs_to :account
  delegated_type :entryable, types: %w[Message Comment Image], dependent: :destroy
end

module Entryable
  extend ActiveSupport::Concern
  included do
    has_one :entry, as: :entryable, touch: true
    delegate :account, to: :entry
  end
end

class Message < ApplicationRecord
  include Entryable
end

class Comment < ApplicationRecord
  include Entryable
end

class Image < ApplicationRecord
  include Entryable
end
```

### Querying

```ruby
# Get every entry, regardless of type:
account.entries.order(created_at: :desc).limit(20)
#   SELECT * FROM entries WHERE account_id = ? ORDER BY created_at DESC LIMIT 20

# Get just the messages:
account.entries.where(entryable_type: "Message")

# Iterate with polymorphic dispatch:
account.entries.each do |entry|
  case entry.entryable
  when Message then render_message(entry.entryable)
  when Image   then render_image(entry.entryable)
  end
end

# Or use predicate methods Rails generates:
entry.message?  # => true if entryable_type == "Message"
entry.image?    # => true if entryable_type == "Image"
```

### When delegated_type wins over STI

- Subclasses have divergent attributes.
- You want a single query across types (`account.entries.order(:created_at)` covers all entry types).
- You don't want NULL columns for unrelated attributes.

### When delegated_type wins over separate-FK polymorphic

- More than ~3 parent types.
- Want one query to get a feed/timeline across all types.
- Shared attributes (account, created_at, position) should live in one place.

## Decision flow

```
Are subclasses similar attribute-wise?
├─ Yes → STI
└─ No → Are there 2-3 parent types and DB integrity matters?
        ├─ Yes → Separate FK columns + validation + check constraint
        └─ No → delegated_type (Rails 6.1+) or polymorphic (when integrity doesn't matter)
```

## Refactor: STI → delegated_type

When an STI table has bloated:

1. Create new tables for each subclass with only its specific attributes.
2. Add `entryable_type`, `entryable_id` to the parent table.
3. Backfill: for each existing row, copy subclass-specific columns to the new subclass table; set `entryable_type` and `entryable_id` on the parent.
4. Remove the old subclass-specific columns from the parent table (separate deploy after backfill).
5. Switch model definitions from STI to `delegated_type`.
6. Drop the `type` column from the parent.

Use `safe-migrations` patterns for each step — this is a multi-deploy change.

## See also

- `service-objects-vs-fat-models` — when subclass behavior is better expressed as a strategy/service
- `safe-migrations` — for the multi-step refactor
- [Rails Guides — Associations](https://guides.rubyonrails.org/association_basics.html#polymorphic-associations)
- [Rails Guides — Inheritance](https://guides.rubyonrails.org/association_basics.html#single-table-inheritance-sti)
- [API — ActiveRecord::DelegatedType](https://api.rubyonrails.org/classes/ActiveRecord/DelegatedType.html)
