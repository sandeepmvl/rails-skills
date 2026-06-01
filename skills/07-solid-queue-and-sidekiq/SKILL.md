---
name: solid-queue-and-sidekiq
description: Background job design for Ruby on Rails — when to pick Solid Queue (Rails 8 default, no Redis) vs Sidekiq (existing investment, advanced features), idempotent job patterns, retry / backoff configuration, scheduled jobs via recurring.yml or sidekiq-cron, the decision matrix for "should this even be a background job at all", concurrency controls, dead-set handling, monitoring. Use when writing or reviewing ActiveJob, Sidekiq, Solid Queue jobs, the user mentions perform_later, perform_async, retry, deliver_later, recurring jobs, dead jobs, queue_adapter, or asks whether work should be sync or async.
---

# Solid Queue and Sidekiq

> Decide which job backend to run, design jobs that retry safely, and stop putting things in background jobs that don't belong there. AI agents over-async by reflex (`Job.perform_later` everywhere) and under-think idempotency (which is where retries bite).

## Why this matters

Background jobs are infrastructure. Pick wrong and you're running Redis you didn't need, or your DB is melting under polling. Pick right and they're invisible until they fail — and when they fail, the question is always: "is it safe to retry?"

## The opinion

> **Greenfield Rails 8: Solid Queue, no Redis. Existing Sidekiq investment or specific Sidekiq features needed (Pro/Enterprise rate limiting, batches): keep Sidekiq. Every job: idempotent by design. Retries with exponential backoff. External effects guarded by lookup-before-write. `after_commit` enqueue, never `after_save`.**

Counter-positions:
- **GoodJob** — Postgres-only, mature, supports cron. Solid Queue covers ~all its features now and ships with Rails 8.
- **delayed_job** — fine for tiny apps, dated for everything else.
- **Resque** — historical, don't pick for new work.

## Decision matrix — which backend

| Concern | Solid Queue | Sidekiq |
|---|---|---|
| Default for Rails 8 greenfield | Yes | — |
| Requires Redis | No (uses your DB) | Yes |
| Throughput | Moderate (DB-polling) | High (Redis-driven) |
| `FOR UPDATE SKIP LOCKED` requirement | PG 9.5+, MySQL 8+ | — |
| Concurrency controls | Yes (but pricey overhead at scale) | Yes (built-in + Pro batches) |
| Recurring jobs | `recurring.yml` built-in | `sidekiq-cron` (or `sidekiq-scheduler`) |
| Web dashboard | Mission Control built-in | Sidekiq web UI |
| Cost | Free | OSS free; Pro/Enterprise paid (rate limiting, batches, unique jobs) |
| When to pick | Default Rails 8 — no extra infra | Already running Redis, OR need >5k jobs/sec, OR need Pro features |

**For migrations from Sidekiq to Solid Queue:** both speak Active Job, so application code doesn't change. Switch `config.active_job.queue_adapter`. Drain Sidekiq queues, then cut over. Plan for Sidekiq-specific gems (`sidekiq-cron`, `sidekiq-throttled`, `sidekiq-unique-jobs`) to need replacements.

## Core patterns

### Pattern 1: When NOT to use a background job

**Before** (AI-default — async everything):

```ruby
class UsersController < ApplicationController
  def create
    @user = User.create!(user_params)
    SetDefaultPreferencesJob.perform_later(@user.id)  # 2 DB writes
    LogSignupAuditJob.perform_later(@user.id)          # 1 DB write
    redirect_to @user
  end
end
```

Three jobs to do trivial work that could happen inline in <10ms. Now: queue infrastructure, retry semantics, monitoring — for nothing.

**After** (sync for cheap, async for expensive):

```ruby
class UsersController < ApplicationController
  def create
    @user = User.create!(user_params)
    @user.set_default_preferences  # < 5ms, sync is fine
    @user.log_signup_audit         # < 5ms, sync is fine
    SendWelcomeEmailJob.perform_later(@user.id)  # email — async (external SMTP)
    SyncToCrmJob.perform_later(@user.id)         # external API — async
    redirect_to @user
  end
end
```

**Use a background job when:**

| Trigger | Why |
|---|---|
| Work takes > 200ms | User shouldn't wait |
| External API call | Network failures, rate limits, slow third parties |
| Email / SMS send | SMTP / vendor is async by nature |
| Image / video processing | CPU-heavy, blocks request worker |
| Batch operation (>50 rows) | Lock contention, slow |
| Scheduled work (cron) | Not request-driven |
| Webhook fanout | One write triggers N notifications |

**Don't use a background job for:**

- Cheap database writes the user is waiting on.
- Anything where the user needs to see the result before the next page.
- "Background" work that's actually faster sync (10ms job + 50ms queue overhead = 60ms perceived latency vs 10ms sync).

### Pattern 2: Idempotency

Every retry can re-run a job. Design for it.

**Before** (not idempotent — double-charges on retry):

```ruby
class ChargeCustomerJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    Stripe::PaymentIntent.create(amount: order.total, currency: "usd", payment_method: order.payment_method_id, confirm: true)
    order.update!(status: "paid")
  end
end
```

If `Stripe::PaymentIntent.create` succeeds but the network drops before the response, retry runs the job — and charges the customer again.

**After** (idempotent via lookup):

```ruby
class ChargeCustomerJob < ApplicationJob
  retry_on Stripe::APIError, wait: :polynomially_longer, attempts: 5

  def perform(order_id)
    order = Order.find(order_id)
    return if order.paid?  # already done

    # Modern Stripe API — PaymentIntent. Same idempotency_key shape as the legacy Charge API.
    intent = Stripe::PaymentIntent.create(
      { amount: order.total, currency: "usd", payment_method: order.payment_method_id, confirm: true },
      idempotency_key: "order-#{order.id}-charge"
    )
    order.update!(stripe_payment_intent_id: intent.id, status: "paid")
  end
end
```

**Idempotency strategies (pick the right one):**

| Strategy | Use when |
|---|---|
| Check state first (`return if order.paid?`) | Job has a clear "done" state in your DB |
| External idempotency key (Stripe, Stripe-style APIs) | API supports it (most modern ones do) |
| Database UNIQUE constraint | Job is INSERT-only (deduplicate by `(user_id, action, day)`) |
| `unique_jobs` gem (Sidekiq) or `concurrency` block (Solid Queue) | Prevent enqueueing duplicates in the first place |
| Idempotency log table (own table tracking `job_class:args` → status) | Heavy work where the above don't fit |

### Pattern 3: Retries with exponential backoff

```ruby
class SyncToHubspotJob < ApplicationJob
  retry_on Hubspot::RateLimitError, wait: :polynomially_longer, attempts: 5
  retry_on Hubspot::ServerError,    wait: :polynomially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound  # don't retry — record's gone

  def perform(contact_id)
    contact = Contact.find(contact_id)
    SyncToHubspot.call(contact)
  end
end
```

**Why exponential, not fixed:** a flaky external API recovers in seconds-to-minutes, but if it's down for 10 min and you retry every 30s, you're hammering it. Exponential gives the dependency a chance to breathe.

**Default formula (Rails 7.1+ `:polynomially_longer`; `:exponentially_longer` is the older alias and still works):** `(executions ** 4) + 2 + jitter`. So retry attempts are roughly at 3s, 18s, 83s, 258s, 627s.

**When to override:**
- Network blip — short fixed retry (5s) is fine.
- Rate-limited API — back off MORE (the API is telling you to slow down).
- Provider outage — no point retrying for an hour; route the job to a "manual review" queue or accept the failure.

### Pattern 4: Enqueue from `after_commit`, not `after_save`

```ruby
# WRONG — job worker may pick the row up before the transaction commits
class Post < ApplicationRecord
  after_save :enqueue_publish_job
  def enqueue_publish_job
    PublishPostJob.perform_later(id) if scheduled?
  end
end

# RIGHT
class Post < ApplicationRecord
  after_commit :enqueue_publish_job, on: :update, if: :saved_change_to_scheduled?
  def enqueue_publish_job
    PublishPostJob.perform_later(id) if scheduled?
  end
end
```

See `activerecord-patterns` Pattern 7 (callbacks) and `activerecord-patterns/references/callbacks-deep-dive.md`.

### Pattern 5: Scheduled jobs

**Solid Queue — `config/recurring.yml`:**

```yaml
production:
  cleanup_expired_sessions:
    class: CleanupExpiredSessionsJob
    schedule: every hour
    queue: default

  daily_digest:
    class: SendDailyDigestJob
    schedule: every day at 9am
    queue: mailers

  weekly_report:
    class: GenerateWeeklyReportJob
    schedule: every monday at 8am
    queue: reports
```

**Sidekiq — `sidekiq-cron` gem with `config/schedule.yml`:**

```yaml
cleanup_expired_sessions:
  cron: "0 * * * *"
  class: CleanupExpiredSessionsJob
  queue: default

daily_digest:
  cron: "0 9 * * *"
  class: SendDailyDigestJob
  queue: mailers
```

**Why neither uses `whenever` (which writes crontab):** crontab on a single host doesn't survive autoscaling, container restarts, or migration. Job-system-native scheduling does.

### Pattern 6: Queue separation

```ruby
class SendWelcomeEmailJob < ApplicationJob
  queue_as :mailers  # fast, latency-sensitive
end

class GenerateMonthlyReportJob < ApplicationJob
  queue_as :reports  # heavy, throughput-sensitive
end

class SyncToHubspotJob < ApplicationJob
  queue_as :external_api  # rate-limited, can queue up
end
```

```yaml
# config/queue.yml (Solid Queue)
production:
  - name: critical_workers
    queues: [critical]
    threads: 5
    polling_interval: 0.1
  - name: default_workers
    queues: [mailers, default]
    threads: 10
    polling_interval: 0.5
  - name: heavy_workers
    queues: [reports, external_api]
    threads: 3
    polling_interval: 1
```

**Why separate queues:**
- One slow job class can't backlog the email queue.
- Concurrency per queue tuned to the workload (3 threads for CPU-heavy, 10 for I/O-bound).
- Easier to scale: spin up more workers for the queue under pressure.

### Pattern 7: Concurrency controls — preventing pile-ups

When 100 jobs touch the same row, you get lock contention and duplicates.

**Solid Queue (built-in):**

```ruby
class SyncToCrmJob < ApplicationJob
  # Pass an integer id (preferred — see Common mistakes). The key lambda receives
  # the same args the perform method receives.
  limits_concurrency to: 1, key: ->(contact_id) { "crm-#{contact_id}" }, duration: 5.minutes

  def perform(contact_id)
    contact = Contact.find(contact_id)
    # Only one job per contact at a time. Others wait up to 5 min, then drop.
  end
end
```

**Sidekiq (gem `sidekiq-unique-jobs`):**

```ruby
class SyncToCrmJob
  include Sidekiq::Job

  sidekiq_options lock: :until_executed, lock_args_method: :lock_args
  def self.lock_args(args); [args.first]; end
end
```

**When you need this:** jobs that operate on a single resource that can race (charge customer, sync contact, send notification). Without it, double-enqueues = double-side-effects.

### Pattern 8: Dead-set / failed-job handling

When all retries are exhausted, jobs land in a dead set / failed list.

**What to do:**

1. **Monitor it.** Sidekiq has a dashboard with the dead set. Solid Queue has Mission Control. Set alerts on dead count > 0.
2. **Replay or discard?** Read the error. If transient (rare provider outage), replay. If a code bug, fix the code and replay or write a one-off rake task.
3. **Don't ignore.** A growing dead set is a signal of either a bad external dependency, a code bug, or both.

```ruby
# Replay all dead jobs (Sidekiq)
Sidekiq::DeadSet.new.each(&:retry)

# Solid Queue equivalent — via Mission Control UI or:
SolidQueue::Job.where(finished_at: nil).failed.each { |j| j.retry_now }
```

### Pattern 9: Error handling INSIDE the job

```ruby
class ChargeCustomerJob < ApplicationJob
  retry_on Stripe::CardError, wait: 5.seconds, attempts: 3
  discard_on ActiveRecord::RecordNotFound
  discard_on ActiveJob::DeserializationError

  rescue_from(StandardError) do |error|
    # Last-ditch capture for unexpected errors — log + re-raise for retry
    Rails.error.report(error, context: { job_id: job_id, args: arguments })
    raise
  end

  def perform(order_id)
    order = Order.find(order_id)
    # ...
  end
end
```

**Three classifications:**
- `retry_on Exception` — known transient failure mode.
- `discard_on Exception` — known unrecoverable (record gone, malformed args). Don't retry.
- `rescue_from` — last-line logging before the retry mechanism takes over.

### Pattern 10: Testing jobs

```ruby
# spec/jobs/charge_customer_job_spec.rb
RSpec.describe ChargeCustomerJob, type: :job do
  let(:order) { create(:order, status: "pending") }

  it "charges Stripe and marks the order paid" do
    expect(Stripe::PaymentIntent).to receive(:create).and_return(double(id: "pi_123"))
    described_class.perform_now(order.id)
    expect(order.reload).to be_paid
  end

  it "is idempotent — does not double-charge if already paid" do
    order.update!(status: "paid")
    expect(Stripe::PaymentIntent).not_to receive(:create)
    described_class.perform_now(order.id)
  end

  it "retries on transient errors" do
    allow(Stripe::PaymentIntent).to receive(:create).and_raise(Stripe::APIError)
    expect { described_class.perform_now(order.id) }.to raise_error(Stripe::APIError)
    # Active Job retry_on will reschedule
  end
end
```

Use `perform_now` for synchronous testing. Use `have_enqueued_job` in request specs to assert the job *was enqueued* without running it.

## Common mistakes to refuse

- Don't enqueue from `after_save` — use `after_commit`.
- Don't trust retries to "make it work" — design idempotency in.
- Don't put authoritative IDs in job arguments (pass `order_id`, not `order` object) — the object can be stale by the time the worker picks it up.
- Don't run the same job class on every queue — separate queues by latency requirement.
- Don't ignore the dead set. Alert on it.
- Don't catch `StandardError` and swallow it — re-raise for the retry mechanism to do its job.
- Don't background-job work that's < 200ms — overhead > benefit.
- Don't pick Sidekiq for a greenfield Rails 8 app unless you have a specific reason.

## When NOT to use this skill

- The user is asking about Hotwire Streams pushed from a job — that's `hotwire-turbo-stimulus`.
- The user is asking about ActionMailer specifically — that's `actionmailer-baseline` (which uses jobs under the hood).

## See also

- `activerecord-patterns` — Pattern 7 (after_commit enqueue)
- `rails-security-baseline` — job args shouldn't carry secrets
- `actionmailer-baseline` — mailer jobs
- `rails-api-design` — when to async vs sync in API endpoints

## Sources

- [Solid Queue README](https://github.com/rails/solid_queue) — defaults, polling, concurrency
- [Sidekiq Wiki](https://github.com/sidekiq/sidekiq/wiki) — best practices
- [Rails Guides — Active Job Basics](https://guides.rubyonrails.org/active_job_basics.html)
- [Mission Control — Jobs](https://github.com/rails/mission_control-jobs) — Solid Queue web UI
- [sidekiq-cron](https://github.com/sidekiq-cron/sidekiq-cron)
- [sidekiq-unique-jobs](https://github.com/mhenrixon/sidekiq-unique-jobs)
- [GoodJob (counter-position)](https://github.com/bensheldon/good_job)
- [Stripe — Idempotency keys](https://docs.stripe.com/api/idempotent_requests)
- [Anyway Labs — Sidekiq production checklist](https://github.com/anyway-labs)
- [Rails Guide — Active Support Instrumentation (enqueue.active_job)](https://guides.rubyonrails.org/active_support_instrumentation.html)
