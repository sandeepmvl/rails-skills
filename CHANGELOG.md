# Changelog

All notable changes to `rails-skills` are documented in this file.

---

## [0.1.0] — 2026-09-26

### v0.1.0: Production-grade Claude Skills for Rails 8 — Foundation Release

The first stable release of `rails-skills`: **16 foundation skills** covering the patterns, performance traps, security baselines, and deployment conventions that senior Rails developers rely on. Install once, globally, and watch AI agents write idiomatic Rails code.

#### What's in v0.1.0

**Foundation (16 skills)**

1. **`rails-project-discovery`** — Orchestrator that interviews you about your app and routes to the right downstream skills
2. **`activerecord-patterns`** — Idiomatic ActiveRecord: associations, scopes, callbacks, includes vs preload vs eager_load
3. **`n-plus-one-killer`** — Detect and eliminate N+1 queries with Bullet, prosopite, and eager-loading patterns
4. **`service-objects-vs-fat-models`** — Know when to keep logic in the model vs extract a service object
5. **`rspec-testing-pyramid`** — RSpec testing discipline: the pyramid shape, FactoryBot, VCR, system specs with Cuprite
6. **`safe-migrations`** — Zero-downtime migrations: strong_migrations, the add/backfill/enforce split, concurrent indexes
7. **`rails-api-design`** — REST API design: versioning, serialization, pagination, JWT auth, rack-attack rate limiting
8. **`solid-queue-and-sidekiq`** — Choose between Solid Queue (Rails 8 default) and Sidekiq; idempotent job patterns
9. **`devise-pundit-rodauth`** — Authentication + authorization: Devise + Pundit as the default, Rodauth for advanced cases
10. **`kamal-docker-production`** — Production deployment: multi-stage Dockerfile, docker-compose for dev, Kamal 2 deploys
11. **`rails-security-baseline`** — Security: strong params, CSRF, Brakeman, credentials, JWT, CORS, Rack::Attack, OWASP for Rails
12. **`rails-caching-strategy`** — Caching hierarchy: Solid Cache (Rails 8 default), Redis, fragment cache, cache stampede prevention
13. **`hotwire-turbo-stimulus`** — Modern Rails UI stack: Turbo Drive, Frames, Streams, Stimulus, Action Cable broadcasts
14. **`activestorage-uploads`** — File uploads: direct to S3/GCS, variants with libvips, pre-signed URL safety
15. **`actionmailer-baseline`** — Email: ActionMailer setup, deliver_later, transactional sends, bounce handling
16. **`observability-baseline`** — Production observability: lograge, Sentry/Honeybadger/Rollbar, Rails.error.report, PII scrubbing

#### Install

**Claude Code (recommended: global, one-time setup)**
```bash
git clone https://github.com/sandeepmvl/rails-skills ~/.claude/skills/rails-skills
```

Then start Claude Code on any Rails project. The `rails-project-discovery` orchestrator wakes up automatically and routes you to the right skills.

**Per-project installation**
```bash
cd <your-rails-app>
git clone https://github.com/sandeepmvl/rails-skills .claude/skills
```

**Other tools** — See [docs/install.md](./docs/install.md) for Claude.ai, the Claude API, OpenAI Codex, Cursor, Gemini CLI, Antigravity, and Windsurf.

#### Why v0.1.0

These 16 skills solve the **most-felt pain points** when AI agents write Rails code:

- Hidden N+1 queries in views
- Callbacks instead of jobs or after_commit
- Service object bloat (extracting logic that belongs in fat models)
- Weak test discipline (system specs instead of unit + request specs)
- Zero-downtime migration gotchas and deploy ordering
- Auth complexity (Devise vs Rodauth vs built-in authentication)
- Caching without strategy (full-page caching when fragment cache would do)
- Missing security baselines (mass assignment, CSRF, secrets in logs, OWASP gaps)
- File uploads to the request thread (instead of direct-to-S3)
- No observability in production

#### What's NOT in v0.1.0

Rails upgrade skills (v0.2), database migrations (v0.2), React/Vue/Angular integration (v0.2), microservice guidance (v0.3), compliance skills for HIPAA/PCI/GDPR (v0.3), and CI/CD skills (v0.3) ship in later releases. See [PLAN.md](./PLAN.md) for the full roadmap.

#### Known limitations

- Skills teach patterns, not automate upgrades. A skill guides the agent and accelerates your work; it does not replace human judgment on architectural decisions.
- These are baseline conventions for Rails 8 apps. If your app uses different patterns (Minitest vs RSpec, Sidekiq-only, React-first), cherry-pick the skills that fit your stack.
- This pack assumes basic Rails knowledge. If you're new to Rails, pair this pack with the [Rails Guides](https://guides.rubyonrails.org).

#### License

MIT — use it anywhere.

---

## [Unreleased]

### v0.2 (coming soon)
- 8 Rails upgrade skills (3→4 through 7→8)
- 3 database engine migration skills (PostgreSQL ↔ MySQL, Oracle → Postgres)
- 3 frontend integration skills (React, Vue, Angular with Rails)
- 10+ infrastructure & integration skills (Puma tuning, asset pipeline, multi-database, webhooks, Stripe, external APIs, feature flags, search, multi-tenancy, console safety)

### v0.3 (specialization)
- Microservices guidance (when NOT to, decomposition, strangler fig extraction)
- Event-driven & message buses (Kafka, RabbitMQ, Redis Streams, CDC)
- Distributed tracing and advanced observability (OpenTelemetry, SLOs, alerting)
- Compliance skills (HIPAA, PCI-DSS, GDPR, SOC 2, data warehouse)
- CI/CD skills (GitHub Actions, GitLab, Jenkins)

### Tooling & project-aware
- `rubocop-and-code-quality` — RuboCop, SimpleCov, erb_lint, type checking (Sorbet/RBS)
- `scaffold-project-skills` — Generate project-specific skills from your codebase (multi-tenancy, workflows, test gates)
