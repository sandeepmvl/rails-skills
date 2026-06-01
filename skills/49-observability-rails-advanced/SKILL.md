---
name: observability-rails-advanced
description: Production-grade observability for Rails — RED + USE metrics, SLO / SLI / error budgets, multi-window multi-burn-rate alerting (Google SRE workbook), exemplars linking metrics to traces, log levels and sampling, alerting hygiene (paging only on customer impact), runbooks, on-call rotations. Use when the user mentions SLOs, error budgets, alerting, runbooks, RED, USE, "what should we monitor", paging strategy, alerting fatigue, Prometheus + Grafana stack, or production observability beyond basic logging.
---

# Observability — Advanced

> Beyond "we have logs + Sentry." This skill is about deciding WHAT to alert on, HOW LOUDLY, and ensuring on-call is woken only when a human can do something useful.

## The opinion

> **Define SLOs first, alerts second. Use multi-window multi-burn-rate alerts (Google SRE Workbook) — alert when the error budget is burning fast OR slowly over a long window. Page only on customer-impacting events. Everything else is a ticket. Maintain runbooks for every alert. Use Prometheus + Grafana + Alertmanager as the open-source default; Datadog if you're willing to pay. Pair metrics with OTel exemplars so a Grafana panel can jump to a trace.**

## The four observability signals

| | What | Default tool |
|---|---|---|
| **Logs** | Discrete events, debug detail | structured JSON via lograge → Loki / Datadog Logs / Elastic |
| **Metrics** | Aggregated time series | Prometheus / Datadog |
| **Traces** | Cross-service request flow | OpenTelemetry → Tempo / Honeycomb / Datadog APM |
| **Errors** | Exceptions with context | Sentry / Rollbar / Datadog Errors |

See `observability-baseline` for setup; this skill is about strategy.

## Pattern 1: RED for services

For every HTTP service / consumer / job worker:

- **R**ate — requests per second.
- **E**rrors — failures per second.
- **D**uration — latency histogram (p50/p95/p99).

```ruby
# prometheus_exporter gem; instrument middleware to emit
require "prometheus_exporter/middleware"
Rails.application.config.middleware.unshift PrometheusExporter::Middleware
```

Grafana panels per service (metric names illustrative — match what your exporter emits, e.g., `prometheus_exporter` uses `http_req_total` + `http_req_duration_seconds`):
- `rate(http_req_total[5m])`
- `rate(http_req_total{status=~"5.."}[5m]) / rate(http_req_total[5m])`
- `histogram_quantile(0.99, rate(http_req_duration_seconds_bucket[5m]))`

## Pattern 2: USE for infrastructure

For every resource (CPU, RAM, disk, network, DB connections):

- **U**tilization — % busy.
- **S**aturation — queue depth waiting for resource.
- **E**rrors — error count.

DB-specific:
- Connection pool utilization
- Replica lag (see `multi-database-and-replicas`)
- Slow query rate

Redis-specific:
- Memory used / max
- Evicted keys (cache thrashing)
- Connection refusals

## Pattern 3: SLOs

A Service Level Objective is a target for customer-visible behavior.

```yaml
# Example SLO
service: orders-api
slo:
  availability: 99.9% over 30 days
  latency:
    p99: 500ms over 30 days
    threshold_window: 28 days
```

99.9% availability over 30 days = 43 minutes of allowed downtime. That's the error budget.

**Why SLOs not SLAs:** an SLA is a contract with the customer. An SLO is the internal target you actually engineer to (usually tighter than the SLA).

## Pattern 4: Multi-window multi-burn-rate alerts

Naive: "alert if error rate > 1% over 5 minutes." Alerts on every tiny blip, ignores slow burns.

Better: alert when you'd burn the entire 30-day budget in N hours.

```yaml
# Prometheus alert rule
- alert: HighErrorBudgetBurnFast
  expr: |
    (
      job:slo_errors:ratio_rate1h{job="orders-api"} > (14.4 * 0.001)
      and
      job:slo_errors:ratio_rate5m{job="orders-api"} > (14.4 * 0.001)
    )
  for: 2m
  labels:
    severity: page
  annotations:
    summary: "Orders API burning error budget 14x faster than allowed (1h window)"
    runbook: "https://runbooks.company.com/orders-api-error-budget"
```

Two windows (5m + 1h). Both must trigger. This prevents flapping AND catches slow burns.

The full Google SRE Workbook scheme has 4 alerts per SLO at different burn rates / windows. Adopt it once you have an SLO definition.

## Pattern 5: Pager hygiene

A page MUST mean:
- Customer impact is happening or imminent.
- A human can fix it from oncall.
- Not waiting will make it worse.

Anything else is a ticket. The fastest way to wreck on-call morale is paging for things that "can wait til morning."

Audit every alert quarterly:
- Did it page in the last 90 days?
- When it paged, did the responder take action?
- Was the action documented in a runbook?

If "no" to any: rewrite or delete the alert.

## Pattern 6: Runbooks

Every alert links to a runbook with:

1. **What this means** — what's happening that triggered this.
2. **Symptoms** — what users see.
3. **Diagnostics** — how to confirm.
4. **Remediation** — step-by-step fixes, in order of cheapest first.
5. **Escalation** — who to involve if remediation fails.

Markdown in a runbooks repo. Link from every alert annotation.

```markdown
# Orders API — Error Budget Burn

## What this means
Customer-visible error rate is exceeding the SLO budget burn threshold.

## Symptoms
- Users see HTTP 500s on checkout
- Sentry events for OrdersController spiking

## Diagnostics
1. Grafana dashboard: orders-api → error rate panel
2. `kubectl logs -l app=orders-api --since=10m | grep ERROR`
3. Sentry: `service:orders-api environment:production`

## Remediation
1. Check recent deploy. Roll back if last 30min.
2. Check downstream services (Payment, Inventory) — see their dashboards.
3. Check DB. PgBouncer connections — `pgbouncer-cli show pools`.

## Escalation
If unresolved after 30 minutes, page #incident-orders.
```

## Pattern 7: Exemplars (metrics ↔ traces)

A spike in p99 latency is not actionable until you know WHICH requests were slow. Exemplars link a histogram bucket to specific trace IDs.

**Caveat:** the `prometheus-client` Ruby gem (4.x) does not yet emit exemplar annotations in its exposition format. For trace-linked exemplars today, use the OTel SDK's metrics pipeline (`opentelemetry-metrics-sdk` + OTLP exporter), which emits exemplars natively. Alternatively, label your histogram with a `trace_id` (high cardinality, expensive) so Grafana can filter:

```ruby
HISTOGRAM = Prometheus::Client::Histogram.new(
  :order_processing_duration_seconds,
  docstring: "...",
  labels: [:trace_id]
)

duration = Benchmark.realtime { process_order(order) }
HISTOGRAM.observe(duration, labels: { trace_id: OpenTelemetry::Trace.current_span.context.hex_trace_id })
```

Cardinality cost is real — only label like this on low-traffic paths or sample.

In Grafana with OTLP-emitted exemplars: click a histogram bucket → "Show exemplars" → click a trace_id → jump to the trace.

Pairs with `distributed-tracing-rails`.

## Pattern 8: Log levels in production

```
DEBUG  — disabled
INFO   — request logs, business events
WARN   — degraded but functioning (cache miss, retry)
ERROR  — operation failed but request continues
FATAL  — request failed, customer impact
```

In production: INFO + above. Sample DEBUG if you really need it.

Sample high-volume logs:

```ruby
# Sample 1% of cache-hit logs but 100% of cache-miss
Rails.logger.info(cache_status: "hit") if rand < 0.01
Rails.logger.info(cache_status: "miss")
```

## Pattern 9: Alerting on the right metrics

Alert on **symptoms** (what customers see), not **causes** (what's broken inside).

| ❌ Cause-based | ✅ Symptom-based |
|---|---|
| Sidekiq queue depth > 10000 | Email send latency p99 > 5min |
| Postgres CPU > 80% | API p99 latency > SLO |
| Redis memory > 90% | Cache hit rate < threshold |

Cause-based alerts fire constantly and don't always mean customer impact. Symptom-based alerts fire only when there's something to fix.

## Pattern 10: Error budgeting policy

Define what happens when you burn budget:

```
> 50% of monthly budget consumed: freeze risky deploys; prioritize reliability work.
> 100% consumed: code freeze; engineering manager + product agree on next steps.
```

Make it cheap to roll back. Make it cheap to deploy fixes. If you're freezing every month, you're under-investing in reliability.

## Common mistakes to refuse

- Don't alert on every error. Define what's customer-visible.
- Don't page for "queue is non-empty." Alert on customer-visible symptom.
- Don't skip runbooks. Alerts without runbooks rot.
- Don't measure everything 100% of the time at high cardinality. Cost blows up.
- Don't write SLOs you don't actually engineer to. Aspirational SLOs are noise.
- Don't ignore the on-call retro. Every page is a chance to delete a noisy alert.

## See also

- `observability-baseline` — getting started with logs / errors / metrics
- `distributed-tracing-rails` — OpenTelemetry
- `solid-queue-and-sidekiq` — queue depth metrics
- `multi-database-and-replicas` — replica lag metrics
- `rails-caching-strategy` — cache hit rate metrics

## Sources

- [Google SRE Workbook — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
- [RED method — Tom Wilkie](https://www.weave.works/blog/the-red-method-key-metrics-for-microservices-architecture/)
- [USE method — Brendan Gregg](https://www.brendangregg.com/usemethod.html)
- [Prometheus](https://prometheus.io/)
- [Grafana](https://grafana.com/)
- [Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Observability Engineering — Charity Majors et al.](https://www.honeycomb.io/observability-engineering-oreilly-book-2022)
- [Datadog APM](https://www.datadoghq.com/product/apm/)
