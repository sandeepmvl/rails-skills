---
name: observability-baseline
description: Observability baseline for Rails 8 production apps — lograge for structured single-line logs, request tagging (request_id, user_id), error tracking via Sentry / Honeybadger / Rollbar, Rails.error.report (Rails 7.1+) as the standard error-reporting API, PII scrubbing in logs and error reports, what to log vs not (no PII, no card data, no JWT contents), structured fields over message concatenation. Deeper observability (APM tracing, distributed tracing, custom metrics) lives in observability-rails-advanced (v0.3). Use when the user mentions logging, lograge, structured logs, Sentry, Honeybadger, Rollbar, error tracking, Rails.error.report, PII, request_id, log tagging, log levels, what to log, or asks "how do I know if my Rails app is healthy in production".
---

# Observability Baseline

> The floor: every Rails 8 production app needs structured logs, request correlation, error tracking with PII scrubbing, and clear what-to-log rules. Deeper observability (APM, distributed tracing, custom metrics) is v0.3 work. This skill makes the floor real.

## Why this matters

When something breaks at 2am, you have three questions: did it actually break (logs), how often (errors), and why (context). Default Rails logging answers none of these well — it's multiline, unstructured, missing user context. This skill replaces the default with the senior-Rails-dev defaults that scale.

## The opinion

> **lograge for single-line structured logs. Tag every log with request_id + user_id. Sentry for errors (Honeybadger / Rollbar are equivalent — pick one; not all three). Use `Rails.error.report` (Rails 7.1+) for non-fatal errors instead of inline logging. PII scrubbing on `filter_parameters` (mirrored in error tracker config). Never log: passwords, card data, JWT contents, full SSN, full DOB. Log structured fields, not concatenated strings.**

Counter-positions:
- **No error tracker** — fine for tiny pre-revenue apps. Sentry's free tier is generous; the trade-off is tiny.
- **OpenTelemetry from day one** — heavy investment for limited return on a small app. Stage it: lograge + Sentry first, OTel when you have multiple services.

## Core patterns

### Pattern 1: lograge — structured single-line logs

**Before** (Rails default, hard to parse):

```
I, [2026-05-24T10:00:00.123]  INFO -- : Started GET "/posts/42" for 192.0.2.1 at ...
I, [2026-05-24T10:00:00.124]  INFO -- : Processing by PostsController#show as HTML
I, [2026-05-24T10:00:00.125]  INFO -- :   Parameters: {"id" => "42"}
I, [2026-05-24T10:00:00.150]  INFO -- :   Rendered post/show.html.erb (Duration: 12.0ms | Allocations: 1234)
I, [2026-05-24T10:00:00.155]  INFO -- : Completed 200 OK in 30ms (Views: 12.0ms | ActiveRecord: 8.0ms)
```

Six lines per request. Multiline logs are painful to grep, hard to ship, and impossible to query at scale.

**After** (lograge — one structured line per request):

```ruby
# Gemfile
gem "lograge"

# config/environments/production.rb
config.lograge.enabled = true
config.lograge.formatter = Lograge::Formatters::Json.new
config.lograge.custom_options = lambda do |event|
  {
    request_id: event.payload[:request_id],
    user_id: event.payload[:user_id],
    remote_ip: event.payload[:remote_ip],
    params: event.payload[:params].except("controller", "action", "format")
  }
end

# Inject request_id + user_id into the lograge payload.
# `append_info_to_payload` is the Rails-native hook — Rails merges this hash into the
# `process_action.action_controller` event payload, which is what lograge reads from.
class ApplicationController < ActionController::Base
  def append_info_to_payload(payload)
    super
    payload[:request_id] = request.request_id
    payload[:user_id]    = current_user&.id
    payload[:remote_ip]  = request.remote_ip
  end
end
```

Output (one line per request, JSON):

```json
{"method":"GET","path":"/posts/42","format":"html","controller":"PostsController","action":"show","status":200,"duration":30.5,"view":12.0,"db":8.0,"request_id":"abc-123","user_id":42,"remote_ip":"192.0.2.1","params":{"id":"42"}}
```

Now grep by request_id to follow a single request. Ship to ELK / Loki / Datadog and query by user_id, status, duration.

### Pattern 2: Job log tagging

```ruby
# config/initializers/lograge.rb
Rails.application.configure do
  config.lograge.base_controller_class = ["ActionController::Base", "ActionController::API"]
end

# For Active Job: tag the job logs with job_id + queue
class ApplicationJob < ActiveJob::Base
  around_perform do |job, block|
    Rails.logger.tagged("job=#{job.class.name}", "job_id=#{job.job_id}", "queue=#{job.queue_name}") do
      block.call
    end
  end
end
```

For Sidekiq specifically, use [`sidekiq/logger`](https://github.com/sidekiq/sidekiq/wiki/Logging) with the same structured output.

### Pattern 3: `Rails.error.report` — the standard error API (Rails 7.1+)

**Before** (ad-hoc inline logging):

```ruby
def fetch_external
  data = external_api.fetch
rescue HTTP::Error => e
  Rails.logger.error("External fetch failed: #{e.message}")
  Sentry.capture_exception(e, extra: { context: "post sync" })
  Honeybadger.notify(e)
  raise
end
```

Different code paths report errors differently. Some go to Sentry, some only to logs, some go to both — inconsistency.

**After** (single API):

```ruby
def fetch_external
  data = external_api.fetch
rescue HTTP::Error => e
  Rails.error.report(e, context: { source: "external_api", post_id: @post.id })
  raise
end
```

`Rails.error.report` is the Rails-standard error reporting API. Sentry / Honeybadger / Rollbar all hook in as subscribers. One code path, multiple destinations.

```ruby
# config/initializers/error_subscriber.rb
class ErrorSubscriber
  def report(error, handled:, severity:, context:, source: nil)
    Sentry.capture_exception(error, extra: context.merge(severity: severity, source: source))
  end
end

Rails.error.subscribe(ErrorSubscriber.new)
```

Sentry's own gem ships a subscriber by default (Rails 7.1+). For Honeybadger / Rollbar, write the small adapter above.

### Pattern 4: Sentry setup (recommended default)

```ruby
# Gemfile
gem "sentry-ruby"
gem "sentry-rails"
gem "sentry-sidekiq" if defined?(Sidekiq)  # or sentry-delayed_job, etc.

# config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.environment = Rails.env

  # Sampling: 10% of transactions in prod (cost vs visibility)
  config.traces_sample_rate = 0.1

  # Profiling: 10% of traces
  config.profiles_sample_rate = 0.1

  # Capture warnings and above (Errors, FATAL)
  config.send_default_pii = false  # CRITICAL — never auto-send PII

  # Scrub the entire cookies hash from outgoing events. (Assigning a string
  # replaces the hash — keeping it as an empty hash is the cleanest "filtered".)
  config.before_send = lambda do |event, hint|
    event.request&.cookies = {}
    event
  end
end
```

**`send_default_pii = false`** is critical. Sentry can auto-attach the user (email, IP, name) from the request — for many apps, that's a privacy violation. Opt in only for the fields you've reviewed.

### Pattern 5: PII scrubbing — `filter_parameters`

```ruby
# config/application.rb (Rails default + extensions)
Rails.application.config.filter_parameters += %i[
  password password_confirmation
  token api_token authentication_token
  ssn social_security_number
  card_number cvv credit_card
  pin
  authorization
]
```

Rails auto-scrubs these in:
- Request logs.
- Error backtraces shown in better_errors / web-console.
- Lograge output (it inherits `filter_parameters`).

**Mirror in Sentry config:**

```ruby
Sentry.init do |config|
  config.send_default_pii = false
  config.before_send = lambda do |event, hint|
    # Defense in depth — strip any sensitive fields Sentry might pick up
    event.request&.data&.transform_values! { |v| v.is_a?(String) && v.length > 1000 ? "[TRUNCATED]" : v }
    event
  end
end
```

### Pattern 6: What to log vs not

```ruby
# DON'T log
Rails.logger.info "User logged in: #{user.email} #{user.password}"   # password
Rails.logger.info "Payment: #{params[:card_number]}"                  # card data
Rails.logger.info "Token: #{request.headers['Authorization']}"        # JWT
Rails.logger.info "Full payload: #{params.to_json}"                   # arbitrary user input

# DO log (structured)
Rails.logger.info({ event: "user_login", user_id: user.id, ip: request.remote_ip }.to_json)
Rails.logger.info({ event: "payment_attempted", order_id: order.id, amount_cents: order.total_cents, vendor: "stripe" }.to_json)
Rails.logger.info({ event: "rate_limit_hit", path: request.path, ip: request.remote_ip }.to_json)
```

**Rules:**
- **No PII**: emails, names, full DOB, full address, phone numbers.
- **No credentials**: passwords, API keys, JWTs, session tokens.
- **No card data**: PCI scope; lock these out.
- **Structured > concatenated**: `{ event: "x", field: y }` queries cleanly; `"User #{user.email} did x with #{thing}"` doesn't.

For PII-adjacent fields you need to correlate: log hashes, not values.

```ruby
Rails.logger.info({ event: "user_login", user_id_hash: Digest::SHA256.hexdigest(user.id.to_s) }.to_json)
```

### Pattern 7: Log levels

```ruby
# config/environments/production.rb
config.log_level = :info  # debug too noisy; warn too sparse
config.log_tags = [:request_id]  # auto-tag every log line
```

| Level | Use for |
|---|---|
| `:debug` | Dev only; SQL queries, cache hits, parameter dumps |
| `:info` | Normal request flow, business events |
| `:warn` | Recoverable but notable: rate limit hits, slow queries, deprecation warnings |
| `:error` | Exception caught and reported via `Rails.error.report` |
| `:fatal` | App-breaking; should page someone |

**Anti-pattern:** `Rails.logger.info` for everything. Production logs become unfilterable. Use the levels.

### Pattern 8: Health endpoint — for monitoring

See `kamal-docker-production` Pattern 6 for `/up` and `/health`. Monitor `/health` from outside (Pingdom, Better Stack, UptimeRobot). Alert on:
- `/health` returns non-200 for 3 consecutive checks.
- p99 latency > N ms.
- Error rate > X% over 5 minutes.

### Pattern 9: Background job observability

```ruby
class ApplicationJob < ActiveJob::Base
  rescue_from(StandardError) do |error|
    Rails.error.report(error, context: { job: self.class.name, args: arguments, job_id: job_id })
    raise  # let retry_on / discard_on take over
  end
end
```

**Per-job context** so the error tracker shows the job class, the args, and the job_id — much more useful than a bare stack trace.

### Pattern 10: When you've outgrown the baseline

Signs you need v0.3 (`observability-rails-advanced`):
- Multiple services calling each other — distributed tracing (OpenTelemetry) becomes valuable.
- Custom business metrics: revenue, signup funnel, conversion. Need a metrics backend (Prometheus + Grafana, Datadog metrics).
- Need to query logs across a fleet — central log aggregation (Loki, ELK).
- SLOs / SLIs become a real discipline.

For most Rails 8 apps, lograge + request tagging + Sentry covers the first 12 months of growth.

## Decision matrix

| Need | Use |
|---|---|
| Default log format | lograge JSON |
| Correlate logs by request | request_id tag + lograge custom_options |
| Capture unhandled exception | Sentry (or HB / Rollbar) — pick one |
| Capture handled but notable exception | `Rails.error.report(e, handled: true)` |
| Strip secrets from logs | `filter_parameters` (Rails) + Sentry `before_send` |
| Monitor uptime | External pinger on `/health` |
| Track business events | Structured `Rails.logger.info({ event: ... })` |
| Performance breakdown per endpoint | APM (Scout, Skylight, Datadog) — covered in v0.3 |

## Common mistakes to refuse

- Don't log passwords, card data, JWTs, full SSN.
- Don't use Rails' default multiline log format in production.
- Don't run all three: Sentry + Honeybadger + Rollbar. Pick one.
- Don't `Sentry.capture_exception` in scattered places — use `Rails.error.report`.
- Don't set `send_default_pii = true` without auditing what gets sent.
- Don't `puts` or `pp` debug statements that survive to production.
- Don't log at `:debug` in production — disk fills, signal-to-noise dies.
- Don't ship secrets via `extra:` payload to Sentry — they end up in the error report.

## When NOT to use this skill

- The user is asking about APM-level observability — that's v0.3 (`observability-rails-advanced`, `distributed-tracing-rails`).
- The user is asking about a specific Sentry feature — link to Sentry docs.

## See also

- `rails-security-baseline` — `filter_parameters` setup
- `kamal-docker-production` — log shipping at the container level
- `solid-queue-and-sidekiq` — job error reporting
- `actionmailer-baseline` — error tracker shouldn't carry mailer payload PII
- Coming in v0.3: `observability-rails-advanced`, `distributed-tracing-rails`

## Sources

- [lograge README](https://github.com/roidrage/lograge)
- [Rails 7.1 — Rails.error](https://guides.rubyonrails.org/error_reporting.html)
- [Sentry Ruby + Rails docs](https://docs.sentry.io/platforms/ruby/guides/rails/)
- [Honeybadger Ruby docs](https://docs.honeybadger.io/lib/ruby/) (counter-position)
- [Rollbar Ruby docs](https://docs.rollbar.com/docs/ruby) (counter-position)
- [Rails Guides — Active Support Instrumentation](https://guides.rubyonrails.org/active_support_instrumentation.html)
- [Rails Guides — Debugging](https://guides.rubyonrails.org/debugging_rails_applications.html#log-levels)
- [Better Stack — Rails logging guide](https://betterstack.com/community/guides/logging/)
- [OWASP — Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html) — what NOT to log
- [Datadog — Rails observability](https://www.datadoghq.com/blog/instrument-ruby-with-datadog/)
