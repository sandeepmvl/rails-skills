---
name: rails-upgrade-5-to-6
description: Upgrade a Ruby on Rails app from 5.x to 6.x — dual-boot via next_rails, Zeitwerk autoloader transition from Classic, Webpacker becoming default, ActionMailbox + ActionText shipping, parallel testing, multi-database support, the version hop sequence. Use when upgrading from Rails 5 to 6, mentions Zeitwerk, autoload paths, Classic to Zeitwerk migration, Webpacker, or asks how to leave Rails 5.
---

# Rails 5 → 6 Upgrade

> The Zeitwerk autoloader transition is the headline event. Most code works; the breakage is autoload-related and unpredictable.

## The opinion

> **Dual-boot with `next_rails`. Hop 5.0 → 5.1 → 5.2 → 6.0 → 6.1. Run Zeitwerk in "check" mode before flipping. Migrate Webpacker if needed (but consider deferring to Rails 7's importmap).**

## The hop sequence

```
5.0 → 5.1 → 5.2 → 6.0 → 6.1
```

## Core patterns

### Pattern 1: 5.x → 5.2 minor hops

Mostly deprecation cleanup. Notable: 5.2 ships Active Storage, encrypted credentials (replaces secrets.yml).

```bash
# Migrate secrets.yml to encrypted credentials
EDITOR=vim bin/rails credentials:edit
# Copy contents of config/secrets.yml.enc into the credentials file
# Update code references: Rails.application.secrets.foo → Rails.application.credentials.foo
```

### Pattern 2: 5.2 → 6.0 — the Zeitwerk transition

**Before flipping:** run in check mode after upgrading the Gemfile to Rails 6.0 but before relying on Zeitwerk in production. Rails 6.0 defaults to Zeitwerk; the legacy "Classic" autoloader is still available as a fallback during the transition.

```ruby
# config/application.rb — opt back into Classic if Zeitwerk:check fails (transitional)
# config.autoloader = :classic   # 6.0 only — removed in 7.0
# Default in 6.0 is :zeitwerk; you do not need to set it.
```

```bash
bin/rails zeitwerk:check
# Reports class names not matching file paths, namespace mismatches, eager-loading failures.
# Fix every one before merging the 6.0 bump.
```

**Common Zeitwerk fixes:**
- `OAuth` class in `oauth.rb` — Zeitwerk expects `o_auth.rb` OR `Zeitwerk::Loader.tag_for(...)`. Use `inflect`:
  ```ruby
  # config/initializers/inflections.rb
  Rails.autoloaders.main.inflector.inflect("oauth" => "OAuth")
  ```
- Single-line `class Foo; end` in a file that should be `Foo::Bar`.
- `require` calls inside autoloaded files — remove; Zeitwerk handles autoload.

### Pattern 3: Webpacker → optional

Rails 6 makes Webpacker the default. If you're on Sprockets and JS is simple: keep Sprockets. If you have a real SPA: adopt Webpacker now, or wait for Rails 7 importmap (often the better answer).

### Pattern 4: 6.0 → 6.1

Multi-DB support shipped. `where.missing`. delegated_type.

Mild hop.

## Common mistakes to refuse

- Don't flip Zeitwerk without `bin/rails zeitwerk:check` passing.
- Don't enable Webpacker because Rails 6 made it default — assess actual JS needs.
- Don't migrate secrets.yml to credentials in the same PR as the version bump.

## See also

- `rails-upgrade-4-to-5` — previous hop
- `rails-upgrade-6-to-7` — next hop

## Sources

- [Rails 6.0 release notes](https://guides.rubyonrails.org/6_0_release_notes.html)
- [Zeitwerk migration guide](https://github.com/fxn/zeitwerk)
- [Rails Guide — Autoloading and Reloading Constants (Zeitwerk Mode)](https://guides.rubyonrails.org/autoloading_and_reloading_constants.html)
- [FastRuby — Zeitwerk migration cases](https://www.fastruby.io/blog)
