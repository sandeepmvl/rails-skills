# Evals for `observability-baseline`

## Prompt 1: "Rails logs are noisy"

**User prompt:**
> My production Rails logs are six lines per request. Hard to grep, hard to ship to ELK.

**Expected:**
- lograge.
- JSON formatter.
- Custom options adding request_id, user_id, remote_ip.

**Rubric:**
- [ ] lograge recommended
- [ ] JSON formatter
- [ ] Request correlation tags

---

## Prompt 2: "Error tracker"

**User prompt:**
> Should I use Sentry, Honeybadger, or Rollbar?

**Expected:**
- Pick one — they're equivalent.
- Sentry is the most common default.
- Costs / pricing are similar.

**Rubric:**
- [ ] Pick one (not all three)
- [ ] Sentry as default suggestion
- [ ] Did not say "doesn't matter, pick anything"

---

## Prompt 3: "PII in logs"

**User prompt:**
> Compliance flagged that we log user emails. Fix?

**Expected:**
- Add to `filter_parameters` (Rails) + Sentry `before_send`.
- Stop logging email directly. Use user_id_hash for correlation.
- Mention error tracker also auto-pulls from request — need `send_default_pii = false`.

**Rubric:**
- [ ] filter_parameters extended
- [ ] Sentry config mirrored
- [ ] Hashed-correlation pattern

---

## Prompt 4: "How do I report this caught exception?"

**User prompt:**
> I'm catching `HTTP::Error` from an external API. Want to log it to Sentry without raising.

**Expected:**
- `Rails.error.report(e, context: {...}, handled: true)`.
- Don't `Sentry.capture_exception` directly — use the Rails 7.1+ API.
- Reasoning: one path, multiple destinations.

**Rubric:**
- [ ] Rails.error.report
- [ ] handled: true distinguished
- [ ] Did not Sentry.capture_exception directly

---

## Prompt 5: "What should I log on signup?"

**User prompt:**
> User signs up. What should I log?

**Expected:**
- Structured: `{ event: "user_signup", user_id: ..., signup_source: ..., ip: ... }`.
- Never log password, never log raw email.
- Mention warn level for rate limit hits, info for normal flow.

**Rubric:**
- [ ] Structured fields
- [ ] No PII
- [ ] Level reasoning

---

## Prompt 6: "Health monitoring"

**User prompt:**
> External pinger to monitor uptime.

**Expected:**
- /health endpoint (not /up — that's for Kamal Proxy load balancing).
- Pingdom / Better Stack / UptimeRobot.
- Alert thresholds: 3 consecutive failures, p99 latency, error rate.

**Rubric:**
- [ ] /health distinguished from /up
- [ ] External pinger recommended
- [ ] Alert thresholds named
