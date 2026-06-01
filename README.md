# rails-skills

> Production-grade Claude Skills for Ruby on Rails. Stop fighting your AI coding agent on Rails conventions — drop in `rails-skills` and Claude Code, Cursor, Codex, Gemini CLI, Antigravity, and Windsurf will write Rails code the way senior Rails developers actually write it.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Skills format](https://img.shields.io/badge/format-Anthropic%20Skills-blue)](https://docs.claude.com)
[![Rails](https://img.shields.io/badge/Rails-8.0-cc0000)](https://rubyonrails.org)

## The problem

You ask Claude Code or Cursor to "add a draft status with scheduled publishing to Post." It generates a migration, a callback, a controller update. It looks fine. Then you notice:

- It added a `before_save` callback instead of using your existing `PublishPostJob`
- It used a string column for `status` instead of the `enum` already on the model
- It didn't add the partial index PostgreSQL needs for the new status
- The test it wrote doesn't use your existing `Post` factory
- It hardcoded the timezone

Every Rails dev using an AI agent has had this morning. The agent isn't dumb — it just doesn't know your Rails conventions. `rails-skills` teaches it.

## What this is

A pack of independent **Claude Skills** ([open standard](https://docs.claude.com), released by Anthropic in December 2025) covering the patterns, performance traps, security baselines, and deployment conventions that senior Rails developers care about. Each skill is portable across:

- Claude Code
- Claude.ai
- the Claude API
- OpenAI Codex
- Cursor
- Gemini CLI
- Antigravity
- Windsurf

## Quick install

### Claude Code

```bash
cd <your-rails-app>
git clone https://github.com/<your-handle>/rails-skills .claude/skills
```

Then start Claude Code in your project. The orchestrator skill (`rails-project-discovery`) will interview you and route to the right downstream skills automatically.

### Cursor

```bash
cd <your-rails-app>
git clone https://github.com/<your-handle>/rails-skills .cursor/skills
```

### Other tools

See `docs/install.md` for OpenAI Codex, Gemini CLI, Antigravity, and Windsurf instructions.

## The skills

### v0.1 — Foundation (16 skills)

| # | Skill | What it does |
|---|---|---|
| 00 | `rails-project-discovery` | Orchestrator — interviews you about your app and routes to the right skills below |
| 01 | `activerecord-patterns` | Associations, scopes, callbacks, includes vs preload vs eager_load |
| 02 | `n-plus-one-killer` | Detect, diagnose, and eliminate N+1 queries |
| 03 | `service-objects-vs-fat-models` | When to keep logic in the model and when to extract a service object |
| 04 | `rspec-testing-pyramid` | RSpec, FactoryBot, VCR, system specs — what to test at which layer |
| 05 | `safe-migrations` | strong_migrations rules, zero-downtime patterns, backfill in batches |
| 06 | `rails-api-design` | Versioning, serialization, pagination, rate limiting, JWT auth |
| 07 | `solid-queue-and-sidekiq` | Choosing between them, idempotent jobs, retries, scheduled work |
| 08 | `devise-pundit-rodauth` | Authentication + authorization patterns done the Rails way |
| 09 | `kamal-docker-production` | Multi-stage Dockerfile, docker-compose dev, Kamal 2 deploys |
| 10 | `rails-security-baseline` | Strong params, CSRF, Brakeman, secrets, JWT, CORS, OWASP for Rails |
| 11 | `rails-caching-strategy` | Solid Cache, Redis, fragment vs low-level, cache stampede prevention |
| 12 | `hotwire-turbo-stimulus` | Turbo Drive/Frames/Streams, Stimulus, Action Cable broadcasts |
| 13 | `activestorage-uploads` | Direct upload, variants, signed URLs, validation, S3/GCS service config |
| 14 | `actionmailer-baseline` | Mailer setup, deliver_later, previews, specs, bounces, idempotent sends |
| 15 | `observability-baseline` | lograge structured logs, Sentry, PII scrubbing, Rails.error.report |

### v0.2 — Expansion (24 skills)

| # | Skill | What it does |
|---|---|---|
| 16 | `rails-upgrade-7-to-8` | dual-Gemfile next-version pattern; 7.x → 8 hops |
| 17 | `rails-upgrade-6-to-7` | importmap / jsbundling, encrypts, Trilogy intro |
| 18 | `rails-upgrade-5-to-6` | Zeitwerk transition, Webpacker decision |
| 19 | `rails-upgrade-4-to-5` | API mode, ActionCable, ApplicationRecord |
| 20 | `rails-upgrade-3-to-4` | strong params, Turbolinks, encrypted secrets |
| 21 | `db-migration-postgres-mysql` | Type mapping, JSONB→JSON, Trilogy gem swap |
| 22 | `db-migration-mysql-postgres` | UTF8MB4→UTF-8, prepared_statements + pgbouncer |
| 23 | `db-migration-oracle-postgres` | ora2pg, DATE→TIMESTAMPTZ, sequences |
| 24 | `react-with-rails` | Inertia.js default, vite_rails, API+SPA alt |
| 25 | `vue-with-rails` | Inertia + Vue 3 + Vite |
| 26 | `angular-with-rails` | Standalone components, `@for`/`@if`, provideHttpClient |
| 27 | `puma-tuning-and-concurrency` | Workers/threads, jemalloc, YJIT, PumaWorkerKiller |
| 28 | `asset-pipeline-propshaft` | Propshaft vs Sprockets, jsbundling, importmap |
| 29 | `multi-database-and-replicas` | connects_to, sticky writes, sharding caveats |
| 30 | `webhook-handling` | Idempotent inserts, HMAC verify, DLQ patterns |
| 31 | `stripe-webhook-integration` | construct_event, PaymentIntent, idempotency keys |
| 32 | `external-api-integration` | Faraday 2, Stoplight circuit breaker, VCR |
| 33 | `feature-flagging` | Flipper, gradual rollout, kill switch |
| 34 | `form-objects-query-objects-presenters` | Architectural extractions beyond fat models |
| 35 | `actiontext-richtext` | Trix, sanitization, embedded attachments, search index |
| 36 | `i18n-and-timezones` | rails-i18n, fallbacks, Time.current, DST traps |
| 37 | `rails-search` | pg_search → Meilisearch → Elasticsearch tiering |
| 38 | `multi-tenancy` | acts_as_tenant, subdomain resolver, require_tenant |
| 39 | `console-safety-production` | Sandbox, audit log, rake tasks over console |

### v0.3 — Specialization (18 skills)

| # | Skill | What it does |
|---|---|---|
| 40 | `when-NOT-to-use-microservices` | Refuses microservices before guiding them. Modular monolith default. |
| 41 | `microservices-decomposition` | Bounded contexts, owned data, JWT/mTLS, sagas |
| 42 | `monolith-to-services-extraction` | Strangler fig, dark-launch, dual-write, cutover |
| 43 | `kafka-rails` | karafka 2.x, outbox, schema registry, partitioning |
| 44 | `rabbitmq-rails` | bunny + sneakers, DLX, prefetch, manual ack |
| 45 | `redis-streams-rails` | XADD, XREADGROUP, XAUTOCLAIM reaper |
| 46 | `cdc-debezium-rails` | Postgres logical replication, outbox + EventRouter SMT |
| 47 | `event-driven-architecture` | Domain vs integration events, rails_event_store, outbox |
| 48 | `distributed-tracing-rails` | OpenTelemetry, OTLP, baggage, sampling, exemplars |
| 49 | `observability-rails-advanced` | RED/USE, SLOs, multi-burn-rate alerts, runbooks |
| 50 | `hipaa-rails` | PHI handling, AR Encryption, audit logs, BAAs |
| 51 | `pci-dss-rails` | SAQ-A path, Stripe Elements, never PAN/CVV |
| 52 | `gdpr-rails` | DSAR, erasure, lawful basis, consent, retention |
| 53 | `soc2-rails` | Trust Services, audit logs, access reviews, MFA |
| 54 | `data-warehouse-integration` | Fivetran/Airbyte ingest, dbt transforms, reverse-ETL |
| 55 | `ci-cd-github-actions-rails` | matrix sharding, bundler-cache, OIDC, Kamal deploy |
| 56 | `ci-cd-gitlab-rails` | stages, services, id_tokens for OIDC, Auto DevOps caveat |
| 57 | `ci-cd-jenkins-rails` | Declarative pipeline, credentials store, when NOT Jenkins |
| 58 | `rubocop-and-code-quality` | RuboCop + omakase preset + rubocop-rails/-performance/-rspec, SimpleCov, erb_lint, RBS vs Sorbet |

See [`PLAN.md`](./PLAN.md) for the full roadmap and rationale.

## Before / after

Same prompt — *"list the 20 most recent posts with their authors"* — to the same agent. Without the pack, then with it.

**Without `rails-skills`** (AI-typical — a hidden N+1 that only bites in production):

```ruby
# app/controllers/posts_controller.rb
def index
  @posts = Post.order(created_at: :desc).limit(20)
end
```
```erb
<% @posts.each do |post| %>
  <%= post.title %> — <%= post.author.name %>   <%# 1 + 20 queries %>
<% end %>
```

**With `rails-skills`** (the `n-plus-one-killer` + `activerecord-patterns` skills trigger):

```ruby
# app/controllers/posts_controller.rb
def index
  # includes(:author) → 2 queries total, regardless of row count.
  @posts = Post.includes(:author).order(created_at: :desc).limit(20)
end
```

The agent also adds a Bullet config to catch the next N+1 in development before it ships, and explains *why* `includes` beats a manual join here. That's the difference: not just correct code, but conventional code with the reasoning a senior Rails dev would give.

> A 30-second screencast of this exact flow lands here before the public launch. Until then, the worked example above is the demo.

## What this is NOT

- **Not magic.** A `rails-upgrade-4-to-8` skill will *guide* and *accelerate* the upgrade. It will not do it autonomously. Rails upgrades require human judgment on gem replacements and test fixes.
- **Not a replacement for the Rails Guides.** These skills target the gaps where AI agents go wrong, not the basics.
- **Not a gem.** Nothing here gets `require`d into your Rails app. Skills are markdown files consumed by AI coding agents.

## Philosophy

These skills lean DHH: Majestic Monolith, fat models, Hotwire by default, Solid Queue/Cache/Cable on Rails 8. Where the Rails community legitimately disagrees, we state our position with rationale and acknowledge the alternative. We don't both-sides every decision.

## Contributing

We need skills for everything in `PLAN.md` under v0.2 and v0.3. Pick one, copy `skills/_TEMPLATE/`, follow the conventions in `CLAUDE.md`, and open a PR.

Skills under v0.1 are the maintainer's responsibility — they set the quality bar. PRs welcome on v0.2+.

## License

MIT — use it anywhere. If it saves your team time, a star is the only thanks needed.
