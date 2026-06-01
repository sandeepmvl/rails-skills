---
name: rails-upgrade-7-to-8
description: Upgrade a Ruby on Rails app from Rails 7.x to Rails 8.0 — dual-boot via next_rails, the deprecation-fix loop, Solid Queue / Solid Cache / Solid Cable adoption choices, Propshaft over Sprockets, the new authentication generator vs existing Devise, Kamal 2 deployment cutover, gem compatibility matrix, the version hop sequence. Use when the user is upgrading Rails to 8, asks about Rails 8 migration, mentions next_rails, dual booting, Gemfile.next, Solid Queue migration, Sprockets to Propshaft, or asks "what changes in Rails 8".
---

# Rails 7 → 8 Upgrade

> Upgrade a Rails 7.x app to Rails 8.0. The hop is smaller than 6→7 but has real choices: Solid Queue vs your existing job backend, Propshaft vs Sprockets, the new authentication generator vs Devise. This skill walks the hop with the dual-boot pattern.

## Why this matters

Rails 8 doesn't break much code. But the new defaults (Solid Queue, Solid Cache, Propshaft, Kamal 2) are *adoptable* — and "adopt all at once" is the wrong move. Stage the adoption.

## The opinion

> **Dual-boot with `next_rails`. Hop 7.x → 7.1 → 7.2 → 8.0 (one minor at a time). Adopt Solid Queue / Cache / Cable only after the version is green — these aren't required by Rails 8, just the default for `rails new`. Keep Sprockets if you have a complex asset pipeline; migrate to Propshaft as a separate project. Skip the built-in `bin/rails generate authentication` if you have Devise.**

Counter-position: a small app on Rails 7.x can do the upgrade in one PR. Dual-boot is for non-trivial apps where breaking master for a week is unacceptable.

## The hop sequence

```
7.0 → 7.1 → 7.2 → 8.0
```

Three Rails minor versions. Never skip — `rails app:update` is per-version diff-aware.

## Core patterns

### Pattern 1: Set up dual-boot with `next_rails`

```ruby
# Gemfile (outside any group)
gem "next_rails", "~> 1.6"

# Existing Rails 7.x:
gem "rails", "~> 7.2.0"
```

```bash
bundle install
bundle exec next --init  # generates Gemfile.next + Gemfile.next.lock
```

```ruby
# Gemfile (after init) — next? is true under BUNDLE_GEMFILE=Gemfile.next
gem "rails", next? ? "~> 8.0.0" : "~> 7.2.0"
# ... continue for any gem with version-specific compatibility
```

Run on the next version:

```bash
BUNDLE_GEMFILE=Gemfile.next bin/rspec
BUNDLE_GEMFILE=Gemfile.next bin/rails server
```

CI runs both Gemfiles in parallel. When the next version is green, swap defaults.

### Pattern 2: 7.x → 7.1 hop

Key changes:
- `Rails.error.report` (the unified error API — see `observability-baseline`).
- Async query API (`load_async`).
- `composed_of` deprecated path; use Attributes API instead.
- `ActiveRecord::Base.with_connection` (was `with_connection`).
- Encrypted attributes get easier — `encrypts :col` is stable.

```bash
# Bump Rails
sed -i '' 's/~> 7.0/~> 7.1/' Gemfile.next
BUNDLE_GEMFILE=Gemfile.next bundle update rails
BUNDLE_GEMFILE=Gemfile.next bin/rails app:update  # review every config diff
BUNDLE_GEMFILE=Gemfile.next bin/rspec
```

**Expect to fix:**
- Deprecation warnings in test output (each one is a future-version breakage).
- Spring / Bootsnap caches stale — `bin/spring stop` and `rm -rf tmp/cache/bootsnap`.
- Gem-version conflicts (any gem pinned to `>= 7.0, < 7.1` needs a bump).

When green, merge the bump to master, then proceed to 7.1 → 7.2.

### Pattern 3: 7.1 → 7.2 hop

Key changes:
- `:polynomially_longer` retry-wait was introduced in **Rails 7.1** (alongside `:exponentially_longer`, which remains as an alias). Audit any custom `retry_on wait:` callers during the 7.1 → 7.2 hop and prefer the new name.
- `puma.rb` config gets `silence_single_worker_warning` option.
- New defaults for cookie security.
- `rails new` starts emitting Devcontainers files (no impact on existing apps unless you run app:update with `--force`).

Same hop dance. App tends to work with minor warnings.

### Pattern 4: 7.2 → 8.0 hop — the real changes

**Required Ruby:** 3.2+ (Rails 8.0 minimum). In 2026 the recommended floor is Ruby 3.3.x for YJIT improvements and bundled gem changes. If you're on 3.1, upgrade Ruby first.

```ruby
# Gemfile
ruby "3.3.7"
gem "rails", "~> 8.0.0"
```

**Default `rails new` stack changes:**
- Asset pipeline: **Propshaft** is the default (existing app keeps Sprockets unless you migrate).
- Job adapter: **Solid Queue** is the default (existing app keeps whatever it had).
- Cache store: **Solid Cache** is the default.
- Cable adapter: **Solid Cable** is the default.
- Auth: `bin/rails generate authentication` ships built-in.

**None of these are required.** Your existing app continues to work with Sprockets + Sidekiq + Memcached + Redis Cable + Devise. The Rails 8 upgrade is purely a Rails version bump.

```bash
sed -i '' 's/~> 7.2/~> 8.0/' Gemfile.next
BUNDLE_GEMFILE=Gemfile.next bundle update rails
BUNDLE_GEMFILE=Gemfile.next bin/rails app:update  # review CAREFULLY
BUNDLE_GEMFILE=Gemfile.next bin/rspec
```

**Fix expectations:**
- A few deprecation warnings (mostly resolved if you cleaned them in 7.1/7.2).
- `config/application.rb` may have new defaults to opt into via `config.load_defaults 8.0`.
- Gem audit: anything depending on Sprockets directly may need `gem "sprockets-rails"` added back.

### Pattern 5: Optional — adopt Solid Queue (after Rails 8 is green)

Separate project, after the version upgrade is in production.

```ruby
# Gemfile (Rails 8 already deployed)
gem "solid_queue"

# Generate config
bin/rails solid_queue:install

# config/environments/production.rb
config.active_job.queue_adapter = :solid_queue

# Drain Sidekiq queues, then cut over.
```

**Decision:** stick with Sidekiq if you have unique-jobs, Pro batches, or sidekiq-throttled in use. Solid Queue doesn't have feature-parity for those. See `solid-queue-and-sidekiq`.

### Pattern 6: Optional — adopt Solid Cache

```ruby
# Gemfile
gem "solid_cache"

bin/rails solid_cache:install

# config/environments/production.rb
config.cache_store = :solid_cache_store
```

Migrate as a deliberate project — invalidates the existing cache. Warm up after deploy.

### Pattern 7: Optional — adopt Propshaft

This is a real migration:

1. Read `references/sprockets-to-propshaft.md` (see `asset-pipeline-propshaft` skill — coming in v0.2).
2. Audit asset pipeline usage: `require` directives, ERB-processed `.scss` files, asset hosts.
3. Most apps need 1-3 days of testing.

If your app is heavy on Sprockets-specific features (e.g. `sass-rails` for ERB-templated SCSS), defer.

### Pattern 8: Optional — Devise vs new authentication generator

The new `bin/rails generate authentication` is for green-fields. Existing Devise users: keep Devise. The generator covers a narrow slice of what Devise does (no confirmable, no lockable, no OmniAuth).

## Decision matrix

| Decision | Default |
|---|---|
| Upgrade strategy | Dual-boot with next_rails, one minor at a time |
| Solid Queue adoption | Defer; separate project; only if no Sidekiq-pro features |
| Solid Cache adoption | Defer; separate project; significant gain over Memcached for most |
| Solid Cable adoption | Defer; only if Redis isn't already in use |
| Propshaft migration | Defer; assess Sprockets-specific usage first |
| Built-in auth generator | Skip; keep Devise |
| Ruby version | Upgrade to 3.3+ before Rails 8 |
| `bin/rails app:update` | Run for every minor hop; review diffs |

## Common mistakes to refuse

- Don't skip Rails minor versions (7.0 → 8.0 in one step). Hop.
- Don't run `bin/rails app:update --force` blindly — it overwrites your config.
- Don't adopt Solid Queue + Solid Cache + Propshaft in the same PR as the version bump.
- Don't upgrade Ruby and Rails in the same PR (different failure modes).
- Don't drop a working Devise install for the new auth generator.

## When NOT to use this skill

- Pre-Rails 7.0 — use the earlier upgrade skills (`rails-upgrade-6-to-7`, etc.).
- Already on Rails 8.0+ — out of scope.

## See also

- `rails-upgrade-6-to-7` — the previous hop
- `solid-queue-and-sidekiq` — Solid Queue adoption choices
- `rails-caching-strategy` — Solid Cache vs Redis
- `asset-pipeline-propshaft` — Propshaft migration
- `kamal-docker-production` — Kamal 2 deployment

## Sources

- [Rails 8 release notes](https://guides.rubyonrails.org/8_0_release_notes.html)
- [Rails 7.2 release notes](https://guides.rubyonrails.org/7_2_release_notes.html)
- [Rails 7.1 release notes](https://guides.rubyonrails.org/7_1_release_notes.html)
- [next_rails README](https://github.com/fastruby/next_rails)
- [Rails upgrade guide](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html)
- [FastRuby — Rails 8 upgrade](https://www.fastruby.io/blog) — case studies
- [Solid Queue migration guide](https://github.com/rails/solid_queue)
