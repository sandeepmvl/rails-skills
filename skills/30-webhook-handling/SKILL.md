---
name: webhook-handling
description: Receive webhooks in Ruby on Rails 8 — signature verification, idempotency via event-ID storage, async processing in jobs (never sync), retry semantics, the raw-body capture for HMAC, replay protection. Use when the user mentions webhooks, webhook signature, HMAC verification, replay protection, idempotency keys, webhook retries, or asks how to receive Stripe / GitHub / Slack / Twilio / Shopify webhooks.
---

# Webhook Handling

> Receive webhooks the right way: verify signature, store event ID for idempotency, enqueue async, respond 200 fast. AI agents skip signature verification, sync-process the payload, and miss the retry semantics — three bugs per webhook integration.

## The opinion

> **Skip CSRF; verify signature instead. Capture the raw request body BEFORE parsing (HMAC is over raw bytes). Persist a `WebhookEvent` row with `provider_event_id` + UNIQUE index for idempotency. Enqueue a job for actual processing. Respond 200 quickly so the provider doesn't retry. Reject signature failures with 400, not 401 (401 invites retries on some platforms).**

## The webhook controller pattern

```ruby
# config/routes.rb
post "/webhooks/stripe", to: "webhooks/stripe#receive"
post "/webhooks/github", to: "webhooks/github#receive"
```

```ruby
# app/controllers/webhooks/base_controller.rb
class Webhooks::BaseController < ActionController::Base
  skip_before_action :verify_authenticity_token

  protected

  def raw_body
    @raw_body ||= request.body.read.tap { request.body.rewind }
  end

  def handle_idempotent(event_id, provider)
    # Try to insert; UNIQUE(provider, provider_event_id) index is the gate.
    event = WebhookEvent.create!(provider: provider, provider_event_id: event_id)

    WebhookEvent.transaction do
      yield event
      event.update!(processed_at: Time.current)
    end
    :processed
  rescue ActiveRecord::RecordNotUnique
    :duplicate  # concurrent / replayed delivery — already recorded
  end
end
```

```ruby
# app/models/webhook_event.rb
class WebhookEvent < ApplicationRecord
  validates :provider, :provider_event_id, presence: true
  validates :provider_event_id, uniqueness: { scope: :provider }
end
```

Migration:

```ruby
create_table :webhook_events do |t|
  t.string :provider, null: false
  t.string :provider_event_id, null: false
  t.string :event_type
  t.jsonb :payload  # encrypted at rest via Active Record Encryption if PII
  t.datetime :processed_at
  t.timestamps
end
add_index :webhook_events, [:provider, :provider_event_id], unique: true
add_index :webhook_events, :processed_at
```

## Core patterns

### Pattern 1: Signature verification — generic HMAC

For providers that sign with HMAC-SHA256 (GitHub, Slack, custom):

```ruby
# app/controllers/webhooks/github_controller.rb
class Webhooks::GithubController < Webhooks::BaseController
  def receive
    return head(:bad_request) unless verify_signature

    payload = JSON.parse(raw_body)
    event_id = request.headers["X-GitHub-Delivery"]

    result = handle_idempotent(event_id, "github") do |event|
      event.update!(event_type: request.headers["X-GitHub-Event"], payload: payload)
      ProcessGithubEventJob.perform_later(event.id)
    end

    head(:ok)
  end

  private

  def verify_signature
    sig_header = request.headers["X-Hub-Signature-256"]  # "sha256=..."
    return false if sig_header.blank?
    expected = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), Rails.application.credentials.github_webhook_secret, raw_body)
    ActiveSupport::SecurityUtils.secure_compare(expected, sig_header)
  end
end
```

**Critical:** `ActiveSupport::SecurityUtils.secure_compare` for timing-attack resistance. Don't use `==`.

### Pattern 2: Provider-specific verification (Stripe)

```ruby
# app/controllers/webhooks/stripe_controller.rb
class Webhooks::StripeController < Webhooks::BaseController
  def receive
    event = Stripe::Webhook.construct_event(
      raw_body,
      request.headers["Stripe-Signature"],
      Rails.application.credentials.stripe_webhook_secret
    )

    handle_idempotent(event.id, "stripe") do |webhook|
      webhook.update!(event_type: event.type, payload: event.to_hash)
      ProcessStripeEventJob.perform_later(webhook.id)
    end

    head(:ok)
  rescue Stripe::SignatureVerificationError
    head(:bad_request)
  rescue JSON::ParserError
    head(:bad_request)
  end
end
```

`Stripe::Webhook.construct_event` handles signature + timestamp checks (replay protection via the timestamp in the signature header).

See `stripe-webhook-integration` for the full Stripe-specific patterns.

### Pattern 3: Async processing in jobs

```ruby
# app/jobs/process_github_event_job.rb
class ProcessGithubEventJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(webhook_event_id)
    event = WebhookEvent.find(webhook_event_id)
    return if event.processed_at.present?  # already processed — idempotency belt + suspenders

    case event.event_type
    when "push"          then handle_push(event)
    when "pull_request"  then handle_pull_request(event)
    when "issue_comment" then handle_comment(event)
    end
  end

  private

  def handle_push(event)
    # ... actual business logic
  end
end
```

**Why async:**
- Webhook providers retry on slow responses (>5-10s) or non-200s. Doing real work synchronously means flakes turn into duplicate events.
- Long-running processing blocks the request worker.
- Jobs retry automatically; webhook re-delivery doesn't always.

### Pattern 4: Raw body capture (critical)

```ruby
def raw_body
  @raw_body ||= request.body.read.tap { request.body.rewind }
end
```

**Why this matters:** signatures are computed over raw bytes. If Rails has already parsed the body (e.g. `params[:event]` was accessed), the bytes you re-serialize may differ from what the provider signed. Always capture raw body BEFORE accessing parsed params.

For some Rails versions, you may need to ensure `wrap_parameters` doesn't strip the raw body — use `consume_request_body` middleware or capture in a `before_action`.

### Pattern 5: Replay protection beyond signature

Some providers include a timestamp in the signature header (Stripe). Reject events older than ~5 minutes. Use the provider's SDK rather than hand-parsing:

```ruby
# Stripe — construct_event handles signature + timestamp tolerance in one call.
Stripe::Webhook.construct_event(raw_body, sig_header, secret, tolerance: 300)
# Raises Stripe::SignatureVerificationError if the timestamp is outside the window.
```

GitHub does not include a timestamp in its `X-Hub-Signature-256` header, so there is no provider-side replay window. For providers like GitHub, the idempotency check (`provider_event_id` + UNIQUE index) is your protection.

### Pattern 6: Webhook dashboard / inspector

For debugging, expose a (auth-protected) dashboard:

```ruby
# app/controllers/admin/webhook_events_controller.rb
class Admin::WebhookEventsController < AdminController
  def index
    @events = WebhookEvent
      .order(created_at: :desc)
      .limit(100)
  end

  def show
    @event = WebhookEvent.find(params[:id])
  end

  def replay
    @event = WebhookEvent.find(params[:id])
    case @event.provider
    when "github" then ProcessGithubEventJob.perform_later(@event.id)
    when "stripe" then ProcessStripeEventJob.perform_later(@event.id)
    end
    redirect_to admin_webhook_event_path(@event), notice: "Replayed"
  end
end
```

Saves hours when debugging "did the webhook arrive? did we process it?"

### Pattern 7: Testing webhooks

```ruby
# spec/requests/webhooks/github_spec.rb
RSpec.describe "Webhooks::Github", type: :request do
  let(:payload) { { action: "opened", number: 1 }.to_json }
  let(:secret) { Rails.application.credentials.github_webhook_secret }
  let(:signature) { "sha256=" + OpenSSL::HMAC.hexdigest("sha256", secret, payload) }

  it "accepts a valid webhook" do
    post "/webhooks/github",
      params: payload,
      headers: {
        "Content-Type" => "application/json",
        "X-Hub-Signature-256" => signature,
        "X-GitHub-Delivery" => SecureRandom.uuid,
        "X-GitHub-Event" => "pull_request"
      }
    expect(response).to have_http_status(:ok)
    expect(WebhookEvent.count).to eq(1)
  end

  it "rejects invalid signatures" do
    post "/webhooks/github",
      params: payload,
      headers: {
        "Content-Type" => "application/json",
        "X-Hub-Signature-256" => "sha256=garbage",
        "X-GitHub-Delivery" => SecureRandom.uuid
      }
    expect(response).to have_http_status(:bad_request)
    expect(WebhookEvent.count).to eq(0)
  end

  it "is idempotent" do
    delivery_id = SecureRandom.uuid
    2.times do
      post "/webhooks/github", params: payload, headers: {
        "Content-Type" => "application/json",
        "X-Hub-Signature-256" => signature,
        "X-GitHub-Delivery" => delivery_id
      }
    end
    expect(WebhookEvent.count).to eq(1)
  end
end
```

## Common mistakes to refuse

- Don't skip signature verification.
- Don't process synchronously — enqueue a job.
- Don't `==` strings for signature comparison — use `secure_compare`.
- Don't read `params[:foo]` before capturing `raw_body` — the parse can mangle bytes.
- Don't return 500 on bad signature — return 400. (5xx invites the provider to retry.)
- Don't store webhooks unencrypted if they contain PII. Use Active Record Encryption.
- Don't skip the UNIQUE index on (provider, provider_event_id) — idempotency relies on it.
- Don't trust the IP source as authentication — IPs can be spoofed or rotate.

## When NOT to use this skill

- Sending webhooks (vs receiving) — different problem; see v0.2 `external-api-integration`.
- Stripe-specific patterns — `stripe-webhook-integration` covers in detail.

## See also

- `stripe-webhook-integration` — canonical example
- `solid-queue-and-sidekiq` — webhook processor jobs
- `rails-security-baseline` — signature verification, secrets
- `external-api-integration` — sending webhook calls

## Sources

- [Stripe webhooks docs](https://docs.stripe.com/webhooks)
- [GitHub webhooks docs](https://docs.github.com/en/webhooks)
- [Slack webhook signature verification](https://api.slack.com/authentication/verifying-requests-from-slack)
- [Twilio webhook signatures](https://www.twilio.com/docs/usage/webhooks/webhooks-security)
- [Stripe Ruby — Webhook helper](https://stripe.com/docs/api/webhooks)
- [ActiveSupport::SecurityUtils](https://api.rubyonrails.org/classes/ActiveSupport/SecurityUtils.html)
