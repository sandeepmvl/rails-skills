---
name: rails-upgrade-6-to-7
description: Upgrade a Ruby on Rails app from 6.x to 7.x — dual-boot via next_rails, the Zeitwerk autoloader transition (was already in 6.0 but became mandatory), Sprockets-to-importmap or jsbundling decision, Hotwire arriving, encrypted attributes via Active Record Encryption (7.0+), the version hop sequence. Use when the user is upgrading from Rails 6 to 7, mentions Zeitwerk, Webpacker removal, importmap-rails, Hotwire migration, encrypted attributes, or asks how to get off Rails 6.
---

# Rails 6 → 7 Upgrade

> Bigger hop than 7→8. Webpacker is gone. Zeitwerk autoloader is mandatory. Hotwire arrives. Treat it as a multi-week project for a non-trivial app.

## The opinion

> **Dual-boot with `next_rails`. Hop 6.0 → 6.1 → 7.0 → 7.1. Migrate off Webpacker as a separate project before or after — never inline with the version bump. Choose importmap-rails (default) or jsbundling-rails based on app size. Adopt Hotwire (Turbo+Stimulus) gradually if you have a heavy jQuery legacy.**

## The hop sequence

```
6.0 → 6.1 → 7.0 → 7.1
```

## Core patterns

### Pattern 1: 6.0 → 6.1

**Key changes:**
- Multi-DB support (`connects_to`).
- Stricter `enum` semantics.
- `where.missing(:assoc)` shortcut.
- `delegated_type` shipped.

Hop, fix deprecations, ship.

### Pattern 2: 6.1 → 7.0 — the big one

**Required:**
- Ruby 2.7+.
- Zeitwerk autoloader (was already in 6.0 as default — but 7.0 removes Classic).

**Breaking-ish:**
- Webpacker deprecated; replaced by importmap-rails or jsbundling-rails (esbuild / rollup / webpack still available).
- spring-watcher-listen removed.
- ActiveRecord Encryption ships (`encrypts :col`).

**Webpacker decision matrix:**

| App | Pick |
|---|---|
| Server-rendered Rails + sprinkle of JS | importmap-rails (no Node build) |
| React/Vue SPA mixed in | jsbundling-rails with esbuild |
| Heavy CSS preprocessing | cssbundling-rails |
| Legacy Webpacker app, can't migrate yet | shakapacker (community fork) |

```ruby
# Migrating from Webpacker (illustrative — full migration is its own skill)
# 1. Remove Webpacker, add importmap-rails
gem "importmap-rails"

# 2. bin/rails importmap:install
# 3. Move app/javascript/packs/* → app/javascript/*
# 4. Update layouts: <%= javascript_importmap_tags %>
# 5. Remove webpacker files, bin/webpack, etc.
```

### Pattern 3: 7.0 → 7.1

**Key changes:**
- `Rails.error.report` arrives.
- `async_count`, `load_async`.
- Trilogy gem for MySQL.
- `composed_of` deprecated; use Attributes API.

Mild hop; mostly deprecation cleanup.

### Pattern 4: Hotwire adoption

Rails 7.0 ships Hotwire (`turbo-rails`, `stimulus-rails`) by default for new apps. Existing app gets it via:

```bash
bin/rails turbo:install
bin/rails stimulus:install
```

**Don't rewrite all your jQuery in one PR.** Adopt incrementally: new pages use Turbo Frames; old pages keep jQuery until you have a reason to touch them. See `hotwire-turbo-stimulus`.

## Common mistakes to refuse

- Don't migrate Webpacker → importmap as part of the version bump. Separate project.
- Don't enable Zeitwerk + Rails 7 + Hotwire in the same PR. Stage them.
- Don't skip Rails 6.1.

## See also

- `rails-upgrade-7-to-8` — next hop
- `rails-upgrade-5-to-6` — previous hop
- `hotwire-turbo-stimulus`
- `asset-pipeline-propshaft`

## Sources

- [Rails 7.0 release notes](https://guides.rubyonrails.org/7_0_release_notes.html)
- [Rails 6.1 release notes](https://guides.rubyonrails.org/6_1_release_notes.html)
- [Webpacker → importmap migration](https://github.com/rails/jsbundling-rails)
- [importmap-rails README](https://github.com/rails/importmap-rails)
- [Hotwire intro for Rails 6 → 7 migrations](https://hotwired.dev/)
- [FastRuby Rails 7 upgrade case studies](https://www.fastruby.io/blog)
