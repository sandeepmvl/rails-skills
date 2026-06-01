# Evals for `rails-project-discovery`

> Test prompts a real Rails dev would type. Run the skill against each and check the output against the rubric. If the skill fails any rubric, it's not ready to ship.

## Prompt 1: Greenfield Rails 8 SaaS monolith

**User prompt:**
> Help me start a new Rails project for a B2B SaaS. I want the Rails 8 defaults, Postgres, Devise, and Kamal deploys.

**Expected behavior:**
- Asks the Group 1 interview (or recognizes most of it is already answered and confirms remaining gaps — auth, frontend interactivity, traffic).
- After interview, lists loaded skills: at minimum `activerecord-patterns`, `rspec-testing-pyramid`, `safe-migrations`, `rails-security-baseline`, `observability-baseline`, `solid-queue-and-sidekiq`, `devise-pundit-rodauth`, `kamal-docker-production`, `hotwire-turbo-stimulus`, `actionmailer-baseline`.
- Lists explicitly *not* loaded with one-line reasons: `n-plus-one-killer`, `rails-caching-strategy`, `service-objects-vs-fat-models`, `rails-api-design`, `activestorage-uploads`.
- Suggests `rails new <name> --database=postgresql --css=tailwind --javascript=importmap --skip-test` as the first command, then RSpec + Devise + Solid Queue setup.
- Does NOT run `rails new` before confirming with the user.

**Rubric (pass/fail):**
- [ ] Interview happened (or was correctly skipped because user answered everything)
- [ ] Loaded list matches expected
- [ ] Skipped list has reasons
- [ ] First-action command is correct and uses Postgres
- [ ] Did not silently swap Solid Queue → Sidekiq

---

## Prompt 2: Existing Rails 6.1 API-only app, performance review

**User prompt:**
> I have a Rails 6.1 API-only app on MySQL with Sidekiq. Some endpoints are slow. Help me audit and fix.

**Expected behavior:**
- Skips Group 3 (existing app, not greenfield).
- Recognizes "existing Rails 6 staying on that version" routing: loads `n-plus-one-killer`, `rails-caching-strategy`, `service-objects-vs-fat-models`, plus universals.
- Loads `rails-api-design` (API-only).
- Loads `solid-queue-and-sidekiq` (because Sidekiq is mentioned — covers the Sidekiq half).
- Does NOT load `hotwire-turbo-stimulus` (API-only).
- Does NOT load `kamal-docker-production` unless deploy target is mentioned.
- Suggests first action: run Bullet against the slow endpoints, or `EXPLAIN ANALYZE` on the slowest queries.

**Rubric:**
- [ ] Recognized this is existing, not greenfield
- [ ] Loaded performance skills (n-plus-one-killer, caching, service-objects)
- [ ] Loaded API skill
- [ ] Did NOT load Hotwire
- [ ] First action is diagnostic, not "write code"

---

## Prompt 3: Upgrading from Rails 4.2 to current

**User prompt:**
> We're on Rails 4.2 with Ruby 2.5. The team wants to get to Rails 8. Where do we even start?

**Expected behavior:**
- Triggers the "I want to upgrade from Rails X to Rails Y" special case.
- Recommends the `next_rails` gem for dual-booting.
- Plans the upgrade one minor version at a time: 4.2 → 5.0 → 5.1 → 5.2 → 6.0 → 6.1 → 7.0 → 7.1 → 7.2 → 8.0.
- Says explicitly that the upgrade is weeks-to-months for a non-trivial app.
- Notes that the specific `rails-upgrade-X-to-Y` skills are coming in v0.2 — gives the manual workflow now.
- Loads universals + `n-plus-one-killer`, `rails-caching-strategy`, `service-objects-vs-fat-models`, `rails-security-baseline`.

**Rubric:**
- [ ] Did not generate a "single-shot upgrade" patch
- [ ] Mentioned `next_rails` for dual-boot
- [ ] Listed every minor version hop
- [ ] Set realistic time expectation (weeks-to-months)
- [ ] Acknowledged v0.2 gap honestly

---

## Prompt 4: Solo dev wants a microservice architecture

**User prompt:**
> I'm building this solo, and I want to split the user service, billing service, and notification service into separate apps. Can you set up the architecture?

**Expected behavior:**
- Refuses politely. Explains the Majestic Monolith position: monoliths win for small teams.
- Asks for the concrete reason (regulatory isolation, different scaling, team org).
- If the user pushes back without a concrete reason, sticks to the refusal and recommends a single Rails app with clear internal boundaries (engines or modules).
- If the user gives a real reason, proceeds — but warns the relevant skills are v0.3 and provides manual guidance referencing `external-api-integration` (v0.2).

**Rubric:**
- [ ] Did not silently set up three services
- [ ] Quoted or paraphrased Majestic Monolith reasoning
- [ ] Asked for concrete reason
- [ ] If user persisted without reason, held the line

---

## Prompt 5: Single-skill bypass

**User prompt:**
> Use the n-plus-one-killer skill on `app/controllers/posts_controller.rb`.

**Expected behavior:**
- Skips the interview entirely.
- Loads only `n-plus-one-killer` and goes directly to that skill's workflow.
- Does NOT ask about deployment, traffic, team size, etc.

**Rubric:**
- [ ] No interview ran
- [ ] Only the named skill loaded
- [ ] Got straight to work

---

## Prompt 6: One-off question, no project context

**User prompt:**
> What's the difference between `find_by` and `where.first` in ActiveRecord?

**Expected behavior:**
- Does NOT trigger the orchestrator interview.
- Answers the question directly with a concise explanation and a tiny code example.
- (May reference `activerecord-patterns` if the user asks to go deeper.)

**Rubric:**
- [ ] No interview
- [ ] Direct answer
- [ ] Concise

---

## Prompt 7: Joining an existing project, no info given

**User prompt:**
> I just inherited this Rails codebase. Help me understand it.

**Expected behavior:**
- Triggers the "I'm joining an existing Rails project" special case.
- Skips Groups 3 and 4.
- Inspects `Gemfile.lock`, `config/application.rb`, `config/database.yml`, `config/routes.rb`, `bundle list | grep …` to infer Group 1 + 2 answers.
- Confirms inferences with the user before proceeding.

**Rubric:**
- [ ] Inspected files (rather than asking the developer to type version numbers)
- [ ] Inferred Rails version, app type, database, auth gems
- [ ] Confirmed inferences with user before loading skills
