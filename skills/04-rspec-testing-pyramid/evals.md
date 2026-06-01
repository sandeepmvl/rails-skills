# Evals for `rspec-testing-pyramid`

## Prompt 1: "How should I test this controller action?"

**User prompt:**
> What spec should I write for `PostsController#create`?

**Expected:**
- Request spec, not system spec, not controller spec.
- Covers: valid params → 201/redirect, invalid params → render :new with errors, auth fail → 401/403.
- Uses FactoryBot for setup.

**Rubric:**
- [ ] Recommended request spec
- [ ] Listed the three branches (happy, validation fail, auth fail)
- [ ] Used factories

---

## Prompt 2: "My spec hits a real Stripe endpoint"

**User prompt:**
> My SyncToStripe service spec is calling the real Stripe API. I want it to stop.

**Expected:**
- Recommends VCR with `:vcr` metadata.
- Shows VCR config with `filter_sensitive_data` for the Stripe key.
- Shows the cassette record-once pattern.
- Mentions WebMock as the hand-rolled alternative.

**Rubric:**
- [ ] VCR recommended
- [ ] Credential filter included
- [ ] Cassette-commit-to-git mentioned

---

## Prompt 3: "Should I use let or let!?"

**User prompt:**
> When should I use let vs let! in RSpec?

**Expected:**
- Default to `let` (lazy).
- `let!` only when the side effect must precede the test body.
- Example of each.
- Warns against `before(:all)`.

**Rubric:**
- [ ] let as default
- [ ] let! reason explained
- [ ] before(:all) warned against

---

## Prompt 4: "My system specs are flaky"

**User prompt:**
> My Cuprite system specs fail intermittently. Sometimes they pass, sometimes they don't.

**Expected:**
- Refuses `sleep` as the fix.
- Recommends Capybara's auto-waiting matchers (`have_content`, `have_selector`, `have_no_content`).
- Recommends `Capybara.default_max_wait_time = 5` (or higher in CI).
- For specs that wait on AJAX, recommends `assert_current_path` + Capybara assertions, not custom `Timeout`.

**Rubric:**
- [ ] Refused sleep / wait
- [ ] Recommended auto-waiting matchers
- [ ] Did not blame Cuprite — flakiness is in the test

---

## Prompt 5: "Factory has a validation failure"

**User prompt:**
> `create(:user)` fails with `Validation failed: Email has already been taken`.

**Expected:**
- Identifies missing `sequence` on email in the factory.
- Shows the fix: `sequence(:email) { |n| "user#{n}@example.com" }`.

**Rubric:**
- [ ] Identified the uniqueness collision
- [ ] Fixed with sequence
- [ ] Did not suggest `email { SecureRandom.hex }` (works but less idiomatic)

---

## Prompt 6: "Test suite is 25 minutes — speed it up"

**User prompt:**
> Our RSpec suite takes 25 minutes. How do I make it faster?

**Expected behavior in priority order:**
1. Audit: how many specs, what types, how many system specs.
2. If >10% system specs, convert non-JS ones to request specs.
3. Add `parallel_tests` for parallel runs (break-even ~500 specs).
4. Bullet failing in test = fix the N+1s — slow specs often run slow DB queries.
5. SimpleCov adds ~10% overhead — disable in local dev runs.

**Rubric:**
- [ ] Audited rather than jumped to "add parallel"
- [ ] System → request conversion mentioned
- [ ] parallel_tests with break-even caveat
- [ ] Mentioned N+1s in specs as a frequent cause
