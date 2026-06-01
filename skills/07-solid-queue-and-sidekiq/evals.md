# Evals for `solid-queue-and-sidekiq`

## Prompt 1: "Solid Queue or Sidekiq?"

**User prompt:**
> Greenfield Rails 8 app, B2B SaaS, ~1000 jobs/day. Solid Queue or Sidekiq?

**Expected:**
- Recommends Solid Queue.
- Reasons: no Redis, ships with Rails 8, throughput is plenty for the load.
- Acknowledges Sidekiq is the call when team already runs Redis or needs Pro features.

**Rubric:**
- [ ] Solid Queue recommended
- [ ] No-Redis benefit noted
- [ ] Sidekiq trigger conditions listed

---

## Prompt 2: "Should I background this?"

**User prompt:**
> Should I move `User.create!` to a background job?

**Expected:**
- Asks how long it takes. If <200ms, no.
- Says async overhead (queue + serialize + deserialize + worker pickup) exceeds the gain.
- Recommends async only for the *expensive* side effects (welcome email, CRM sync).

**Rubric:**
- [ ] Did not auto-recommend async
- [ ] Mentioned latency threshold (~200ms)
- [ ] Identified the right things to async (mail, external)

---

## Prompt 3: "Job double-charges customers on retry"

**User prompt:**
> My ChargeCustomerJob occasionally double-charges. The retry on network failure is firing the Stripe call twice.

**Expected:**
- Identifies missing idempotency.
- Recommends Stripe's `idempotency_key` parameter.
- Adds `return if order.paid?` guard.
- Notes both belt-and-suspenders.

**Rubric:**
- [ ] Identified idempotency gap
- [ ] Stripe idempotency_key recommended
- [ ] State-check guard added

---

## Prompt 4: "Job fires before transaction commits"

**User prompt:**
> My job is failing with `ActiveRecord::RecordNotFound`. It's enqueued from `after_save`.

**Expected:**
- Identifies the after_save vs after_commit race.
- Switches to `after_commit`.
- Adds a change predicate (`saved_change_to_*?`).
- Links to `activerecord-patterns` Pattern 7.

**Rubric:**
- [ ] Diagnosed pre-commit race
- [ ] after_commit fix
- [ ] Change-predicate added

---

## Prompt 5: "How do I schedule a daily job?"

**User prompt:**
> I want to send a digest email every morning at 9am.

**Expected:**
- If Solid Queue: `config/recurring.yml` entry.
- If Sidekiq: `sidekiq-cron` with `config/schedule.yml`.
- Does NOT recommend `whenever` gem (single-host crontab).

**Rubric:**
- [ ] Used job-system-native scheduling
- [ ] Recurring.yml or sidekiq-cron mentioned
- [ ] whenever rejected

---

## Prompt 6: "Dead jobs piling up"

**User prompt:**
> My Sidekiq dead set has 500 jobs from yesterday. What do I do?

**Expected:**
- Recommend reading the error. Common: external API outage + transient.
- If transient: replay (`DeadSet.new.each(&:retry)`).
- If code bug: fix code first.
- Mentions alerting on dead set count.

**Rubric:**
- [ ] Did not auto-replay without reading errors
- [ ] Replay command shown
- [ ] Recommended alert setup going forward
