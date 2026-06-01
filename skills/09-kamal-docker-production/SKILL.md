---
name: kamal-docker-production
description: Production Docker and Kamal 2 deployment for Ruby on Rails 8 — multi-stage Dockerfile with build/runtime separation, ruby:3.x-slim over alpine (avoiding musl gotchas with nokogiri/pg/sassc), docker-compose for development with Postgres + Redis, Kamal 2 deploy.yml, zero-downtime via Kamal Proxy and the GET /up health check, secrets via Kamal envs + Rails credentials, log shipping. Use when writing or reviewing a Dockerfile for Rails, setting up Kamal, debugging deploy failures, the user mentions Dockerfile, docker-compose, Kamal, Kamal Proxy, Thruster, multi-stage builds, alpine vs slim, native gem compilation, kamal deploy, zero-downtime, or asks how to ship a Rails 8 app to production.
---

# Kamal + Docker for Rails Production

> Ship a Rails 8 app to production without managing Kubernetes or paying Heroku 10× markup. AI agents generate Dockerfiles that work but waste 500MB of image size and 4 minutes of build time. They reach for `alpine` and trip on native gem compilation. This skill encodes the choices a senior infra-aware Rails dev makes.

## Why this matters

Rails 8 ships a `Dockerfile` out of the box, plus Kamal 2 for deployment. Both are good. But the defaults need understanding — what to keep, what to customize, and how to wire secrets without leaking them to images or logs.

## The opinion

> **Use the Rails-generated multi-stage `Dockerfile` as the starting point. Base on `ruby:3.x-slim` (debian-slim), not `alpine` — alpine's musl libc causes subtle native-gem failures with nokogiri, pg, sassc, and libvips. Use `bin/docker-entrypoint` for runtime setup (db:prepare). Deploy with Kamal 2. Use Rails credentials for app secrets, Kamal envs (`.kamal/secrets`) for deployment secrets. Health check at `GET /up`. Never put secrets in the Dockerfile.**

Counter-positions:
- **Distroless** base images (gcr.io/distroless) are smaller and safer than `slim`, but every native gem becomes a debugging session. Worth it for super-locked-down envs; over-investment for most.
- **Heroku, Fly.io, Render** — managed PaaS. Trade money for engineer-hours. Pick if the team's time is better spent on product than ops. Kamal is the answer when you've decided you want your own VMs.
- **Kubernetes** — appropriate when you actually need its features (multi-cluster, auto-scaling on real signals, multi-team isolation). Don't pick K8s for a single Rails app.

## Core patterns

### Pattern 1: Multi-stage Dockerfile

```dockerfile
# syntax=docker/dockerfile:1
# Pin major+minor; pin patch for reproducibility
ARG RUBY_VERSION=3.3.7
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app directory
WORKDIR /rails

# Common deps both stages need
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libjemalloc2 libvips postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Production env defaults
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    RAILS_SERVE_STATIC_FILES="1" \
    RAILS_LOG_TO_STDOUT="1" \
    MALLOC_ARENA_MAX="2" \
    LD_PRELOAD="libjemalloc.so.2"

# ===== BUILD STAGE =====
FROM base AS build

# Build deps — only here, not in runtime image
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git pkg-config libpq-dev libyaml-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Bundle install — cache-friendly: copy Gemfiles first, then app
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs=4 --retry=3 && \
    bundle exec bootsnap precompile --gemfile && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy app code
COPY . .

# Precompile bootsnap caches + assets
RUN bundle exec bootsnap precompile app/ lib/ && \
    SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

# ===== RUNTIME STAGE =====
FROM base AS runtime

# Copy gems and app from build stage
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Non-root user — defense in depth
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER rails:rails

# Entrypoint runs db:prepare on boot; exec replaces shell
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
```

**Why each line matters:**
- `RUBY_VERSION` arg makes the upgrade a one-line change.
- `-slim` over `-alpine`: avoids musl/glibc divergence with nokogiri, pg, sassc, libvips.
- `BUNDLE_WITHOUT`: build/test gems aren't shipped to prod.
- `MALLOC_ARENA_MAX=2` + `LD_PRELOAD=libjemalloc.so.2`: fragmentation control. Cuts memory by 20-40% on long-running Rails procs.
- Build stage installs `build-essential`, etc.; runtime stage doesn't. ~400MB saved.
- `assets:precompile` in build stage — runtime image has compiled assets, not the build toolchain.
- Non-root user: defense in depth if a process is compromised.
- `bin/thrust` is Thruster (built into Rails 8), proxying behind Kamal Proxy.

### Pattern 2: `bin/docker-entrypoint`

```bash
#!/bin/bash -e
# bin/docker-entrypoint — run before CMD

# Prepare the database if it doesn't exist yet (first-time boot)
if [ "${@: -2:1}" == "./bin/rails" ] && [ "${@: -1:1}" == "server" ]; then
  ./bin/rails db:prepare
fi

exec "${@}"
```

**Why `db:prepare`** (not `db:migrate` or `db:setup`): `db:prepare` is idempotent — creates the database if missing, otherwise runs pending migrations. Safe for fresh deploys AND for rolling restarts.

**Anti-pattern:** running `db:migrate` on every container boot. With Kamal's rolling deploys, multiple containers fire `db:migrate` simultaneously — they all try to grab the same advisory lock. Run migrations in a dedicated step in `deploy.yml` (`deploy.pre.cmds`), not the entrypoint.

### Pattern 3: docker-compose for development

```yaml
# docker-compose.yml — for local dev only, NOT prod
services:
  web:
    build:
      context: .
      target: build  # use the build stage so dev gems work
    command: bin/rails server -b 0.0.0.0
    ports:
      - "3000:3000"
    volumes:
      - .:/rails
      - bundle:/usr/local/bundle
      - node_modules:/rails/node_modules
    environment:
      DATABASE_URL: postgres://postgres:postgres@db:5432/myapp_development
      REDIS_URL: redis://redis:6379/0
      RAILS_ENV: development
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: myapp_development
    volumes:
      - postgres-data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

  worker:
    build:
      context: .
      target: build
    command: bin/jobs  # Solid Queue worker
    volumes:
      - .:/rails
      - bundle:/usr/local/bundle
    environment:
      DATABASE_URL: postgres://postgres:postgres@db:5432/myapp_development
    depends_on:
      db:
        condition: service_healthy

volumes:
  postgres-data:
  bundle:
  node_modules:
```

**Why `target: build`** in dev: dev needs build-essential, sass compilation, JS toolchain. The runtime stage strips those.

**Postgres `alpine` is fine in dev** — Postgres' alpine image doesn't have the native-gem problem (it's not running Ruby).

### Pattern 4: Kamal 2 `config/deploy.yml`

```yaml
service: myapp
image: yourregistry.io/myapp

servers:
  web:
    hosts:
      - 1.2.3.4
      - 5.6.7.8
    options:
      "add-host": host.docker.internal:host-gateway
  jobs:
    hosts:
      - 9.10.11.12
    cmd: bin/jobs  # Solid Queue worker

proxy:
  ssl: true
  host: myapp.example.com
  app_port: 80
  healthcheck:
    interval: 3
    path: /up
    timeout: 3

registry:
  server: yourregistry.io
  username: your-username
  password:
    - KAMAL_REGISTRY_PASSWORD  # from .kamal/secrets

env:
  clear:
    RAILS_LOG_TO_STDOUT: 1
    RAILS_SERVE_STATIC_FILES: 1
    SOLID_QUEUE_IN_PUMA: false
    DB_HOST: postgres-internal  # accessory below
    REDIS_URL: redis://redis-internal:6379/0
  secret:
    - RAILS_MASTER_KEY  # from .kamal/secrets
    - POSTGRES_PASSWORD
    - STRIPE_SECRET_KEY

builder:
  arch: amd64  # match your servers
  cache:
    type: registry

accessories:
  postgres:
    image: postgres:16
    host: 1.2.3.4
    port: "5432:5432"
    env:
      clear:
        POSTGRES_USER: rails
        POSTGRES_DB: myapp_production
      secret:
        - POSTGRES_PASSWORD
    files:
      - config/postgres/init.sql:/docker-entrypoint-initdb.d/setup.sql
    directories:
      - data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    host: 1.2.3.4
    port: "6379:6379"
    directories:
      - data:/data

aliases:
  console: app exec --interactive --reuse "bin/rails console"
  shell: app exec --interactive --reuse "bash"
  logs: app logs -f
  dbc: app exec --interactive --reuse "bin/rails dbconsole"
```

**Key choices explained:**
- `proxy.healthcheck.path: /up` — Rails 7.1+ ships `GET /up` returning 200 if the app booted. Kamal Proxy waits for 200 before routing traffic. Zero-downtime is automatic.
- `env.secret` interpolates from `.kamal/secrets`; never plain-text in `deploy.yml`.
- `accessories` brings up Postgres and Redis as Kamal-managed containers on the same host or a separate one. Good for small deployments; swap to a managed DB at scale.
- `jobs` role with `cmd: bin/jobs` — Solid Queue worker process. For Sidekiq, replace with `bundle exec sidekiq -e production`.

### Pattern 5: Secrets — three layers

```
.kamal/secrets               ← deployment-time secrets (registry pw, Rails master key)
                                  Used by Kamal CLI; gitignored.

config/credentials.yml.enc   ← runtime app secrets (Stripe keys, etc.)
                                  Decrypted at boot via RAILS_MASTER_KEY.
                                  Committed; encrypted.

env vars (Kamal env.secret)  ← runtime infra secrets (DB password, Redis URL)
                                  Injected at container start.
```

```bash
# .kamal/secrets — gitignored
KAMAL_REGISTRY_PASSWORD=...
RAILS_MASTER_KEY=$(cat config/master.key)
POSTGRES_PASSWORD=...
STRIPE_SECRET_KEY=...
```

**Why three layers:**
- Kamal secrets exist for the deploy step only. They're not in the container.
- Rails credentials are encrypted-at-rest in the repo. The master key decrypts them at boot.
- Env vars are injected at container start. Visible inside the container; never logged.

**Never:**
- Commit `.kamal/secrets` or `config/master.key`.
- Put secrets in `Dockerfile` (image layers preserve them forever).
- Put secrets in `env.clear` (visible in `kamal env`).
- Echo secrets in build logs.

### Pattern 6: Health check

```ruby
# config/routes.rb
get "/up", to: "rails/health#show", as: :rails_health_check
```

Rails 8 ships this route. Returns 200 if the app responds at all (Rack stack is up). For deeper checks (DB reachable, Redis reachable, Sidekiq workers running), add a second endpoint:

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    checks = {
      db: db_ok?,
      redis: redis_ok?,
      solid_queue: solid_queue_ok?
    }

    status = checks.values.all? ? :ok : :service_unavailable
    render json: { status: status, checks: checks }, status: status
  end

  private

  def db_ok?
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue
    false
  end

  def redis_ok?
    Redis.new(url: ENV["REDIS_URL"]).ping == "PONG"  # Redis.current was removed in redis-rb 5
  rescue
    false
  end

  def solid_queue_ok?
    SolidQueue::Process.where("last_heartbeat_at > ?", 1.minute.ago).any?
  rescue
    false
  end
end
```

**Use `/up` for Kamal Proxy** (cheap, fast). Use `/health` for monitoring (Datadog, Pingdom) — runs every few minutes, can afford the DB check.

### Pattern 7: Migrations on deploy

Kamal 2 invokes shell scripts under `.kamal/hooks/`. The naming determines the lifecycle phase. Create:

```bash
# .kamal/hooks/pre-deploy   (chmod +x)
#!/usr/bin/env bash
set -euo pipefail
kamal app exec --reuse "bin/rails db:migrate"
```

```bash
chmod +x .kamal/hooks/pre-deploy
git add .kamal/hooks/pre-deploy
```

Kamal runs the script once per deploy, on the deploying host, before new app containers route traffic.

**Why a hook script (not a `migrate` role):** Kamal 2 removed the `once: true` role keyword from earlier versions. The hook script is the supported one-shot pattern, runs once, and you can extend it (`db:migrate`, then warm a cache, then verify health).

### Pattern 8: Log shipping

Production logs go to stdout (`RAILS_LOG_TO_STDOUT=1`). Capture them at the container level:

**Option A: docker logging driver to syslog / journald / awslogs / fluentd:**

```yaml
# deploy.yml
servers:
  web:
    options:
      "log-driver": "awslogs"
      "log-opt":
        "awslogs-group": "/myapp/web"
        "awslogs-region": "us-east-1"
```

**Option B: vector / fluent-bit / promtail sidecar:**

Run a log collector container alongside, tailing the docker socket or `/var/lib/docker/containers`. Ships to Loki, Elasticsearch, S3, CloudWatch.

**Why stdout (not log file):** containers are ephemeral. Files inside containers vanish on redeploy. Stdout streams to a durable backend.

## Decision matrix

| Question | Answer |
|---|---|
| Base image | `ruby:3.x-slim` (debian) |
| Multi-stage? | Yes — build + runtime |
| Dev orchestration | docker-compose |
| Prod deployment | Kamal 2 |
| App secrets | Rails credentials |
| Infra secrets | Kamal env.secret + .kamal/secrets |
| Health check | `/up` (Rails 8 built-in) + optional `/health` |
| Migrations on deploy | Kamal hook OR migrate role, NOT entrypoint |
| Logs | stdout → driver/sidecar → durable backend |
| jemalloc? | Yes — `LD_PRELOAD=libjemalloc.so.2` |
| Non-root user? | Yes |

## Common mistakes to refuse

- Don't use `alpine` for the Ruby base image. Musl libc breaks subtly with native gems.
- Don't ship the build toolchain (build-essential, git) in the runtime image.
- Don't run as root in production containers.
- Don't commit `.kamal/secrets` or `config/master.key`.
- Don't run `db:migrate` from `docker-entrypoint` — race on rolling deploys.
- Don't log `RAILS_LOG_TO_FILE`; logs vanish on container exit.
- Don't put secrets in `env.clear` in `deploy.yml` — visible in `kamal env`.
- Don't put secrets in the `Dockerfile` (image layers preserve them).
- Don't expose Postgres / Redis ports to the internet — use Kamal's internal network only.

## When NOT to use this skill

- The team is committed to a managed PaaS (Heroku, Fly.io, Render) — Kamal is overkill.
- The team is on Kubernetes — different deployment tooling.

## See also

- `rails-security-baseline` — secrets management deep dive
- `observability-baseline` — log shipping integration
- `solid-queue-and-sidekiq` — worker container configuration
- Coming in v0.2: `puma-tuning-and-concurrency` — Puma worker counts, memory tuning

## Bundled assets

- [`assets/Dockerfile.production`](assets/Dockerfile.production) — drop-in multi-stage Dockerfile
- [`assets/docker-compose.dev.yml`](assets/docker-compose.dev.yml) — dev with PG + Redis + Solid Queue
- [`assets/deploy.yml`](assets/deploy.yml) — Kamal 2 sample

## Sources

- [Rails 8 launch — "No PaaS required"](https://rubyonrails.org/2024/11/7/rails-8-no-paas-required)
- [Kamal 2 docs](https://kamal-deploy.org/)
- [Thruster README](https://github.com/basecamp/thruster) — built-in proxy
- [Kamal Proxy README](https://github.com/basecamp/kamal-proxy)
- [Rails generated Dockerfile (rails/rails master)](https://github.com/rails/rails)
- [jemalloc Ruby performance](https://www.speedshop.co/2017/12/04/malloc-doubles-ruby-memory.html) — Nate Berkopec
- [Alpine vs slim trade-offs](https://pythonspeed.com/articles/alpine-docker-python/) — generalizes to Ruby
- [Docker logging drivers](https://docs.docker.com/config/containers/logging/configure/)
- [Postgres connection pooling on Kamal](https://github.com/basecamp/kamal/discussions) — community guidance
- [Rails health check route](https://guides.rubyonrails.org/configuring.html#configuring-rails-components) — `/up` documentation
