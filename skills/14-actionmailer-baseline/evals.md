# Evals for `actionmailer-baseline`

## Prompt 1: "Send a welcome email after signup"

**User prompt:**
> After User.create, send a welcome email.

**Expected:**
- `UserMailer.welcome(@user).deliver_later` in controller.
- Notes `deliver_later` over `deliver_now`.
- Mentions enqueueing from after_commit on the model is cleaner than from controller.

**Rubric:**
- [ ] deliver_later used
- [ ] Async benefit explained
- [ ] after_commit alternative noted

---

## Prompt 2: "Why is signup slow?"

**User prompt:**
> POST /users takes 1.5 seconds. The controller does `UserMailer.welcome(@user).deliver_now`.

**Expected:**
- Identifies the synchronous email send as the cause.
- Switches to `deliver_later`.
- Mentions worker process handles delivery.

**Rubric:**
- [ ] Diagnosed sync send
- [ ] deliver_later fix
- [ ] Async pattern explained

---

## Prompt 3: "Preview emails before sending"

**User prompt:**
> How do I see what the welcome email looks like in development?

**Expected:**
- Mailer Preview class in `spec/mailers/previews/`.
- Visit `/rails/mailers/user_mailer/welcome`.
- Optionally Letter Opener for actual-send simulation.

**Rubric:**
- [ ] Mailer Preview shown
- [ ] /rails/mailers route mentioned
- [ ] Letter Opener as second option

---

## Prompt 4: "Vendor for transactional email"

**User prompt:**
> What service should I use for transactional emails in Rails 8?

**Expected:**
- Postmark for transactional (highest deliverability).
- SES if cost-sensitive at scale.
- Not just "SendGrid because everyone uses it".
- Brief decision matrix.

**Rubric:**
- [ ] Trade-off explained
- [ ] Postmark recommended for transactional
- [ ] SES mentioned for high-volume

---

## Prompt 5: "Bounces"

**User prompt:**
> Some user emails bounce. What should I do?

**Expected:**
- Vendor webhook → mark user as `deliverable: false`.
- Suppression list at the mailer level (`before_action`).
- Reputation damage explained.

**Rubric:**
- [ ] Webhook + suppression
- [ ] before_action filter shown
- [ ] Reputation reason given

---

## Prompt 6: "Welcome email sent twice on retry"

**User prompt:**
> My WelcomeEmailJob occasionally sends the email twice. The job retries.

**Expected:**
- Add idempotency: `welcome_sent_at` column, check at start of job.
- After successful send, update the column.
- Subsequent retries are no-ops.

**Rubric:**
- [ ] Idempotency added
- [ ] sent_at column pattern
- [ ] Did not just suggest "disable retry"
