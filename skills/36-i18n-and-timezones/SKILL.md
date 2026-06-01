---
name: i18n-and-timezones
description: Internationalization and time zones in Rails 8 — I18n keys for translations, locale fallbacks, lazy lookup in views, locale switching per-request, the rails-i18n gem, time zone storage strategy (UTC in DB, display in user's zone), Time.zone vs Time.current vs Time.now, time_in_zone, daylight saving traps. Use when the user mentions I18n, locales, translations, t() helper, Time.zone, Time.current, time zone, DST, multi-language, or asks how to localize a Rails app.
---

# I18n + Time Zones

> Two related areas Rails handles well by default but AI agents botch consistently. Strings get hardcoded. `Time.now` returns server-local instead of UTC. DST changes break appointment booking. This skill encodes the defaults that prevent each class of bug.

## The opinion

> **Externalize every user-visible string via `t()`. Use the rails-i18n gem for built-in locales (date formats, currency, validation messages). Store all times as UTC in the database (Rails default). Use `Time.current` / `Time.zone.now`, never `Time.now`. Set `Time.zone` per-request based on user preference. Use the `time_in_zone` helper for display. Test DST transitions explicitly.**

## Core patterns

### Pattern 1: Externalize strings

```yaml
# config/locales/en.yml
en:
  greetings:
    welcome: "Welcome, %{name}!"
    farewell: "See you soon."
  posts:
    index:
      title: "All Posts"
      new: "New Post"
      filter:
        all: "All"
        drafts: "Drafts only"
```

```erb
<h1><%= t(".title") %></h1>           <!-- Lazy lookup: app/views/posts/index → t("posts.index.title") -->
<%= link_to t(".new"), new_post_path %>
<%= t("greetings.welcome", name: current_user.name) %>
```

**Lazy lookup** (`t(".title")`) — Rails infers the namespace from the view path. Way less repetitive than full `t("posts.index.title")` in every line.

### Pattern 2: Locale fallbacks

```ruby
# config/application.rb
config.i18n.available_locales = %i[en fr de ja]
config.i18n.default_locale = :en
config.i18n.fallbacks = [I18n.default_locale]   # or true for chain fallback
config.i18n.fallbacks.map = { fr: :en, de: :en, ja: :en }  # explicit per-locale
```

```ruby
# config/initializers/i18n.rb — enable Fallbacks backend (required for `fallbacks.map`)
require "i18n/backend/fallbacks"
I18n::Backend::Simple.include I18n::Backend::Fallbacks
```

Missing French translation → falls back to English. Never falls back to a missing key (`translation missing` placeholder).

For production, use `config.i18n.raise_on_missing_translations = true` in test env to fail specs that reference missing keys.

### Pattern 3: rails-i18n gem

```ruby
# Gemfile
gem "rails-i18n"  # locale data for 100+ languages
```

Provides:
- Validation error messages in every locale.
- Date / time / number format defaults per locale.
- Pluralization rules (Russian's 6 plural forms, Arabic's 6, etc.).

Just add to Gemfile. Rails picks it up.

### Pattern 4: Per-request locale

```ruby
class ApplicationController < ActionController::Base
  around_action :switch_locale

  private

  def switch_locale(&action)
    locale = params[:locale] || current_user&.locale || extract_locale_from_accept_language_header || I18n.default_locale
    I18n.with_locale(locale, &action)
  end

  def extract_locale_from_accept_language_header
    header = request.env["HTTP_ACCEPT_LANGUAGE"]
    return nil if header.blank?

    # "en-US,en;q=0.9,fr;q=0.8" → ["en", "fr"]
    accepted = header.split(",").map { |tag| tag.split(";").first.to_s.strip[0, 2].downcase }
    accepted.find { |l| I18n.available_locales.map(&:to_s).include?(l) }&.to_sym
  end
end
```

`I18n.with_locale(locale) { ... }` — scopes the locale change to the block, no leakage.

### Pattern 5: Time zones — storage vs display

**Storage:** always UTC. Rails defaults to this. Don't change it.

```ruby
# config/application.rb
config.time_zone = "UTC"             # default; do not change
config.active_record.default_timezone = :utc  # DB timezone
```

**Display:** user's preferred zone.

```ruby
class ApplicationController < ActionController::Base
  around_action :set_time_zone

  private

  def set_time_zone(&action)
    Time.use_zone(current_user&.time_zone || "UTC", &action)
  end
end
```

In views:

```erb
<%= @post.published_at %>             <!-- UTC time, formatted in current Time.zone -->
<%= l(@post.published_at, format: :long) %>  <!-- Localized format -->
```

### Pattern 6: `Time.now` is wrong; `Time.current` is right

```ruby
Time.now              # Ruby's local time — server's TZ. Don't use.
Time.zone.now         # Current time in Rails' Time.zone (UTC default, or per-request)
Time.current          # Alias for Time.zone.now. Use this.
Date.today            # Ruby's local date. Don't use.
Date.current          # Current date in Time.zone. Use this.
```

**Why it matters:** if your server is configured to a different timezone than `Time.zone` (or you SSH into a server in production and run `Time.now`), the values diverge. Always `Time.current` and `Date.current`.

### Pattern 7: `time_in_zone` for explicit conversion

```ruby
created_at = Time.current  # UTC by default
created_at.in_time_zone("America/New_York")  # → 2026-05-24 06:00:00 -0400
created_at.in_time_zone("Asia/Tokyo")        # → 2026-05-24 19:00:00 +0900
```

For display: `time_in_zone` (alias for `in_time_zone`) gives a TimeWithZone object. `strftime` on it formats in the target zone.

### Pattern 8: DST gotchas

```ruby
# 2026-03-08, US clocks spring forward at 02:00 → 03:00
appt = Time.zone.parse("2026-03-08 02:30")  # ambiguous — doesn't exist!
# Returns 2026-03-08 03:30 in TZ-aware mode (Rails normalizes).

# 2026-11-01, US clocks fall back at 02:00 → 01:00
appt = Time.zone.parse("2026-11-01 01:30")  # also ambiguous — appears twice
```

**Mitigations:**
- For appointment booking apps: refuse to book between 2:00 and 3:00 on DST transition days.
- For recurring schedules: store the user's local "wall clock" intent (`every Monday at 9:00 in America/New_York`), compute the UTC time per occurrence.
- Use `Time.zone.parse` (TZ-aware) over `Time.parse` (TZ-ignorant).

### Pattern 9: Date math respects zone

```ruby
# Wrong on DST days:
Time.current.beginning_of_day + 24.hours  # may not be next-day start

# Right:
Time.current.tomorrow.beginning_of_day
```

`24.hours` is exactly 86400 seconds — never DST-aware. `1.day` IS DST-aware ("same wall-clock time tomorrow") only when applied to a `TimeWithZone` (e.g. `Time.current.tomorrow`, `Time.zone.now + 1.day`). On a bare `Time` (`Time.now + 1.day`), it's still 86400 seconds. Always start from `Time.current` / `Time.zone.now`.

### Pattern 10: Number / currency formatting

```ruby
number_to_currency(1234.5)  # "$1,234.50" in :en; "1 234,50 €" in :fr
number_with_delimiter(1234567)  # "1,234,567" or "1.234.567" depending on locale
l(Date.current, format: :long)  # "May 24, 2026" or "24 mai 2026"
```

rails-i18n provides the formats per-locale. Set `config.i18n.default_locale` and start using.

## Common mistakes to refuse

- Don't hardcode strings in views or models.
- Don't use `Time.now` or `Date.today` in app code. Always `Time.current` / `Date.current`.
- Don't store wall-clock times as if they were UTC. Always convert to UTC for storage.
- Don't add hours to a Time and expect DST safety. Use `1.day` / `1.week` / `1.month`.
- Don't assume server timezone == user timezone.
- Don't translate column names in the database — translation belongs in code.
- Don't hand-roll pluralization. Use I18n's `count:` interpolation.

## When NOT to use this skill

- Single-locale app with no plans to add more: still externalize for testability, but skip the locale-switching machinery.
- The user is doing complex calendar / recurring event logic — recommend the `ice_cube` gem.

## See also

- `actionmailer-baseline` — I18n.with_locale per recipient
- `safe-migrations` — backfilling localized columns

## Sources

- [Rails Guides — I18n](https://guides.rubyonrails.org/i18n.html)
- [rails-i18n gem](https://github.com/svenfuchs/rails-i18n)
- [Rails Time API](https://api.rubyonrails.org/classes/Time.html)
- [TZInfo (Rails uses)](https://tzinfo.github.io/)
- [DST handling — Rails internals](https://api.rubyonrails.org/classes/ActiveSupport/TimeZone.html)
- [ice_cube (recurring events)](https://github.com/seejohnrun/ice_cube)
