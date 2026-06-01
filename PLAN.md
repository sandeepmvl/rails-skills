# rails-skills — Build Plan

> Read `CLAUDE.md` first. This document is the live roadmap.

## Phase status

- **v0.1 — Foundation (drafted).** Sixteen focused skills, all in `skills/00`–`skills/15`. Reviewed; blocking fixes applied.
- **v0.2 — Expansion (drafted).** Twenty-four skills, `skills/16`–`skills/39`. Reviewed in batches; blocking fixes applied.
- **v0.3 — Specialization (drafted).** Eighteen skills, `skills/40`–`skills/57`. Reviewed; blocking fixes applied.
- **v0.3.1 — Quality tooling (drafted).** One skill, `skills/58-rubocop-and-code-quality`. Added post-review per request.

All 59 skill folders exist with `SKILL.md` + `evals.md`. Final review pass + README skills table update is the remaining gate before launch.

## Anti-goals (what we are deliberately NOT shipping in v0.1)

These were requested in the original scope. They are explicitly deferred — do not start them until v0.1 ships:

1. Rails 3→4, 4→5, 5→6, 6→7 upgrade playbooks → **v0.2**. Rails 7→8 upgrade is covered as a v0.2 skill (was originally inlined in v0.1, moved out to keep v0.1 focused).
2. Database engine migration (PostgreSQL ↔ MySQL ↔ Oracle) → **v0.2**
3. React / Vue / Angular integration skills → **v0.2** (Hotwire ships in v0.1 because it is the Rails 8 default)
4. Microservice decomposition, message buses, CDC → **v0.3**
5. HIPAA / PCI-DSS / GDPR / SOC 2 compliance skills → **v0.3**
6. Data warehouse / big data integration → **v0.3**

If a v0.1 skill tempts you to expand into v0.2/v0.3 territory, resist. Mention the topic in a one-line "See also (coming in v0.2)" footer and move on.

---

## v0.1 — The sixteen

Build in this order. Each skill is one PR. Do not start the next skill until the current one is ready to ship (per the quality checklist in `CLAUDE.md`).

The first twelve are the original launch core. Skills #13–#16 were added after a gap analysis of the most common Rails workloads AI coding agents botch.

### 1. `00-rails-project-discovery` (orchestrator)

**Already drafted.** Polish, write its evals, then move on. This is the highest-leverage skill because it routes to all others.

### 2. `activerecord-patterns`

Scope: associations (`belongs_to`/`has_many`/`has_one`/`has_many :through`), scopes vs class methods, callbacks vs service-layer logic, `find_by` vs `where.first`, when `includes` vs `preload` vs `eager_load`, `pluck` vs `select`, `exists?` vs `present?`, the `counter_cache` pattern, single-table inheritance (when not to use it), polymorphic associations (when not to use them).

Anchor example: take a typical "AI-generated" Rails model that misuses callbacks and refactor it.

### 3. `n-plus-one-killer`

Scope: detection (Bullet gem config, prosopite, query log tailing), prevention patterns, `includes` vs `preload` vs `eager_load` decision tree, counter caches, denormalization, when N+1 is fine (small fixed set).

Bundle `scripts/bullet-config.rb` and `references/query-explained.md` (EXPLAIN ANALYZE for Rails devs).

### 4. `service-objects-vs-fat-models`

Scope: when to keep logic in the model (default), when a service object earns its keep (multi-model transactions, external API orchestration, complex workflows), naming conventions, the `Result` pattern, why we don't reach for service objects on every controller action.

Opinionated. Don't both-sides this. State the DHH-leaning default, then give the specific cases where the alternative wins.

### 5. `rspec-testing-pyramid`

Scope: the testing pyramid for Rails (lots of model + request specs, fewer system specs), FactoryBot patterns, `let` vs `let!` vs `before`, shared examples, VCR for external HTTP, system specs with Capybara + Cuprite, test database strategy (transactional vs truncation), parallel testing config.

Bundle `assets/spec-helper-template.rb` and `assets/rails-helper-template.rb`.

### 6. `safe-migrations`

Scope: strong_migrations rules, zero-downtime patterns (add column with default → add column → set default → backfill → enforce NOT NULL across multiple deploys), `disable_ddl_transaction!`, concurrent index creation (PG), backfill in batches with `find_each`, why `change_column` is dangerous, the deploy/migrate/deploy split.

Bundle `references/zero-downtime-playbook.md`.

### 7. `rails-api-design`

Scope: API versioning (URL `/api/v1` vs `Accept` header — pick URL, here's why), serialization (jsonapi-serializer is the default, alternatives covered), pagination (`pagy` over kaminari, why), authentication (JWT for stateless, session for first-party SPAs), rate limiting via `rack-attack`, error response format, OpenAPI generation via `rswag`.

Bundle `assets/base-api-controller-template.rb`.

### 8. `solid-queue-and-sidekiq`

Scope: when to choose Solid Queue (Rails 8 default, no Redis), when to choose Sidekiq (existing investment, advanced features), idempotent job design, retry/backoff configuration, scheduled jobs (`recurring.yml` for Solid Queue, sidekiq-cron for Sidekiq), the decision matrix for "should this go to a background job at all" (>200ms latency, external API call, side-effect on third party, batch work).

### 9. `devise-pundit-rodauth`

Scope: Devise + Pundit as the default auth + authz combo (still the right answer for most monoliths), Rodauth where Devise hits limits (advanced password policies, account features), JWT auth for API-only apps with `devise-jwt`, secure defaults checklist (lockable, confirmable, password complexity), Pundit policy structure, the "scope" pattern for index actions, common authorization smells.

### 10. `kamal-docker-production`

Scope: multi-stage Dockerfile for Rails (build stage with native deps, slim runtime stage), why `ruby:3.x-slim` is usually better than `alpine` (musl gotchas with native gems like nokogiri, pg, sassc), `docker-compose.yml` for development with Postgres + Redis, Kamal 2 deployment config, zero-downtime deploy patterns, secret management via Kamal envs + Rails credentials, health check endpoints, log shipping.

Bundle `assets/Dockerfile.production`, `assets/docker-compose.dev.yml`, `assets/deploy.yml`.

### 11. `rails-security-baseline`

Scope: strong params (and the common bypass mistakes), CSRF for browser apps, CSRF for SPAs (use cookies + CSRF token endpoint, or skip CSRF + use bearer tokens), Brakeman + bundler-audit + Dependabot, secrets management via Rails credentials (per-env files), JWT best practices (short-lived access tokens 5–15 min, refresh tokens with rotation, never put secrets in JWT payload), CORS configuration for SPAs (no wildcards in production), Rack::Attack for rate limiting and brute-force protection, the OWASP Top 10 mapped to Rails.

Bundle `references/owasp-rails-mapping.md`.

### 12. `rails-caching-strategy`

Scope: the cache layer hierarchy (HTTP/CDN → page cache → action cache (rare now) → fragment cache → low-level cache → DB query cache), Solid Cache as the new default, Redis when distributed cache + pub/sub + Sidekiq are co-located, cache key design (versioned, content-addressed), Russian doll caching for nested views, `Rails.cache.fetch` patterns, cache stampede prevention (`race_condition_ttl`), HTTP caching with `stale?` / `fresh_when`, when caching is the wrong answer (fix the query first).

### 13. `hotwire-turbo-stimulus` _(addition)_

Scope: why Hotwire is the Rails 8 default for UI, Turbo Drive (full-page swaps without React), Turbo Frames (lazy-loaded HTML islands), Turbo Streams (server-pushed updates over WebSocket or response body), Stimulus controllers (the JS sprinkles layer), morph updates (idiomorph), Action Cable broadcasting from models/jobs, when Hotwire is the wrong call (offline-first, native-feel mobile-web, heavy client-side state).

Anchor example: AI agent generates a React snippet to add inline-edit on a post; refactor to Turbo Frame + Stimulus.

### 14. `activestorage-uploads` _(addition)_

Scope: direct uploads to S3/GCS (skip the Rails server for the byte payload), variant configuration (image_processing gem, libvips over imagemagick where possible), content-type and size validation, pre-signed URL safety (short TTLs, no public buckets by default), `analyzer`/`previewer` hooks, processing variants in background jobs not request thread, the "service" config for dev/test/prod, common gotcha: serving private blobs without expiry.

### 15. `actionmailer-baseline` _(addition)_

Scope: ActionMailer setup, `deliver_later` by default (never `deliver_now` in request path), Mailer previews in dev, mailer specs (RSpec), Letter Opener for dev, Postmark/SendGrid/SES/Mailgun for prod, bounce/complaint handling, idempotent transactional sends (don't double-send password resets on retry), `ActionMailbox` mentioned but deferred to v0.2, attachments + inline images, `i18n` for mailer subjects/bodies.

### 16. `observability-baseline` _(addition)_

Scope: `lograge` structured single-line logs, request tagging (`request_id`, `user_id`), error tracking via Sentry / Honeybadger / Rollbar (Sentry default unless cost-constrained), PII scrubbing in error reports + logs, `Rails.error.report` (Rails 7.1+), OpenTelemetry mentioned but deferred to v0.3 (too heavy for a baseline), what to log vs not (no PII, no card data, no JWT contents), structured fields over message concatenation. Deeper observability (APM tracing, distributed tracing, custom metrics) lives in `observability-rails-advanced` (v0.3).

### Bonus for v0.1 (only if time permits)

- `rails-code-review` — invoked on a diff or PR, runs a Rails-flavored review checklist
- `rails-doctor` — diagnostic that scans the app and reports issues (high demo value)

---

## v0.2 — Expansion (~6–8 weeks after v0.1 ships)

Each line below is one skill folder. Originals from earlier roadmap plus the additions surfaced during v0.1 gap analysis.

**Version upgrades**
- `rails-upgrade-7-to-8`
- `rails-upgrade-6-to-7`
- `rails-upgrade-5-to-6`
- `rails-upgrade-4-to-5`
- `rails-upgrade-3-to-4`

**Database engine migrations**
- `db-migration-postgres-mysql`
- `db-migration-mysql-postgres`
- `db-migration-oracle-postgres`

**Frontend integration (when not using Hotwire)**
- `react-with-rails` (Inertia.js as default, classical API+SPA as alternative)
- `vue-with-rails`
- `angular-with-rails`

**Performance + infrastructure**
- `puma-tuning-and-concurrency`
- `asset-pipeline-propshaft` (Propshaft + Importmap vs jsbundling vs cssbundling — when which wins)
- `multi-database-and-replicas`

**Integration patterns**
- `webhook-handling` (idempotency, signature verification, retry semantics, generic)
- `stripe-webhook-integration` (the canonical example, including idempotency keys + payment intents)
- `external-api-integration` (Faraday + circuit breaker + retries + VCR)
- `feature-flagging` (Flipper)

**Architectural patterns + day-2 ops**
- `form-objects-query-objects-presenters` (when each earns its keep, naming, testing)
- `actiontext-richtext` (Trix, sanitization gotchas, attachment handling)
- `i18n-and-timezones` (I18n keys, fallbacks, Time.current vs Time.now, time zone storage)
- `rails-search` (pg_search by default, Meilisearch when full-text isn't enough, Elasticsearch only when justified)
- `multi-tenancy` (row-level vs schema-based vs DB-per-tenant — when each fits)
- `console-safety-production` (immutable shell wrappers, audit trails, read-only console, `Marginalia` for query attribution)

## v0.3 — Specialization

**Architectural macro-decisions (refuse first, then guide)**
- `when-NOT-to-use-microservices` (ships first on purpose)
- `microservices-decomposition`
- `monolith-to-services-extraction` (strangler-fig)

**Message buses + event-driven**
- `kafka-rails`
- `rabbitmq-rails`
- `redis-streams-rails`
- `cdc-debezium-rails`
- `event-driven-architecture`

**Observability (deep)**
- `distributed-tracing-rails` (OpenTelemetry)
- `observability-rails-advanced` (APM, custom metrics, RED method for Rails endpoints, log sampling)

**Compliance**
- `hipaa-rails`
- `pci-dss-rails`
- `gdpr-rails`
- `soc2-rails`

**Data engineering**
- `data-warehouse-integration` (Snowflake/BigQuery/Redshift ETL)

**CI/CD**
- `ci-cd-github-actions-rails`
- `ci-cd-gitlab-rails`
- `ci-cd-jenkins-rails`

---

## Definition of done for v0.1

- [ ] All 16 skills shipped per the quality checklist in `CLAUDE.md`
- [ ] `README.md` has the skills table, install instructions for Claude Code / Cursor / Codex / Gemini CLI / Antigravity / Windsurf, and a before/after demo
- [ ] `LAUNCH.md` checklist completed through "Day 1 launch"
- [ ] 500+ GitHub stars within 30 days of launch (floor target; this is achievable for a quality Rails skill pack via RubyWeekly + r/rails alone)
