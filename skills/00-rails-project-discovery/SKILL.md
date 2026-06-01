---
name: rails-project-discovery
description: Interview the developer about their Ruby on Rails project (app type, database, frontend stack, background jobs, deployment target, traffic profile, compliance, current Rails version) and then route to the right downstream rails-skills. Use at the start of any new Rails work session, when the user says they want to "start a new Rails app", "set up a Rails project", "scaffold Rails", "build a Rails API", "build a Rails monolith", "build a Rails 8 app", or anytime they reference rails-skills without specifying which skill they want. Also use when reviewing or auditing an existing Rails codebase to determine which skills apply. This is the entry point of the rails-skills pack — almost every Rails task should start here.
---

# Rails Project Discovery

> Entry point for the `rails-skills` pack. Interview the developer in a short structured way, then load the right downstream skills. Do not start writing Rails code, generating files, or running `rails new` until the interview is complete and the relevant downstream skills are loaded.

## Why this skill exists

AI coding agents fail at Rails not because they don't know Ruby syntax — they fail because they don't know **which Rails** the user is on. A `rails new` for a Hotwire monolith looks nothing like a Rails-API + React SPA. A Rails 4 legacy app being migrated looks nothing like a greenfield Rails 8 app. Loading every skill in the pack into context wastes tokens and confuses the agent. This skill narrows the context to what matters.

## Rails 8 defaults (authoritative as of Rails 8.0)

When the user says "Rails 8 defaults," they mean this stack — confirmed against the [official Rails 8 launch post](https://rubyonrails.org/2024/11/7/rails-8-no-paas-required):

| Layer | Rails 8 default | Notes |
|---|---|---|
| Database | SQLite (in `rails new`); PostgreSQL is the standard production swap | Pass `--database=postgresql` for greenfield prod apps |
| Job adapter | **Solid Queue** | DB-backed; needs `FOR UPDATE SKIP LOCKED` (PG 9.5+, MySQL 8+, MariaDB 10.6+); Rails 8 itself requires Ruby 3.2+ |
| Cache store | **Solid Cache** | DB-backed; FIFO eviction; encrypted via Active Record Encryption |
| Cable adapter | **Solid Cable** | DB-backed pubsub; replaces Redis as Action Cable backend |
| Asset pipeline | **Propshaft** | Replaces Sprockets; only does load-path + digest stamping |
| JS bundling | **Importmap** | No Node toolchain by default |
| CSS | Plain CSS (`--css=tailwind` for Tailwind) | |
| Front-end interactivity | **Hotwire** (Turbo + Stimulus) | Server-rendered HTML over the wire |
| Test framework | **Minitest** | The DHH/Rails-core default. We cover RSpec patterns in `rspec-testing-pyramid` for teams who prefer it; the pyramid shape transfers either way |
| Auth | Built-in `bin/rails generate authentication` (Rails 8.0+) | Skip Devise for simple cases; use Devise/Rodauth for richer needs |
| Deploy | **Kamal 2** + Thruster + Kamal Proxy | Container-first, zero-downtime via `GET /up`, Let's Encrypt SSL auto |

Note these whenever the user says "use Rails 8 defaults" — don't second-guess unless they ask.

## The interview

Ask the questions below in order. Group them — don't ask one at a time. Wait for the user's full answer before proceeding to the next group. If the user has already answered some questions earlier in the conversation, skip them and confirm what you inferred.

If the user explicitly says "just go", "skip the questions", or "use defaults", apply the defaults marked `(default)` below and proceed.

### Group 1: Project shape (always ask)

> "Quick — six questions to load the right skills. (Say 'skip' to use defaults.)
>
> 1. **Is this a new project, an existing app, or a migration?** (greenfield / existing / upgrading-from-older-rails)
> 2. **App type?** (monolith with Hotwire (default) / API-only / API + separate SPA / microservice)
> 3. **Current Rails version** and, if upgrading, **target version**? (default greenfield: 8.0; e.g. existing: 4.2 → 8.0)
> 4. **Database?** (postgresql (default for prod) / mysql / sqlite / oracle / mssql)
> 5. **Background jobs?** (solid_queue (default for Rails 8) / sidekiq / good_job / none yet / not sure)
> 6. **Deployment target?** (kamal (default) / heroku / fly.io / render / AWS ECS / kubernetes / bare VM / not sure)"

### Group 2: Stack details (only if relevant from Group 1 answers)

If they answered "API + separate SPA" in Q2, also ask:

> 7. **Frontend framework?** (react / vue / angular / svelte / other)
> 8. **Auth approach?** (JWT (default for stateless) / session cookies / OAuth provider / not sure)

If they didn't answer "API + separate SPA":

> 7. **Auth?** (rails 8 built-in (default for Rails 8 greenfield) / devise / rodauth / clearance / custom / none yet)
> 8. **Frontend interactivity?** (hotwire (default) / minimal js / stimulus-only / heavy js)

### Group 3: Constraints (ask only for greenfield or significant new work)

> 9. **Expected traffic profile?** (low: <100 req/min / medium: 100–1k / high: 1k–10k / very high: >10k / not sure)
> 10. **Compliance requirements?** (none / HIPAA / PCI-DSS / SOC 2 / GDPR-strict / other)
> 11. **Team size working on this?** (solo / small 2–5 / medium 6–20 / large 20+)

### Group 4: External systems (ask only if Group 1 mentioned microservice, or the user mentioned integrations)

> 12. **Does this app need to talk to external services?** If yes, which? (other internal services / third-party REST APIs / message bus like Kafka/RabbitMQ / data warehouse / payment processor)

## After the interview: routing

Build a mental routing table from the answers and load the corresponding skills. Do not load skills the user won't need — that's the whole point of this interview.

### Universal skills (always load)

Regardless of answers, these apply to every Rails project:

- `activerecord-patterns`
- `rspec-testing-pyramid`
- `safe-migrations`
- `rails-security-baseline`
- `observability-baseline`
- `rubocop-and-code-quality`

### Conditional routing

| If the user answered… | Also load this skill |
|---|---|
| Greenfield Rails 8 monolith | `hotwire-turbo-stimulus`, `kamal-docker-production`, `rails-caching-strategy` (lighter coverage initially). Load `solid-queue-and-sidekiq` only after Q5 confirms background jobs |
| Greenfield Rails 8 with file uploads expected | `activestorage-uploads` |
| Greenfield any | `actionmailer-baseline` (almost every app sends email), `i18n-and-timezones` (set defaults from day one) |
| Existing Rails 4/5/6 staying on that version | `n-plus-one-killer`, `rails-caching-strategy`, `service-objects-vs-fat-models` |
| Upgrading from older Rails | One of `rails-upgrade-3-to-4`, `rails-upgrade-4-to-5`, `rails-upgrade-5-to-6`, `rails-upgrade-6-to-7`, `rails-upgrade-7-to-8` per current → target. Hop one minor version at a time. Use `next_rails` for dual-boot. |
| DB engine migration | `db-migration-postgres-mysql` / `db-migration-mysql-postgres` / `db-migration-oracle-postgres` |
| Monolith with Hotwire | `hotwire-turbo-stimulus`, `actiontext-richtext` if WYSIWYG; do NOT load React/Vue/Angular |
| API-only or API + SPA | `rails-api-design` |
| API + SPA (frontend specific) | `rails-api-design` + one of `react-with-rails`, `vue-with-rails`, `angular-with-rails` per Q7 |
| Background jobs needed | `solid-queue-and-sidekiq` |
| Auth at all | `devise-pundit-rodauth`. Rails 8 built-in auth is fine for low-complexity; suggest Devise once they need confirmable/recoverable, Rodauth when they need MFA/WebAuthn |
| Multi-tenant SaaS | `multi-tenancy` |
| Deployment to Kamal/Docker | `kamal-docker-production` |
| Setting up CI/CD | One of `ci-cd-github-actions-rails`, `ci-cd-gitlab-rails`, `ci-cd-jenkins-rails` per platform |
| High or very-high traffic | `rails-caching-strategy`, `n-plus-one-killer`, `puma-tuning-and-concurrency`, `multi-database-and-replicas`, `asset-pipeline-propshaft` |
| Search functionality | `rails-search` (pg_search → Meilisearch → ES tiering) |
| Stripe / payments | `pci-dss-rails`, `stripe-webhook-integration` |
| Webhooks (any provider) | `webhook-handling`, `stripe-webhook-integration` for Stripe specifically |
| Third-party REST APIs | `external-api-integration` |
| Feature flags / gradual rollout | `feature-flagging` |
| Forms spanning multiple models | `form-objects-query-objects-presenters` |
| HIPAA | `hipaa-rails` + `rails-security-baseline` + `observability-baseline` |
| PCI-DSS (card data) | `pci-dss-rails` + `stripe-webhook-integration` |
| SOC 2 | `soc2-rails` + `observability-rails-advanced` |
| GDPR / EU users | `gdpr-rails` |
| Microservice or splitting monolith | `when-NOT-to-use-microservices` FIRST. If they pass the gating, then `microservices-decomposition`, `monolith-to-services-extraction`, `event-driven-architecture` |
| Message bus / event streaming | `event-driven-architecture` + one of `kafka-rails`, `rabbitmq-rails`, `redis-streams-rails` |
| CDC / streaming DB changes downstream | `cdc-debezium-rails` |
| Cross-service tracing | `distributed-tracing-rails` |
| SLOs / on-call / advanced observability | `observability-rails-advanced` |
| Data warehouse / BI / analytics | `data-warehouse-integration` |
| Team size large (20+) | `service-objects-vs-fat-models` loaded earlier than usual |
| File uploads (avatars, attachments) | `activestorage-uploads` |
| Email features (transactional, marketing) | `actionmailer-baseline` |
| Running production console / data fixes | `console-safety-production` |

### After loading

Once skills are loaded, tell the user — in one short sentence per skill — what's loaded and what's not, and why. Then ask:

> "Loaded: \[skills]. Skipped: \[skills + brief reason]. Ready to start with: \[suggested first action based on their goal]. Sound right?"

This gives the user a chance to correct routing before you start work.

## Special cases

### "I just want to scaffold a new app"

Default stack to use unless the user says otherwise (Rails 8 greenfield):

```
rails new <name> \
  --database=postgresql \
  --css=tailwind \
  --javascript=importmap \
  --skip-test  # we'll add RSpec instead
```

After the app is generated, immediately:
1. Decide testing: keep Minitest (Rails default, lighter) OR add RSpec (`bundle add rspec-rails --group "development,test"` then `rails g rspec:install`). Default to Minitest unless the user asks for RSpec.
2. Generate the auth scaffold if they want simple auth: `bin/rails generate authentication`.
3. Confirm Solid Queue, Solid Cache, Solid Cable are wired (Rails 8 defaults).

Then load: `activerecord-patterns`, `rspec-testing-pyramid`, `safe-migrations`, `rails-security-baseline`, `kamal-docker-production`, `hotwire-turbo-stimulus`, `observability-baseline`. Mention other skills (`solid-queue-and-sidekiq` when they add the first background job, `rails-caching-strategy` when performance becomes a concern, `activestorage-uploads` when file uploads enter scope, etc.) but don't dump them into context now.

### "I'm joining an existing Rails project, help me understand it"

Skip Groups 3 and 4. Inspect rather than ask:

```
cat Gemfile.lock | head -20                # Rails + Ruby version
cat config/application.rb                  # mode (Rails::Application, Rails::API)
cat config/database.yml                    # database adapter
cat config/routes.rb | head -50            # API vs HTML routes
ls app/javascript app/views app/frontend   # SPA hint
bundle list | grep -E "devise|rodauth|pundit|sidekiq|solid_queue|jbuilder|jsonapi-serializer|alba|blueprinter|active_model_serializers|panko_serializer"
```

Then confirm what you inferred with the user before proceeding.

### "I want to upgrade from Rails X to Rails Y"

This is a multi-month process for non-trivial apps, not a single command. Do not generate an "upgrade in one shot" patch. Instead:

1. Confirm current Ruby + Rails versions from `Gemfile` and `Gemfile.lock`.
2. Confirm the target version.
3. Recommend the `next_rails` gem (latest 1.6.0+) for dual-booting: it creates `Gemfile.next` + `Gemfile.next.lock` and switches via `BUNDLE_GEMFILE`. Add `next_rails` outside any group so `NextRails.next?` is available everywhere.
4. Generate an upgrade plan, **one minor version at a time** (e.g. 4.2 → 5.0 → 5.1 → 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0). Never skip versions.
5. For each hop, the steps are: bump Gemfile, `bundle update rails`, run `rails app:update` (carefully review diffs in `config/`), run the test suite, fix deprecations, ship to staging, ship to prod, then begin the next hop.

Be honest: a 4→8 upgrade for a non-trivial app is weeks to months of work. This skill makes it tractable, not instant.

### "I want a microservice / SOA / event-driven architecture"

Load `when-NOT-to-use-microservices` first — it gates the entire conversation with a 6-question framework. Most teams under ~50 engineers should not adopt microservices; that skill explains why.

If they pass the gating, route to `microservices-decomposition`, `monolith-to-services-extraction`, `event-driven-architecture`, and one transport from `kafka-rails` / `rabbitmq-rails` / `redis-streams-rails`. Pair with `distributed-tracing-rails` for cross-service debugging.

## Anti-patterns to refuse

- **Do not** start running `rails new` or generating code before completing at least Group 1 of the interview.
- **Do not** load every skill "just in case." That defeats the point.
- **Do not** claim the pack can upgrade Rails versions "automatically" or "without judgment." Be honest about the human-in-the-loop steps.
- **Do not** recommend microservices for solo developers or teams under ~10 engineers (see special case above).
- **Do not** silently swap Solid Queue → Sidekiq, Solid Cache → Redis, or Hotwire → React without asking. Rails 8 picks defaults for reasons. If the user has a real need (existing Sidekiq investment, distributed cache, React team), surface the trade-off explicitly and let them choose.

## Example interview

**User:** "Help me start a new Rails project for a B2B SaaS."

**You:**
> Quick — six questions to load the right skills. (Say 'skip' for defaults.)
>
> 1. New project, existing, or upgrading?
> 2. App type? (Hotwire monolith / API-only / API + SPA / microservice)
> 3. Rails version target?
> 4. Database?
> 5. Background jobs?
> 6. Deployment target?

**User:** "New project. Hotwire monolith. Rails 8. Postgres. Yes background jobs. Kamal."

**You:**
> Two more:
> 7. Auth? (Rails 8 built-in / devise / rodauth / clearance / none yet)
> 8. Expected traffic to start? (low / medium / high)

**User:** "Devise. Low traffic to start, hoping to grow."

**You:**
> Loaded: activerecord-patterns, rspec-testing-pyramid, safe-migrations, rails-security-baseline, observability-baseline, solid-queue-and-sidekiq (Solid Queue half), devise-pundit-rodauth, kamal-docker-production, hotwire-turbo-stimulus, actionmailer-baseline.
>
> Skipped for now: rails-caching-strategy (load when perf becomes an issue), n-plus-one-killer (load when you see slow queries), service-objects-vs-fat-models (load when a controller action gets ugly), rails-api-design (load when you add a JSON API later), activestorage-uploads (load when you add file uploads).
>
> Suggested first action: scaffold the app with `rails new <name> --database=postgresql --css=tailwind --skip-test`, then add RSpec + Devise + Pundit + Solid Queue. Sound right?

---

## When NOT to use this skill

- The user explicitly names a single downstream skill (e.g. "use the n-plus-one-killer skill on this file"). Skip discovery and go straight to that skill.
- The user is asking a one-off Rails question with no project context (e.g. "what's the difference between `find_by` and `where.first`?"). Just answer.
- The user is mid-refactor of a single file and asks for a focused change. Don't re-interview — keep the context narrow.

## See also

- `_TEMPLATE/SKILL.md` — clone for every new skill
- `CLAUDE.md` (project root) — principles, conventions, quality bar
- `PLAN.md` (project root) — full roadmap of v0.1, v0.2, v0.3 skills

## Sources

Research used to construct this orchestrator (live URLs at time of writing):

- [Anthropic Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview) — frontmatter rules, progressive disclosure, skill discovery
- [Rails 8 launch post — "No PaaS required"](https://rubyonrails.org/2024/11/7/rails-8-no-paas-required) — confirmed defaults
- [Rails Guides — Getting Started](https://guides.rubyonrails.org/getting_started.html) — `rails new` flags
- [Solid Queue README](https://github.com/rails/solid_queue) — Rails 8 job adapter requirements
- [Solid Cache README](https://github.com/rails/solid_cache) — DB-backed cache
- [Kamal 2 docs](https://kamal-deploy.org/) — deployment model and `/up` health check
- [Hotwire intro](https://hotwired.dev/) — Turbo + Stimulus components
- [Devise README](https://github.com/heartcombo/devise) — modules + Rails 7+ requirement
- [Rodauth README](https://github.com/jeremyevans/rodauth) — advanced auth alternative
- [Pundit README](https://github.com/varvet/pundit) — policy + scope pattern
- [strong_migrations README](https://github.com/ankane/strong_migrations) — dangerous operations
- [next_rails README](https://github.com/fastruby/next_rails) — dual-boot upgrade path
- [Bullet README](https://github.com/flyerhzm/bullet) — N+1 detection
