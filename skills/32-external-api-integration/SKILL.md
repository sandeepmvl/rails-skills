---
name: external-api-integration
description: Integrate Ruby on Rails apps with external HTTP APIs — Faraday as the canonical client, retries with exponential backoff, circuit breaker (Stoplight), VCR for tests, timeout discipline (open + read), structured logging of API calls, idempotency keys on writes, rate limit handling, the wrap-in-a-service-object pattern. Use when the user mentions Faraday, HTTP client, API integration, retries, circuit breaker, Stoplight, VCR cassettes, HTTPX, Net::HTTP, or asks how to call a third-party API safely.
---

# External API Integration

> Calling external APIs is where Rails apps lose reliability. AI agents reach for `Net::HTTP.get(URI(url))`, no timeouts, no retries, no logging, no circuit breaker. Replace with Faraday + middleware + service object wrapper.

## The opinion

> **Faraday for the HTTP client. Wrap every external API in a service object. Open timeout 3s, read timeout 10s (tune per API). Exponential retries (3 attempts) on idempotent verbs. Circuit breaker for chronically-flaky upstreams. VCR for tests. Log every call (sanitized) with correlation IDs. Idempotency keys on writes when the API supports them. Never put external calls in the request path if you can help it — use a job.**

## Core patterns

### Pattern 1: The Faraday client wrapper

```ruby
# Gemfile
gem "faraday"
gem "faraday-retry"
gem "stoplight"  # circuit breaker

# app/clients/hubspot_client.rb
class HubspotClient
  def initialize
    @conn = Faraday.new(url: "https://api.hubapi.com") do |f|
      f.request :json
      f.request :authorization, "Bearer", -> { Rails.application.credentials.hubspot_api_key }
      f.request :retry, max: 3, interval: 0.5, backoff_factor: 2,
                         retry_statuses: [429, 500, 502, 503, 504],
                         methods: %i[get put]  # idempotent verbs only
      f.response :raise_error  # raise on 4xx/5xx
      f.response :json
      f.response :logger, Rails.logger, headers: false, log_level: :info do |log|
        log.filter(/(Authorization: Bearer )(\S+)/i, '\1[FILTERED]')
      end
      f.options.open_timeout = 3
      f.options.timeout = 10
      f.adapter Faraday.default_adapter
    end
  end

  def upsert_contact(email:, attrs:)
    Stoplight("hubspot.upsert_contact") do
      @conn.post("/contacts/v1/contact/createOrUpdate/email/#{email}", { properties: attrs.map { |k, v| { property: k, value: v } } }).body
    end.with_threshold(5).with_cool_off_time(60).run
  end
end
```

**Why every piece:**
- `request :retry` — handles transient failures without app-level code.
- `retry_statuses: [429, 500, ...]` — only retry on transient failures, not on 401/422.
- `methods: %i[get put]` — only retry idempotent operations. Don't auto-retry POST (might double-create).
- `response :raise_error` — turn 4xx/5xx into exceptions; cleaner control flow.
- `response :logger` with sanitization — visibility without leaking creds.
- Timeouts — never hang on a flaky upstream.
- Stoplight circuit breaker — after 5 failures in window, requests fail fast for 60s.

### Pattern 2: Idempotency keys on POST writes

```ruby
def create_charge(amount:, customer:, idempotency_key:)
  @conn.post("/charges", { amount: amount, customer: customer }) do |req|
    req.headers["Idempotency-Key"] = idempotency_key
  end.body
end

# Caller:
HubspotClient.new.create_charge(amount: 100, customer: "cus_x", idempotency_key: "charge-#{order.id}")
```

The idempotency key is owned by the caller. Use something stable (order ID, request ID) so retries dedupe.

### Pattern 3: Service object wrapper

```ruby
# app/services/sync_to_hubspot.rb
class SyncToHubspot
  Result = Data.define(:status, :contact, :error)

  def initialize(contact)
    @contact = contact
  end

  def call
    response = HubspotClient.new.upsert_contact(
      email: @contact.email,
      attrs: { firstname: @contact.first_name, lastname: @contact.last_name }
    )
    @contact.update!(hubspot_id: response["vid"], hubspot_synced_at: Time.current)
    Result.new(status: :success, contact: @contact, error: nil)
  rescue Faraday::TooManyRequestsError
    Result.new(status: :rate_limited, contact: @contact, error: "429")
  rescue Stoplight::Error::RedLight
    Result.new(status: :circuit_open, contact: @contact, error: "circuit breaker open")
  rescue Faraday::Error => e
    Rails.error.report(e, context: { contact_id: @contact.id })
    Result.new(status: :failure, contact: @contact, error: e.message)
  end
end
```

See `service-objects-vs-fat-models` Trigger 2 — external API integration is the canonical service-object use case.

### Pattern 4: Don't block the request — use a job

```ruby
# Controller — no
def create
  @user = User.create!(user_params)
  SyncToHubspot.new(@user).call  # 500ms-3s blocking
  redirect_to @user
end

# Controller — yes
def create
  @user = User.create!(user_params)
  SyncToHubspotJob.perform_later(@user.id)
  redirect_to @user
end
```

```ruby
class SyncToHubspotJob < ApplicationJob
  retry_on Faraday::TooManyRequestsError, wait: :polynomially_longer, attempts: 10
  retry_on Faraday::TimeoutError,         wait: :polynomially_longer, attempts: 5

  def perform(user_id)
    user = User.find(user_id)
    SyncToHubspot.new(user).call
  end
end
```

The job retries on transient failures. The user sees a fast response.

### Pattern 5: Testing with VCR

```ruby
# spec/services/sync_to_hubspot_spec.rb
RSpec.describe SyncToHubspot, :vcr do
  let(:contact) { create(:contact, email: "test@example.com") }

  it "upserts the contact and updates locally" do
    result = described_class.new(contact).call
    expect(result.status).to eq(:success)
    expect(contact.reload.hubspot_id).to be_present
  end

  it "returns rate_limited on 429" do
    VCR.use_cassette("hubspot/rate_limited") do
      result = described_class.new(contact).call
      expect(result.status).to eq(:rate_limited)
    end
  end
end
```

See `rspec-testing-pyramid` Pattern 5 for the VCR setup. Filter credentials from cassettes.

### Pattern 6: Circuit breaker — Stoplight

```ruby
Stoplight("hubspot.api") do
  HubspotClient.new.upsert_contact(...)
end
  .with_threshold(5)      # 5 failures in window
  .with_cool_off_time(60) # before retrying
  .with_data_store(Stoplight::DataStore::Redis.new(Redis.new))  # share across workers
  .run
```

After 5 consecutive failures, the breaker opens. Subsequent calls fail immediately with `Stoplight::Error::RedLight`. After cool-off, the breaker enters half-open: one trial call. Success → close; failure → re-open.

**When to use:** any API that goes down for minutes-hours and can take your app down with it (heavy retry storms).

### Pattern 7: Rate limit handling

Most APIs return `429 Too Many Requests` with a `Retry-After` header.

```ruby
# Custom exception that carries the retry-after value.
class RateLimited < StandardError
  attr_reader :retry_after
  def initialize(retry_after)
    @retry_after = retry_after
    super("rate_limited; retry after #{retry_after}s")
  end
end

class RateLimitMiddleware < Faraday::Middleware
  def on_complete(env)
    if env[:status] == 429
      retry_after = env[:response_headers]["Retry-After"]&.to_i || 5
      raise RateLimited.new(retry_after)
    end
  end
end
```

Job-level handling:

```ruby
class SyncToHubspotJob < ApplicationJob
  rescue_from RateLimited do |error|
    retry_job(wait: error.retry_after.seconds)
  end
end
```

### Pattern 8: Observability

Every external API call logs:
- Endpoint, method, status.
- Latency.
- Correlation ID (request_id, job_id).
- Sanitized headers (filter auth, tokens).

Faraday's `response :logger` handles most of this. Pair with Sentry / OTel for distributed traces.

### Pattern 9: Alternative clients

| Client | When |
|---|---|
| Faraday | Default. Rich middleware ecosystem. |
| HTTPX | Better HTTP/2, async-first. Pick when running many concurrent requests. |
| Net::HTTP | Standard library, no gem. Only for one-off scripts. |
| HTTParty | Older, less idiomatic. Don't pick for new code. |
| Excon | Stripe Ruby uses it. Fine; less popular than Faraday. |

## Common mistakes to refuse

- Don't `Net::HTTP.get(URI(params[:url]))` — SSRF (see `rails-security-baseline`).
- Don't block requests on external calls. Use a job.
- Don't retry POST without an idempotency key.
- Don't skip timeouts. Default-no-timeout = hang.
- Don't log raw headers — credentials leak.
- Don't skip the circuit breaker for flaky upstreams — retry storms compound the outage.
- Don't hit the real API in tests. VCR or WebMock.

## When NOT to use this skill

- Receiving webhooks — `webhook-handling`.
- The user asks for a SOAP / GraphQL client — different libs (savon, graphql-client).

## See also

- `service-objects-vs-fat-models` — external API is canonical service-object case
- `solid-queue-and-sidekiq` — retry config on jobs
- `rails-security-baseline` — SSRF, credential management
- `rspec-testing-pyramid` — VCR setup

## Sources

- [Faraday docs](https://lostisland.github.io/faraday/)
- [faraday-retry](https://github.com/lostisland/faraday-retry)
- [Stoplight (circuit breaker)](https://github.com/bolshakov/stoplight)
- [VCR](https://github.com/vcr/vcr)
- [HTTPX](https://honeyryderchuck.gitlab.io/httpx/)
- [Faraday Logger filter pattern](https://lostisland.github.io/faraday/middleware/logger)
- [Idempotency keys — Stripe](https://docs.stripe.com/api/idempotent_requests)
