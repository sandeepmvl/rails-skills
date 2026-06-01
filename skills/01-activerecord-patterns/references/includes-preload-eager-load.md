# `includes` vs `preload` vs `eager_load` — Deep Dive

> When the one-paragraph summary in SKILL.md isn't enough.

## The three methods and the SQL each produces

### `preload(:author)` — always two queries

```ruby
Post.preload(:author).limit(10)
```

```sql
SELECT * FROM posts LIMIT 10;
SELECT * FROM authors WHERE id IN (1, 4, 7, ...);
```

- Two round-trips, no JOIN.
- Cannot apply `where` conditions to the associated columns — Rails will refuse.
- Best when memory matters and you don't need to filter by the association.

### `eager_load(:author)` — always one query with LEFT OUTER JOIN

```ruby
Post.eager_load(:author).limit(10)
```

```sql
SELECT posts.*, authors.* FROM posts
LEFT OUTER JOIN authors ON authors.id = posts.author_id
LIMIT 10;
```

- One round-trip.
- Can filter / order by associated columns: `eager_load(:author).where(authors: { active: true }).order("authors.name")`.
- Costs more memory in the result set (LEFT OUTER JOIN materializes the cartesian product).
- The `LIMIT 10` applies to the joined rowset — usually still what you want for `has_one`/`belongs_to`. For `has_many` with `LIMIT`, watch out: you can get fewer than 10 parent posts.

### `includes(:author)` — Rails picks

```ruby
Post.includes(:author).limit(10)
```

Rails defaults to `preload`. If you then add `where(authors: ...)` or `order("authors.…")`, Rails escalates to `eager_load` automatically — but only if you also call `.references(:authors)` (Rails 4+ — older versions guessed from string SQL).

```ruby
# Escalates to eager_load:
Post.includes(:author).where(authors: { active: true }).references(:authors)
```

## When `.references()` is required

Whenever you use SQL fragments (string `where("authors.name = ?", "Alice")`) on an included table, you must `.references(:authors)` so Rails knows to JOIN. With hash conditions (`where(authors: { name: "Alice" })`), Rails infers the table name and you can omit it — though being explicit doesn't hurt.

## Nested eager loading

```ruby
Post.includes(author: :profile, comments: [:user, :likes])
```

- Loads posts.
- For each post, loads its author, then each author's profile.
- For each post, loads its comments; for each comment loads user and likes.
- All in separate queries (or one big LEFT OUTER JOIN if Rails escalates).

## Conditional eager loading

```ruby
Post.includes(:author).where("posts.published_at > ?", 1.week.ago)
```

This is safe — the WHERE is on `posts`, not on `authors`. Rails stays with `preload`.

```ruby
Post.includes(:author).where("authors.active = ?", true).references(:authors)
```

This forces escalation to `eager_load` (string condition on associated table requires JOIN).

## The "memory vs round-trips" trade-off

| Scenario | Pick |
|---|---|
| Large parent table, small association table, no filtering | `preload` — two small queries beat one big JOIN |
| Need to filter parents by association values | `eager_load` — must JOIN |
| Polymorphic `has_many` (many associated types) | `preload` — `eager_load` can't JOIN polymorphic targets |
| Default, don't want to think | `includes` — Rails picks |

## Common N+1 patterns and fixes

### N+1 on `has_one`

```ruby
# Bad
User.first(10).each { |u| puts u.profile.bio }  # 1 + 10 queries

# Good
User.preload(:profile).first(10).each { |u| puts u.profile.bio }
# 1 query for users, 1 for profiles
```

### N+1 on `belongs_to`

```ruby
# Bad
Comment.first(50).each { |c| puts c.post.title }

# Good
Comment.preload(:post).first(50).each { |c| puts c.post.title }
```

### N+1 through scoped association

```ruby
class Post < ApplicationRecord
  has_many :recent_comments, -> { order(created_at: :desc).limit(5) }, class_name: "Comment"
end

# preload doesn't honor the scope's LIMIT — you'll still N+1 per post
# Use a window function or per-post query for this case.
```

### N+1 on conditional includes

```ruby
# Bad — includes triggers JOIN, but the WHERE is on parents
Post.includes(:author).where("authors.name = ?", "Alice")
# Without .references, you'll get an "Mysql2::Error: Unknown column 'authors.name'" type failure.

# Good
Post.includes(:author).where("authors.name = ?", "Alice").references(:authors)

# Better — let hash conditions infer
Post.includes(:author).where(authors: { name: "Alice" })
```

## Anti-patterns

- `Post.all.each { |p| p.author.name }` — classic N+1 with no eager loading.
- `Post.includes(:author).map { |p| p.author.name }.compact` — fine, but you wanted `pluck("authors.name")` if all you need is names.
- `Post.eager_load(:comments).limit(10)` where `comments` is `has_many` — this LIMITs the joined rowset, not the parent count. You'll get fewer than 10 posts. Use `preload` for `has_many` with `limit`.

## See also

- `n-plus-one-killer` — detection tooling (Bullet, prosopite)
- `references/query-explained.md` in `n-plus-one-killer` for EXPLAIN ANALYZE for Rails devs
