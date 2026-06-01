# Evals for `activerecord-patterns`

> Realistic prompts a Rails dev would type. Skill output must satisfy the rubric for each.

## Prompt 1: Slow index page

**User prompt:**
> The blog index page loads slow. Here's the controller:
>
> ```ruby
> class PostsController < ApplicationController
>   def index
>     @posts = Post.order(created_at: :desc).limit(20)
>   end
> end
> ```
>
> And the template renders `<%= post.author.name %>` and `<%= post.comments.count %>` per post. Help.

**Expected behavior:**
- Identifies the N+1 on `post.author` and the count query on `post.comments`.
- Adds `includes(:author)` to fix the author N+1.
- Recommends a `counter_cache` for `comments_count` so the per-post count doesn't query.
- Mentions the backfill: `Post.find_each { |p| Post.reset_counters(p.id, :comments) }` after adding the column.
- Does NOT recommend caching the view as the first answer — fix the query first.

**Rubric:**
- [ ] Diagnosed N+1 on author
- [ ] Diagnosed count-query problem on comments
- [ ] Used `includes(:author)` not `eager_load` (no WHERE on associated)
- [ ] Counter cache solution with backfill mentioned
- [ ] Did not jump to fragment caching as primary fix

---

## Prompt 2: "Find the user by email"

**User prompt:**
> I want to look up a user by email and return nil if not found. Right way?

**Expected behavior:**
- Recommends `User.find_by(email: e)`.
- Mentions `find_by!` for the crash-if-missing case.
- Mentions `find_by(email: e)` vs `where(email: e).first` — explains the latter is non-deterministic without `.order(...)` if emails are non-unique (or just less idiomatic if unique).

**Rubric:**
- [ ] `find_by` chosen
- [ ] `find_by!` mentioned for crash variant
- [ ] Didn't suggest `where(email: e).first`

---

## Prompt 3: Callback bug — job fires before commit

**User prompt:**
> My `PublishPostJob` is failing with `ActiveRecord::RecordNotFound`. The model has:
>
> ```ruby
> class Post < ApplicationRecord
>   after_save :enqueue_publish_job
>
>   def enqueue_publish_job
>     PublishPostJob.perform_later(id) if scheduled?
>   end
> end
> ```

**Expected behavior:**
- Identifies the race: `after_save` fires inside the transaction; Sidekiq picks up the job before commit; the worker SELECT fails because the row isn't committed.
- Recommends `after_commit on: :update, if: :saved_change_to_scheduled?` (or similar predicate).
- Notes the double-fire problem on every save without a change-predicate.

**Rubric:**
- [ ] Identified pre-commit race
- [ ] Switched to `after_commit`
- [ ] Added change-predicate to avoid spurious re-enqueues

---

## Prompt 4: Scope vs class method

**User prompt:**
> Should I use a scope or a class method for `Post.published_before(time)`?

**Expected behavior:**
- Recommends scope.
- Specifically demonstrates the nil-return foot-gun of class methods (chainability breaks).
- Shows the scope returning `Post.all` when the conditional is false.

**Rubric:**
- [ ] Recommended scope
- [ ] Showed the nil-return failure of class methods
- [ ] Noted scopes return Relation even when conditional is false

---

## Prompt 5: Soft delete

**User prompt:**
> I want to soft-delete posts. Add a `deleted_at` column and hide deleted ones from queries.

**Expected behavior:**
- Does NOT recommend `default_scope { where(deleted_at: nil) }` as the solution.
- Recommends an explicit `scope :active` plus the `discard` gem (or `paranoia`).
- Explains the default_scope foot-gun: invisible WHERE on every query, including associations and `.find`.

**Rubric:**
- [ ] Refused `default_scope` approach
- [ ] Recommended explicit scope or `discard`/`paranoia` gem
- [ ] Explained why default_scope is the wrong tool

---

## Prompt 6: STI for content types

**User prompt:**
> I have Article, Quote, and Photo. Article has body + hero. Quote has quote_text + attribution. Photo has s3_key + dimensions + exif. Should I use STI?

**Expected behavior:**
- Recommends `delegated_type` (Rails 6.1+) — subclasses diverge in attributes.
- Shows the schema: narrow `posts` table + separate `articles`, `quotes`, `photos` tables.
- Explains STI bloats one table with null-padded columns when subclasses diverge.

**Rubric:**
- [ ] Recommended delegated_type
- [ ] Identified that subclasses diverge in attributes
- [ ] Did not recommend STI

---

## Prompt 7: Polymorphic Comment

**User prompt:**
> I want comments on both Posts and Photos. Use polymorphic?

**Expected behavior:**
- Asks how many parent types are expected and whether DB-level integrity matters.
- If 2-3 types and integrity matters: recommends separate FK columns with a validation enforcing exactly one parent.
- If many types with divergent attributes: recommends `delegated_type` on the parent side.
- Only recommends polymorphic when integrity isn't a concern (e.g. taggings).

**Rubric:**
- [ ] Surfaced the FK-integrity loss of polymorphic
- [ ] Offered separate-FK alternative
- [ ] Mentioned delegated_type for many-type case

---

## Prompt 8: Large-table iteration

**User prompt:**
> I need to send a daily email to every user. `User.all.each` is OOMing.

**Expected behavior:**
- Recommends `User.find_each(batch_size: 1000)`.
- Explains memory bound: constant per batch, not proportional to table size.
- Uses `deliver_later` not `deliver_now` (in-transaction email is wrong even outside this skill — but `actionmailer-baseline` covers that).

**Rubric:**
- [ ] Replaced `all.each` with `find_each`
- [ ] Explained memory characteristics
- [ ] Did not suggest `each` on a relation
