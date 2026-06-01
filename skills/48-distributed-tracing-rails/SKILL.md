---
name: distributed-tracing-rails
description: Distributed tracing for Rails — OpenTelemetry SDK + auto-instrumentation, trace + span model, context propagation across HTTP / Sidekiq / Kafka, baggage, sampling strategies, exporters (OTLP to Tempo / Jaeger / Honeycomb / Datadog / Lightstep), correlating traces with logs via trace_id, when tracing matters more than logs/metrics. Use when the user mentions OpenTelemetry, OTel, distributed tracing, traces, spans, Jaeger, Tempo, Honeycomb, Datadog APM, "follow a request across services", or has microservices and needs cross-service debugging.
---

# Distributed Tracing in Rails

> When a request crosses 4 services, logs in 4 places, traces are the only way to follow it. OpenTelemetry is the vendor-neutral standard — instrument once, export anywhere. This skill sets up production-grade tracing for Rails with minimal noise.

## The opinion

> **Use OpenTelemetry (OTel) — the CNCF standard, vendor-neutral, replaces vendor-specific APM agents. Use auto-instrumentation for Rails, Net::HTTP, Faraday, Sidekiq, Active Record. Propagate context across HTTP (W3C traceparent header), Sidekiq, and Kafka. Sample at the head (parent-based) by default; tune down for high-traffic services. Export to OTLP and let a collector fan out to your backend (Tempo, Honeycomb, Datadog).**

## Setup

```ruby
# Gemfile
gem "opentelemetry-sdk"
gem "opentelemetry-exporter-otlp"
gem "opentelemetry-instrumentation-all"
```

```ruby
# config/initializers/opentelemetry.rb
require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"

OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "rails-app")
  c.resource = OpenTelemetry::SDK::Resources::Resource.create(
    "service.version" => ENV.fetch("APP_VERSION", "unknown")
  )
  c.use_all  # turn on every instrumentation we have a gem for
end
```

Set via env:
- `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318`
- `OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production,service.namespace=ecommerce`
- `OTEL_TRACES_SAMPLER=parentbased_traceidratio`
- `OTEL_TRACES_SAMPLER_ARG=0.1`  # 10% sampling

## What `use_all` instruments

- Rails (controllers, views, mailers)
- Active Record (SQL queries)
- Net::HTTP, Faraday, HTTPClient (outbound HTTP)
- Sidekiq, Active Job (queue + perform)
- Rack
- Redis
- Tilt (template render)
- AwsSdk, MysqlClient, PG, Postgres

Each becomes a span. Auto-context-propagation works for HTTP and Active Job out of the box.

## Pattern 1: Custom spans

```ruby
class PaymentProcessor
  TRACER = OpenTelemetry.tracer_provider.tracer("payment_processor", "1.0")

  def charge(order)
    TRACER.in_span("charge_order", attributes: { "order.id" => order.id, "order.cents" => order.total_cents }) do |span|
      result = Stripe::PaymentIntent.create(...)
      span.set_attribute("stripe.payment_intent_id", result.id)
      result
    rescue Stripe::CardError => e
      span.record_exception(e)
      span.status = OpenTelemetry::Trace::Status.error("declined")
      raise
    end
  end
end
```

## Pattern 2: Cross-service propagation (HTTP)

OTel auto-injects W3C `traceparent` and `tracestate` headers on outbound HTTP. The receiving service auto-extracts them. No code needed if both ends use OTel.

For manual control:

```ruby
require "opentelemetry/baggage"

headers = {}
OpenTelemetry.propagation.inject(headers)
# headers now contains "traceparent" and "tracestate"
Net::HTTP.post(uri, body, headers)
```

## Pattern 3: Sidekiq / Active Job propagation

`opentelemetry-instrumentation-sidekiq` wraps perform — the span starts when the job runs and links to the enqueue span. So you get continuity:

```
[POST /orders] → [enqueue] ⋯ [perform OrderConfirmEmailJob] → [SMTP]
```

Without instrumentation, the perform span is a separate trace, no link.

## Pattern 4: Kafka propagation

OTel doesn't auto-inject headers into Kafka by default. Manually:

```ruby
context = OpenTelemetry::Context.current
headers = {}
OpenTelemetry.propagation.inject(headers, context: context)

Karafka.producer.produce_sync(
  topic: "order_events",
  key: order.account_id.to_s,
  payload: payload,
  headers: headers
)
```

Consumer extracts:

```ruby
def consume
  messages.each do |message|
    context = OpenTelemetry.propagation.extract(message.headers || {})
    OpenTelemetry::Context.with_current(context) do
      TRACER.in_span("order_events.consume", attributes: { "kafka.offset" => message.offset }) do
        # ... process
      end
    end
  end
end
```

## Pattern 5: Correlating logs with traces

Every log line should include the trace_id. With lograge:

```ruby
# config/initializers/lograge.rb
Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.custom_options = ->(event) {
    span = OpenTelemetry::Trace.current_span
    ctx = span.context
    {
      trace_id: ctx.hex_trace_id,
      span_id: ctx.hex_span_id,
      request_id: event.payload[:request_id]
    }
  }
end
```

Now in your log aggregator (Loki / Datadog / Elastic), search by trace_id → see every log line for that request across services.

## Pattern 6: Baggage

Propagate small string keys across the entire trace:

```ruby
OpenTelemetry::Baggage.set_value("account_id", order.account_id.to_s)
```

Now every span in the request — even in downstream services — has `account_id` as an attribute (via a SpanProcessor). Useful for filtering: "show me all traces where account.id = 42 hit an error."

**Don't put PII in baggage.** It propagates to every span and may end up in logs.

## Pattern 7: Sampling

Tracing every request is expensive. Sample strategically:

```bash
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
```

- **Parent-based:** if upstream sampled, we sample. Keeps traces complete across services.
- **TraceID-ratio:** 10% of traces. Each service contributes if upstream did.

For high-traffic services, sample even lower (0.01 = 1%) but use tail-based sampling in the collector to keep all error / slow traces.

## Pattern 8: Sampling decisions in the collector

```yaml
# OTel Collector config (tail-based sampling)
processors:
  tail_sampling:
    decision_wait: 10s
    policies:
      - name: errors
        type: status_code
        status_code: { status_codes: [ERROR] }
      - name: slow
        type: latency
        latency: { threshold_ms: 1000 }
      - name: sample-10pct
        type: probabilistic
        probabilistic: { sampling_percentage: 10 }
```

Result: 100% of errors / slow traces + 10% of healthy traces. Far cheaper than uniform 100%.

## Pattern 9: Export topology

```
[Rails apps] → OTLP/HTTP → [OTel Collector] → fan out:
                                              ├─ Tempo / Jaeger
                                              ├─ Honeycomb
                                              ├─ Datadog
                                              └─ S3 (cold storage)
```

The Collector is a separate deployable (Docker / k8s). Apps export OTLP to the collector; collector handles export complexity.

## Pattern 10: Reducing noise

`use_all` is noisy in development. Disable verbose instrumentations:

```javascript
OpenTelemetry::SDK.configure do |c|
  c.use_all(
    "OpenTelemetry::Instrumentation::ActiveRecord" => { db_statement: :include },
    "OpenTelemetry::Instrumentation::Tilt" => { suppress_internal: true }
  )
end
```

For Active Record: `db_statement: :include` records the SQL — useful in dev, expensive in prod. Set `:omit` in production unless you need it.

## Common mistakes to refuse

- Don't roll your own correlation IDs. Use OTel — it's already in 90% of platforms.
- Don't put PII in span attributes or baggage. They go everywhere.
- Don't sample at 100% in high-traffic prod. The cost compounds.
- Don't skip cross-service propagation. A trace that stops at the HTTP boundary is half useful.
- Don't forget to plumb traces through Sidekiq and Kafka. Most of your latency is async.
- Don't use vendor-specific APM SDKs in 2026 unless you have a strong reason — OTel works with all of them.

## See also

- `observability-baseline` — logs / metrics / errors basics
- `observability-rails-advanced` — SLOs, alerting strategy
- `kafka-rails` — context propagation through topics
- `solid-queue-and-sidekiq` — trace propagation through jobs

## Sources

- [OpenTelemetry Ruby](https://github.com/open-telemetry/opentelemetry-ruby)
- [W3C Trace Context](https://www.w3.org/TR/trace-context/)
- [opentelemetry.io](https://opentelemetry.io/)
- [Honeycomb on tracing](https://www.honeycomb.io/blog/observability-driven-development)
- [Lightstep / ServiceNow](https://lightstep.com/)
- [OTel Collector docs](https://opentelemetry.io/docs/collector/)
- [Tempo (Grafana)](https://grafana.com/oss/tempo/)
