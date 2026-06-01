# Evals for `distributed-tracing-rails`

## Prompt 1: "Trace requests across services"
**User:** I have 3 Rails services. Want to follow a request across them.
**Expected:** OpenTelemetry. opentelemetry-instrumentation-all. OTLP exporter. Auto-propagation.
**Rubric:** [ ] OpenTelemetry [ ] Auto-instrument [ ] W3C propagation

## Prompt 2: "Vendor SDK?"
**User:** Should we use Datadog APM agent?
**Expected:** Prefer OTel — vendor-neutral. Datadog has OTLP ingestion.
**Rubric:** [ ] Recommended OTel [ ] OTLP

## Prompt 3: "Trace through Sidekiq"
**User:** Trace stops when job is enqueued.
**Expected:** opentelemetry-instrumentation-sidekiq for enqueue→perform link.
**Rubric:** [ ] Sidekiq instr [ ] Context link

## Prompt 4: "Sampling"
**User:** Tracing every request is expensive.
**Expected:** parent-based traceidratio + tail-based at collector (errors + slow + 10%).
**Rubric:** [ ] Sampling strategy [ ] Tail-based
