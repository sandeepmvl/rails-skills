---
name: stripe-webhook-integration
description: Stripe webhook integration in Rails 8 — Stripe::Webhook.construct_event for signature + timestamp verification, idempotency via event.id, the canonical event types to handle (payment_intent.succeeded / payment_intent.payment_failed / charge.refunded / customer.subscription.*), test-mode vs live-mode secrets, webhook endpoint testing via Stripe CLI, async processing in jobs. Use when the user mentions Stripe webhooks, payment_intent events, subscription events, Stripe::Webhook, webhook_secret, Stripe CLI, or builds payment infrastructure.
---

# Stripe Webhook Integration

> Stripe webhooks are the most common webhook integration in Rails. Get them right: signature + timestamp verification, idempotency by `event.id`, handle the events you actually need (not every event in the catalog), retry safely.

## The opinion

> **Use `Stripe::Webhook.construct_event` — signature + timestamp covered in one call. Persist a `WebhookEvent` for idempotency. Enqueue a job for actual processing. Handle only the events your business needs; ignore the rest. Separate test-mode and live-mode webhook secrets.**

## The event types you actually handle

```ruby
HANDLED_EVENTS = %w[
  payment_intent.succeeded
  payment_intent.payment_failed
  charge.refunded
  customer.subscription.created
  customer.subscription.updated
  customer.subscription.deleted
  invoice.payment_succeeded
  invoice.payment_failed
  customer.created
  checkout.session.completed
]
```

Everything else: log + skip. Don't reach for events you don't have a business action for.

## Core patterns

### Pattern 1: The controller

```ruby
# app/controllers/webhooks/stripe_controller.rb
class Webhooks::StripeController < Webhooks::BaseController
  HANDLED_EVENTS = %w[
    payment_intent.succeeded payment_intent.payment_failed
    charge.refunded
    customer.subscription.created customer.subscription.updated customer.subscription.deleted
    invoice.payment_succeeded invoice.payment_failed
    checkout.session.completed
  ]

  def receive
    event = Stripe::Webhook.construct_event(
      raw_body,
      request.headers["Stripe-Signature"],
      Rails.application.credentials.stripe_webhook_secret
    )

    return head(:ok) unless HANDLED_EVENTS.include?(event.type)

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

(Uses the `Webhooks::BaseController` + `WebhookEvent` model from `webhook-handling`.)

### Pattern 2: The processor job

```ruby
# app/jobs/process_stripe_event_job.rb
class ProcessStripeEventJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(webhook_event_id)
    event_record = WebhookEvent.find(webhook_event_id)
    stripe_event = Stripe::Event.construct_from(event_record.payload)

    case stripe_event.type
    when "payment_intent.succeeded"           then PaymentIntentSucceeded.call(stripe_event)
    when "payment_intent.payment_failed"      then PaymentIntentFailed.call(stripe_event)
    when "charge.refunded"                    then ChargeRefunded.call(stripe_event)
    when "customer.subscription.created"      then SubscriptionCreated.call(stripe_event)
    when "customer.subscription.updated"      then SubscriptionUpdated.call(stripe_event)
    when "customer.subscription.deleted"      then SubscriptionDeleted.call(stripe_event)
    when "invoice.payment_succeeded"          then InvoicePaymentSucceeded.call(stripe_event)
    when "invoice.payment_failed"             then InvoicePaymentFailed.call(stripe_event)
    when "checkout.session.completed"         then CheckoutSessionCompleted.call(stripe_event)
    end
  end
end
```

One service object per event type. Keeps the dispatch flat and testable.

### Pattern 3: Handling `payment_intent.succeeded`

```ruby
# app/services/payment_intent_succeeded.rb
class PaymentIntentSucceeded
  def self.call(event)
    new(event).call
  end

  def initialize(event)
    @intent = event.data.object  # PaymentIntent object
  end

  def call
    order = Order.find_by(stripe_payment_intent_id: @intent.id)
    return if order.nil?  # PaymentIntent without a matching order — log and skip
    return if order.paid?  # idempotency belt-and-suspenders

    order.update!(
      status: "paid",
      paid_at: Time.current,
      amount_received: @intent.amount_received
    )
    OrderConfirmationMailer.confirm(order).deliver_later
  end
end
```

**Idempotency layers:**
1. WebhookEvent UNIQUE index — won't process the same `event.id` twice.
2. `return if order.paid?` — won't apply same effect even if WebhookEvent guard fails.
3. Stripe's own idempotency key on the original payment — prevents double-charge upstream.

### Pattern 4: Subscription lifecycle

```ruby
class SubscriptionCreated
  def self.call(event)
    stripe_sub = event.data.object
    user = User.find_by!(stripe_customer_id: stripe_sub.customer)
    Subscription.create!(
      user: user,
      stripe_subscription_id: stripe_sub.id,
      plan: stripe_sub.items.data.first.price.id,
      status: stripe_sub.status,
      current_period_end: Time.at(stripe_sub.current_period_end)
    )
  end
end

class SubscriptionUpdated
  def self.call(event)
    stripe_sub = event.data.object
    sub = Subscription.find_by(stripe_subscription_id: stripe_sub.id)
    return if sub.nil?
    sub.update!(
      plan: stripe_sub.items.data.first.price.id,
      status: stripe_sub.status,
      current_period_end: Time.at(stripe_sub.current_period_end),
      cancel_at_period_end: stripe_sub.cancel_at_period_end
    )
  end
end

class SubscriptionDeleted
  def self.call(event)
    Subscription.find_by(stripe_subscription_id: event.data.object.id)&.update!(status: "canceled")
  end
end
```

### Pattern 5: Test-mode vs live-mode secrets

```yaml
# config/credentials/development.yml (decrypted)
stripe_webhook_secret: whsec_test_XXX
stripe_secret_key: sk_test_YYY

# config/credentials/production.yml.enc (decrypted)
stripe_webhook_secret: whsec_live_AAA
stripe_secret_key: sk_live_BBB
```

```ruby
# config/initializers/stripe.rb
Stripe.api_key = Rails.application.credentials.stripe_secret_key
```

**Critical:** test-mode events to production endpoint = signature mismatch (different secrets). Set up two endpoints in the Stripe Dashboard: one for production (live secret), one for staging (test secret).

### Pattern 6: Local development — Stripe CLI

```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe

# Forward webhooks to local
stripe listen --forward-to localhost:3000/webhooks/stripe

# Triggers events for testing
stripe trigger payment_intent.succeeded
stripe trigger customer.subscription.created
```

`stripe listen` outputs a webhook signing secret (`whsec_...`) to use during local development.

### Pattern 7: Replay an event from Stripe Dashboard

Failed processing? Open the Dashboard → Developers → Webhooks → pick the endpoint → click the failed event → "Resend". Same event ID, your idempotency layer handles it cleanly.

**Anti-pattern:** building a custom replay tool from scratch. Stripe's UI handles it.

## Common mistakes to refuse

- Don't skip `Stripe::Webhook.construct_event` — verifies signature + timestamp.
- Don't use the wrong webhook secret (test vs live) — silent signature failure.
- Don't process synchronously. Long jobs trigger retries from Stripe.
- Don't handle events you don't have a business action for. Less code, fewer bugs.
- Don't trust the event payload's pricing — re-fetch from Stripe API if the value is critical (Stripe's webhook payload is a snapshot; query live data when in doubt).
- Don't forget `payment_intent.payment_failed` — only handling success means failed payments go silent.

## When NOT to use this skill

- Generic webhook patterns — `webhook-handling`.
- Stripe API for non-webhook flows (charge, customer creation) — `external-api-integration`.

## See also

- `webhook-handling` — generic webhook handling
- `solid-queue-and-sidekiq` — the processor job
- `actionmailer-baseline` — confirmation emails after payment events
- `observability-baseline` — log webhook processing

## Sources

- [Stripe — Webhooks](https://docs.stripe.com/webhooks)
- [Stripe — Build a webhook endpoint](https://docs.stripe.com/webhooks/quickstart)
- [Stripe CLI](https://docs.stripe.com/stripe-cli)
- [Stripe — Event types](https://docs.stripe.com/api/events/types)
- [Stripe Ruby gem](https://github.com/stripe/stripe-ruby)
- [Stripe webhook idempotency](https://docs.stripe.com/webhooks#handle-duplicate-events)
