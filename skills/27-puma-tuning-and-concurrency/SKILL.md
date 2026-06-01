---
name: puma-tuning-and-concurrency
description: Tune Puma for production Rails 8 — worker process count (CPUs × 1.5), thread count per worker (3-5 default), memory budget per worker, jemalloc, preload_app + fork-safe initializers, the Ruby 3+ YJIT enable, GIL implications for thread count, signal handling, restart strategies, MALLOC_ARENA_MAX. Use when the user mentions Puma config, workers, threads, jemalloc, memory bloat, copy-on-write, WEB_CONCURRENCY, RAILS_MAX_THREADS, MALLOC_ARENA_MAX, or asks how many workers / threads to run.
---

# Puma Tuning + Concurrency

> A misconfigured Puma is the most common Rails performance issue after N+1. Defaults are conservative; the right tuning depends on workload (I/O-bound vs CPU-bound), memory budget, and Ruby version. This skill encodes the formulas.

## The opinion

> **Workers = CPU cores × 1.5 (I/O-bound) or = CPU cores (CPU-bound). Threads per worker = 3-5. `preload_app!` + fork-safe initializers (re-establish DB connections after fork). `MALLOC_ARENA_MAX=2` + jemalloc. YJIT on for Ruby 3.3+. Plan for ~300-500MB per worker after warm-up.**

Counter-position: Falcon and Iodine offer event-loop concurrency that beats Puma on pure I/O workloads. For 95% of Rails apps, Puma is the right answer.

## The formulas

```
WORKERS  = max(2, CPU_cores × 1.5)         # I/O bound (most Rails apps)
WORKERS  = CPU_cores                        # CPU bound (heavy serialization, image processing)
THREADS  = 5                                # safe default; tune up to 10 for I/O-heavy
TOTAL    = WORKERS × THREADS                # concurrent requests handled
MEMORY   = WORKERS × 400MB                  # rough budget after warm-up
```

**Example:** 4 CPUs, I/O-bound app → 6 workers × 5 threads = 30 concurrent requests. ~2.4GB RAM budget.

## Core patterns

### Pattern 1: `config/puma.rb` — production-tuned

```ruby
# config/puma.rb
threads_count = ENV.fetch("RAILS_MAX_THREADS", 5).to_i
threads threads_count, threads_count

worker_count = ENV.fetch("WEB_CONCURRENCY", 4).to_i
workers worker_count

port ENV.fetch("PORT", 3000)
environment ENV.fetch("RAILS_ENV", "development")

preload_app!  # fork once, share memory via copy-on-write

# After fork: each worker re-establishes DB + cache connections
on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
  Rails.cache.reconnect if Rails.cache.respond_to?(:reconnect)
end

# Optional: run Solid Queue in-Puma (small apps). Use the official plugin.
# plugin :solid_queue   # requires solid_queue 0.3+
# In production, prefer running solid_queue as a separate `bin/jobs` process.

# Before fork: close parent DB connections so they don't leak into children
before_fork do
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
end

# Graceful restart support
plugin :tmp_restart

# NOTE: MALLOC_ARENA_MAX must be set in the container/shell env BEFORE the
# Ruby process starts — setting it here is too late for glibc's allocator.
# In your Dockerfile / Kamal env:  ENV MALLOC_ARENA_MAX=2
```

**Why each setting:**
- `threads x, x` — min and max thread pool sizes equal; avoids stalls on autoscale.
- `WEB_CONCURRENCY` — environment variable controls worker count; tunable without redeploy.
- `preload_app!` — load Rails once, fork workers. Copy-on-write means initial memory is shared.
- `on_worker_boot` — DB connections, cache clients, etc. must be re-established after fork.
- `MALLOC_ARENA_MAX=2` — reduces glibc malloc fragmentation. Combined with jemalloc, cuts memory 20-40%.

### Pattern 2: jemalloc

```dockerfile
# In your Dockerfile (slim base image)
RUN apt-get install -y libjemalloc2
ENV LD_PRELOAD=libjemalloc.so.2
ENV MALLOC_CONF=narenas:2
```

Long-running Ruby processes fragment glibc's allocator significantly. jemalloc handles it better — typically 20-40% memory reduction on a Rails process at the 1-hour mark.

### Pattern 3: YJIT (Ruby 3.3+)

```bash
# Enable globally
export RUBY_YJIT_ENABLE=1
# or per-process: ruby --yjit
```

10-25% throughput improvement for typical Rails workloads. Memory cost ~50-150MB per process. Worth it for any Rails app where compute is non-trivial.

```ruby
# config/boot.rb (Ruby 3.3+ ships YJIT bundled, no require needed)
RubyVM::YJIT.enable if defined?(RubyVM::YJIT)
```

### Pattern 4: Sizing workers

```ruby
# Quick formula at runtime:
workers = (ENV["WEB_CONCURRENCY"] || (Etc.nprocessors * 1.5).floor).to_i
```

**On Heroku / Render** (1 CPU per dyno): `WEB_CONCURRENCY=2` is a sane default.
**On Kamal-hosted multi-core VMs:** scale with cores.

**Memory check:**

```
Available RAM / 400 MB ≥ WEB_CONCURRENCY
```

If you can't fit, drop workers and add threads — but threads share a process's memory.

### Pattern 5: Sizing threads

GIL (Ruby's global VM lock) means only one thread runs Ruby code at a time per process. But:

- I/O (DB queries, HTTP requests, file reads) releases the GIL.
- A request that's 80% DB time effectively uses 20% of a Ruby thread.

So 5 threads per worker is fine for I/O-heavy apps. For CPU-heavy, 1-2 threads per worker — extra threads contend for the GIL without helping.

**Heuristic:** start at `THREADS=5`. Monitor `puma_busy_threads` metric. If hitting ceiling regularly, scale workers (not threads).

### Pattern 6: Memory bloat detection — `puma_worker_killer`

```ruby
# Gemfile
gem "puma_worker_killer"

# config/puma.rb — configure ONCE at top level (master process), not in before_fork.
# before_fork runs on every worker fork, which would spawn duplicate killer threads.
PumaWorkerKiller.config do |config|
  config.ram = 4096  # MB available
  config.frequency = 5  # check every 5 seconds
  config.percent_usage = 0.98  # 98% threshold
  config.rolling_restart_frequency = 12.hours  # rolling worker restarts
  config.reaper_status_logs = false
end
PumaWorkerKiller.start
```

**When you need this:** workers grow over hours (memory leaks, large object caches). Rolling restarts keep memory bounded.

**Anti-pattern:** ignoring the leak. PWK is a workaround. Fix the root cause when you can.

### Pattern 7: Signal handling

- `SIGTERM` — graceful shutdown. Puma waits for in-flight requests up to `worker_timeout`.
- `SIGUSR1` — graceful restart. Workers re-fork one at a time. Zero-downtime.
- `SIGUSR2` — phased restart (alias).
- `SIGHUP` — reopen logs (rotate).

Kamal sends SIGTERM by default. Make sure `worker_timeout` is shorter than the orchestrator's grace period.

### Pattern 8: When Puma isn't the answer

| Workload | Better fit |
|---|---|
| 10k+ concurrent connections (chat, websockets) | Falcon (Ruby) or move to dedicated WebSocket server |
| Long-polling endpoints | Falcon or rack-attack-style decoupling |
| Pure async I/O (lots of HTTP fan-out) | Concurrent::Promises in jobs, NOT Puma threads |
| Very high RPS, low compute | Falcon |

For most Rails apps: Puma is the right answer.

## Decision matrix

| Resource | Target |
|---|---|
| Workers | CPU × 1.5 (I/O) or CPU × 1 (CPU-bound) |
| Threads per worker | 5 (start); 3 if CPU-bound; up to 10 if I/O-bound |
| Memory per worker | ~400 MB after warm-up |
| YJIT | On (Ruby 3.3+) |
| jemalloc | On |
| MALLOC_ARENA_MAX | 2 |
| Phased restart | Yes (SIGUSR1) |
| PumaWorkerKiller | Only if you can't fix the leak |

## Common mistakes to refuse

- Don't pick threads = 25 to "be safe". GIL means most threads contend.
- Don't pick workers = 16 on a 2-CPU machine. You'll spend all time context-switching.
- Don't run preload_app! without `on_worker_boot` DB reconnect.
- Don't enable YJIT and tune nothing else — measure first.
- Don't ignore puma_worker_killer alerts — fix the leak.
- Don't run Sidekiq + Solid Queue + Puma in the same process at high traffic — separate worker container.

## When NOT to use this skill

- The user is asking about Kamal deployment specifically — that's `kamal-docker-production`.
- The user is asking about web server choice (Puma vs Falcon vs Unicorn) generally — touch lightly, deep dive is out of scope.

## See also

- `kamal-docker-production` — container memory limits
- `observability-baseline` — monitor `puma_busy_threads`, `puma_pool_capacity`
- `solid-queue-and-sidekiq` — when async work moves out of Puma

## Sources

- [Puma config reference](https://github.com/puma/puma)
- [Nate Berkopec — Sizing Puma](https://www.speedshop.co/2017/10/12/appserver.html)
- [Speedshop — Puma in Production](https://www.speedshop.co/)
- [jemalloc and Ruby](https://www.speedshop.co/2017/12/04/malloc-doubles-ruby-memory.html)
- [YJIT docs](https://github.com/ruby/ruby/blob/master/doc/yjit/yjit.md)
- [Heroku Puma sizing](https://devcenter.heroku.com/articles/deploying-rails-applications-with-the-puma-web-server)
- [PumaWorkerKiller](https://github.com/zombocom/puma_worker_killer)
