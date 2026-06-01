# Evals for `stripe-webhook-integration`

## Prompt 1: "Stripe webhook"
**User:** Receive Stripe webhooks for payment success.
**Expected:** Stripe::Webhook.construct_event. WebhookEvent for idempotency. Job for processing. Idempotency belt-and-suspenders.
**Rubric:** [ ] construct_event [ ] Idempotency [ ] Async job

## Prompt 2: "Handle all events?"
**User:** Should I handle every Stripe event type?
**Expected:** No — only those with a business action. payment_intent.* + subscription.* are typical.
**Rubric:** [ ] Curated list [ ] Did not over-handle

## Prompt 3: "Local dev"
**User:** How do I test Stripe webhooks locally?
**Expected:** stripe listen --forward-to. stripe trigger for synthetic events.
**Rubric:** [ ] Stripe CLI [ ] trigger command

## Prompt 4: "Signature mismatch in prod"
**User:** Stripe signature verification fails in production but works in staging.
**Expected:** Check test vs live webhook secret. Production endpoint needs live secret; staging needs test secret. Stripe Dashboard configures separately.
**Rubric:** [ ] Per-env secret [ ] Dashboard config noted
