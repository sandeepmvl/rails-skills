# Evals for `rails-upgrade-7-to-8`

## Prompt 1: "Upgrade to Rails 8"

**User prompt:**
> We're on Rails 7.0. Want to get to Rails 8.

**Expected:**
- Hop: 7.0 → 7.1 → 7.2 → 8.0.
- Dual-boot with next_rails.
- Note Ruby 3.2+ required.
- Don't adopt Solid Queue / Propshaft in the same PR.

**Rubric:**
- [ ] Hop sequence
- [ ] Dual-boot
- [ ] Ruby version check
- [ ] Adoption deferred

---

## Prompt 2: "Solid Queue mandatory?"

**User prompt:**
> Does upgrading to Rails 8 mean I have to switch from Sidekiq to Solid Queue?

**Expected:**
- No — Rails 8 default for `rails new`, not required for existing apps.
- Stick with Sidekiq if using Pro features.
- Migration is a separate project.

**Rubric:**
- [ ] Not mandatory
- [ ] Sidekiq stays valid
- [ ] Separate-project framing

---

## Prompt 3: "Propshaft migration"

**User prompt:**
> Should I migrate from Sprockets to Propshaft as part of the Rails 8 upgrade?

**Expected:**
- Defer. Audit Sprockets-specific usage first.
- Separate project; risky if app has ERB-templated SCSS, custom processors.
- Most apps benefit; some don't.

**Rubric:**
- [ ] Deferred
- [ ] Audit-first
- [ ] Trade-off discussed

---

## Prompt 4: "next_rails dual-boot"

**User prompt:**
> How does next_rails work?

**Expected:**
- Creates Gemfile.next + Gemfile.next.lock.
- `BUNDLE_GEMFILE=Gemfile.next` switches.
- CI runs both gemfiles.
- Use `next?` helper in Gemfile for conditional gem versions.

**Rubric:**
- [ ] Gemfile.next explained
- [ ] Bundle env var
- [ ] CI parallel runs
- [ ] next? helper

---

## Prompt 5: "Skip the version hops"

**User prompt:**
> Can I just bump Gemfile from "~> 7.0" to "~> 8.0" and fix what breaks?

**Expected:**
- Refuses for non-trivial app.
- Each minor version has its own deprecation set; piling them up is unfixable.
- Hop one minor at a time.
- Tiny apps with thin coverage can sometimes get away with it.

**Rubric:**
- [ ] Refused for non-trivial apps
- [ ] Per-version deprecation reason
- [ ] Honest about tiny-app exception
