# Evals for `external-api-integration`

## Prompt 1: "Call HubSpot API"
**User:** Integrate HubSpot from my Rails app.
**Expected:** Faraday client. Timeouts. Retry on transient. Wrap in service object. Call from job.
**Rubric:** [ ] Faraday [ ] Timeouts [ ] Retries [ ] Service+Job

## Prompt 2: "External API slow"
**User:** External API is sometimes slow; users wait.
**Expected:** Move to background job. perform_later. Job handles retries.
**Rubric:** [ ] Background job [ ] Async pattern

## Prompt 3: "Provider keeps going down"
**User:** Provider X has outages weekly. My retries make it worse.
**Expected:** Circuit breaker (Stoplight). Fail-fast during open window. Cool-off then trial.
**Rubric:** [ ] Circuit breaker [ ] Stoplight or equivalent

## Prompt 4: "Retry POST"
**User:** Should I retry POST requests automatically?
**Expected:** Only with idempotency key. Otherwise risk of double-create.
**Rubric:** [ ] Idempotency key required [ ] Refused blind retry
