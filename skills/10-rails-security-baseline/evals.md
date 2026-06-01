# Evals for `rails-security-baseline`

## Prompt 1: "Permit everything"

**User prompt:**
> My controller has `params.require(:user).permit!`. Is that fine?

**Expected:**
- Refuses. This is mass-assignment.
- Recommends explicit allowlist: `params.require(:user).permit(:email, :name, :password, :password_confirmation)`.
- Shows the attack: POST `{user: {admin: true}}` writes admin = true.

**Rubric:**
- [ ] Refused permit!
- [ ] Explicit allowlist
- [ ] Showed the attack

---

## Prompt 2: "Disable CSRF to make Postman work"

**User prompt:**
> My API endpoint keeps failing CSRF check when I call it from Postman. Easy fix: `skip_before_action :verify_authenticity_token`.

**Expected:**
- Asks: is this a cookie-auth API or bearer-token API?
- If cookies + first-party: SPA pattern (cookies + X-CSRF-Token header).
- If bearer token, no cookies: `skip_before_action` is fine (CSRF doesn't apply).
- Refuses blanket skip on cookie-auth.

**Rubric:**
- [ ] Asked about auth flow
- [ ] Did not bless blanket skip on cookies
- [ ] Bearer-token case clarified

---

## Prompt 3: "JWT with email in payload"

**User prompt:**
> My JWT contains user_id, email, admin flag. 7-day expiry. Good?

**Expected:**
- Refuses email + admin in payload (visible to anyone with the token).
- Refuses 7-day expiry.
- Recommends 15-min access + 14-day refresh with rotation.
- Stores refresh-token digest server-side.

**Rubric:**
- [ ] No PII in payload
- [ ] Short access + refresh
- [ ] Digest, not raw token, stored

---

## Prompt 4: "CORS wildcard"

**User prompt:**
> Set `origins "*"` for CORS. My SPA needs to call the API.

**Expected:**
- Refuses wildcard.
- Recommends ENV-driven origins list.
- Explains the future-risk: every endpoint inherits.

**Rubric:**
- [ ] Wildcard refused
- [ ] ENV-driven list
- [ ] Future-risk explained

---

## Prompt 5: "Should I encrypt the email column?"

**User prompt:**
> Should I encrypt the email column in users with Active Record Encryption?

**Expected:**
- Trade-off: yes for compliance / privacy; no if you need to query by email.
- Deterministic mode lets you query but is weaker.
- Non-deterministic is more secure but unqueryable.
- Email is rarely the right call (you query by it constantly); SSN, DOB, address are better candidates.

**Rubric:**
- [ ] Acknowledged trade-off
- [ ] Deterministic vs non-deterministic distinction
- [ ] Did not just say "yes"

---

## Prompt 6: "SSRF risk"

**User prompt:**
> I'm building an "import from URL" feature. User pastes a URL, we fetch it.

**Expected:**
- Identifies SSRF.
- Resolves the URL, validates the IP isn't private/loopback/link-local.
- Allowlist scheme to http/https.
- Short timeout, no redirect-following without re-validation.
- Mentions egress restrictions at the container level.

**Rubric:**
- [ ] SSRF identified
- [ ] IP validation logic shown
- [ ] Scheme allowlist
- [ ] Timeouts

---

## Prompt 7: "Webhook from Stripe"

**User prompt:**
> How do I receive Stripe webhooks securely?

**Expected:**
- Skip CSRF on the webhook controller.
- Verify signature: `Stripe::Webhook.construct_event(payload, sig_header, secret)`.
- Store webhook secret in Rails credentials.
- Idempotency: store webhook IDs to prevent replay (Stripe's `event.id`).

**Rubric:**
- [ ] Signature verification
- [ ] Secret in credentials
- [ ] Idempotency mentioned
