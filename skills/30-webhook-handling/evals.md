# Evals for `webhook-handling`

## Prompt 1: "Receive GitHub webhook"
**User:** Receive GitHub webhooks for PR events.
**Expected:** Skip CSRF. Verify HMAC-SHA256 over raw body. secure_compare. Store WebhookEvent. Enqueue job.
**Rubric:** [ ] Signature [ ] Idempotency [ ] Async job

## Prompt 2: "Double-processed event"
**User:** GitHub sometimes delivers the same webhook twice. How to dedupe?
**Expected:** Persist WebhookEvent with UNIQUE(provider, provider_event_id). Find-or-create pattern.
**Rubric:** [ ] UNIQUE index [ ] find-or-create pattern

## Prompt 3: "Signature compare"
**User:** Use == to compare HMAC signatures?
**Expected:** No — timing attack. Use ActiveSupport::SecurityUtils.secure_compare.
**Rubric:** [ ] Timing attack flagged [ ] secure_compare

## Prompt 4: "Webhook is slow"
**User:** My webhook handler takes 3 seconds; GitHub keeps retrying.
**Expected:** Enqueue a job; respond 200 fast. Job does the work.
**Rubric:** [ ] Async pattern [ ] Quick 200
