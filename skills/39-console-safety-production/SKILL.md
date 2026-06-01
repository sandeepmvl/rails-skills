---
name: console-safety-production
description: Production console safety in Rails 8 — the production console warning, sandbox mode, read-only consoles, audit logging of console sessions, scrubbing PII, dangerous methods to never run (update_all, delete_all, truncate, raw SQL DELETE/UPDATE without WHERE), the staged-production-console pattern, replacing console with rake tasks. Use when the user mentions production console, rails c, console safety, sandbox, web-console, rails db, dangerous Rails commands, scrubbing data, or asks how to safely operate a production Rails app.
---

# Console Safety in Production

> The production Rails console is a foot-gun. `User.update_all(admin: true)` runs in 0.2 seconds. There is no undo. This skill encodes the habits, gates, and alternatives that keep production console operations safe.

## The opinion

> **Avoid the production console for routine work — write a rake task or a script-as-PR. When you must use it, default to read-only mode. Use `rails console --sandbox` for any state-changing exploration. Enable Rails 7.2+ production console warning. Log every session. Never run `update_all` / `delete_all` / `truncate` / raw SQL DML in console.**

Why it matters: most "production outage caused by a 1-line typo" incidents trace back to console usage. The console gives you full ActiveRecord power with zero review, zero tests, zero rollback.

## Pattern 1: Production console warning (Rails 7.2+)

Rails 7.2 shipped the production console warning by default. IRB renders a prominent prompt with the environment name when launched against production, e.g.:

```
Loading production environment (Rails 8.0.0)
production> User.first
```

The prompt label and color are controlled by IRB itself, not by a Rails config flag — there's no `config.console_environment_color`. Customize via `~/.irbrc` if you want a different prompt:

```ruby
# ~/.irbrc — applies to your shell, not the app
IRB.conf[:PROMPT][:PRODUCTION] = {
  PROMPT_I: "\e[31mproduction>\e[0m ",
  PROMPT_S: "\e[31mproduction*\e[0m ",
  PROMPT_C: "\e[31mproduction?\e[0m ",
  RETURN:   "=> %s\n"
}
```

## Pattern 2: Sandbox mode

```bash
bin/rails console --sandbox
```

```
Loading production environment in sandbox (Rails 8.0.0)
Any modifications you make will be rolled back on exit
```

All DB writes wrap in a transaction that rolls back on exit. The default for exploratory work in production.

**Gotcha:** sandbox does NOT roll back:
- Files written to disk
- API calls
- Email sends
- Background jobs enqueued via Sidekiq (writes to Redis — does NOT roll back). Solid Queue persists to your DB, so NEW enqueues from within the sandbox roll back with the transaction. But jobs already picked up by workers during the sandbox session run normally and are unaffected.
- Cache writes (Redis, MemoryStore)

Always stub external effects when testing logic in sandbox, or expect side effects to persist.

## Pattern 3: Read-only console

For routine inspection, restrict to a read-only DB user:

```yaml
# config/database.yml
production:
  primary:
    <<: *default
    username: app_writer
  primary_readonly:
    <<: *default
    username: app_reader
    replica: true
```

```ruby
# config/environments/production.rb
config.active_record.database_resolver_context = ActiveRecord::Middleware::DatabaseSelector::Resolver::Session
```

Launch:

```bash
DATABASE_URL=$READ_ONLY_URL bin/rails console
```

Any `INSERT` / `UPDATE` / `DELETE` fails immediately at the DB level. Belt-and-braces with sandbox.

## Pattern 4: Audit-log every console session

```ruby
# config/initializers/console_audit.rb
if defined?(Rails::Console) && Rails.env.production?
  Rails.logger.info(
    user: ENV["USER"],
    hostname: Socket.gethostname,
    started_at: Time.current,
    pid: Process.pid,
    event: "console_session_start"
  )

  at_exit do
    Rails.logger.info(
      user: ENV["USER"],
      hostname: Socket.gethostname,
      ended_at: Time.current,
      pid: Process.pid,
      event: "console_session_end"
    )
  end
end
```

Better: record every command. Use `irb` history file + a tail-shipper:

```ruby
# config/initializers/irb_history.rb
if defined?(IRB) && Rails.env.production?
  IRB.conf[:HISTORY_FILE] = "/var/log/rails/irb_history_#{ENV["USER"]}_#{Process.pid}.log"
  IRB.conf[:SAVE_HISTORY] = 10_000
end
```

Ship the log to your SIEM. Now every command is reviewable.

## Pattern 5: Forbidden methods

These should be flagged on sight in any production console review:

| Method | Why dangerous |
|---|---|
| `Model.update_all(...)` | Skips callbacks, validations, single SQL UPDATE — no undo |
| `Model.delete_all` | Skips callbacks, single SQL DELETE — no undo |
| `Model.destroy_all` | Slow but at least runs callbacks; still no undo |
| `Model.connection.execute("DELETE FROM ...")` | Raw SQL — no safety nets |
| `ActiveRecord::Base.connection.truncate(:posts)` | Truncate is unrecoverable |
| `Model.find_each { |r| r.destroy }` | OK in scripts, dangerous ad-hoc |
| `Rails.cache.clear` | Forces a thundering herd on cold-cache requests |
| `Sidekiq::Queue.new("...").clear` | Drops jobs silently |
| `system("...")` / backticks | Shell out from console → file deletes, network calls |

If you find yourself typing any of these, stop. Write a reviewed rake task instead.

## Pattern 6: Use rake tasks instead

```ruby
# lib/tasks/data_fixes.rake
namespace :data_fixes do
  desc "Backfill premium_until for users who paid in March 2026"
  task backfill_premium_march_2026: :environment do
    affected = User
      .joins(:payments)
      .where(payments: { paid_at: Date.new(2026, 3, 1).beginning_of_day..Date.new(2026, 3, 31).end_of_day })
      .distinct

    puts "About to update #{affected.count} users."
    print "Type 'yes' to continue: "
    confirmation = STDIN.gets.chomp
    abort("Cancelled") unless confirmation == "yes"

    affected.find_each do |user|
      user.update!(premium_until: 30.days.from_now)
      puts "Updated user ##{user.id}"
    end
  end
end
```

Why rake over console:
- Code is in the repo. Reviewable. Versioned. Rollback-able.
- Affected count is logged.
- `find_each` batches — no memory blow-up.
- `update!` per-record runs callbacks / validations.
- Confirmation prompt prevents accidental runs.

Run via: `bin/rails data_fixes:backfill_premium_march_2026` on the production server.

## Pattern 7: One-off scripts as PRs

For larger interventions:

```ruby
# script/2026_05_24_reset_locked_users.rb
# Reviewed and approved in PR #1234
# Run once: bin/rails runner script/2026_05_24_reset_locked_users.rb

raise "Run with RUNNING_INCIDENT=1" unless ENV["RUNNING_INCIDENT"] == "1"

ApplicationRecord.transaction do
  User.where("locked_at < ?", 1.hour.ago).find_each do |user|
    user.update!(locked_at: nil, failed_attempts: 0)
    Rails.logger.info "[script] Unlocked user #{user.id}"
  end
end
```

Commit the file. Reviewed by a peer. Run via `bin/rails runner`. Delete after.

## Pattern 8: Web Console (development only)

Rails ships `web-console` for the development error page. It allows arbitrary Ruby execution on the server.

```ruby
# Gemfile
group :development do
  gem "web-console"
end
```

Verify it's never in production. Audit `config/environments/production.rb`:

```ruby
# Should NOT contain:
# config.web_console.whitelisted_ips = ...
```

By default `web-console` 4.x restricts access to `127.0.0.1` via `allowed_ips`, so the practical attack surface is misconfiguration: someone setting `config.web_console.allowed_ips = "0.0.0.0/0"`, exposing the dev error page through a reverse proxy, or running development assets in a production-ish environment. Wherever `allowed_ips` is opened OR the error page is reachable from untrusted networks, web-console grants RCE — this has happened to multiple companies. Keep it in the `development` group only and never relax `allowed_ips` in production.

## Pattern 9: Console-friendly model helpers

For routine inspection, expose helpers on Application classes:

```ruby
class ApplicationRecord < ActiveRecord::Base
  def self.recent(n = 10)
    order(created_at: :desc).limit(n)
  end

  def self.inspect_columns
    columns.map { |c| [c.name, c.type, c.null].join("\t") }.each { |row| puts row }
  end
end

# Usage:
User.recent(5)
User.inspect_columns
```

Less surface for mistakes — `User.recent(5)` over remembering ORDER BY syntax under pressure.

## Pattern 10: Multi-tenant console safety

If you operate a multi-tenant app:

```ruby
# In console
ActsAsTenant.with_tenant(Account.find(123)) do
  Post.count  # scoped to account 123
end
```

Forgetting `with_tenant` with `require_tenant = true` (see `multi-tenancy`) raises immediately. With it `false`, you'd see all accounts' data — a privacy violation if your screen is shared, an audit issue regardless.

## Common mistakes to refuse

- Don't run `Model.update_all` in console. Use a rake task with a count + confirm.
- Don't run `truncate` ever, on any environment matching production.
- Don't paste SQL from someone's Slack message without reviewing it.
- Don't open a console because "it's faster than writing a task." It's not, when you account for the recovery time of mistakes.
- Don't share console sessions over screen-share without read-only mode.
- Don't trust `--sandbox` to roll back side effects (emails, HTTP calls, Sidekiq enqueues).
- Don't include `web-console` outside of development.

## When the console IS appropriate

- Read-only investigation of a customer complaint.
- Debugging a specific record after an incident (in sandbox).
- Tab-completion exploration of an unfamiliar model.

For everything else: write the script, get it reviewed, run it deliberately.

## See also

- `safe-migrations` — for schema changes, never bypass migrations via console
- `multi-tenancy` — `require_tenant` prevents cross-tenant console mistakes
- `observability-baseline` — audit logging console sessions
- `solid-queue-and-sidekiq` — running rake tasks instead of inline console operations

## Sources

- [Rails console docs](https://guides.rubyonrails.org/command_line.html#bin-rails-console)
- [Rails 7.2 production console warning](https://github.com/rails/rails/pull/49432)
- [web-console RCE history](https://www.rapid7.com/blog/post/2017/03/27/heres-what-you-need-to-know-about-the-new-rails-vulnerability/)
- [Sandbox mode](https://api.rubyonrails.org/classes/Rails/ConsoleMethods.html)
- [Strong Migrations](https://github.com/ankane/strong_migrations)
- [The story of the production console](https://m.signalvnoise.com/) — Basecamp post-mortems
