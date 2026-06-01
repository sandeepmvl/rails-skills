---
name: rspec-testing-pyramid
description: RSpec testing for Ruby on Rails — pyramid shape (lots of model + request specs, fewer system specs), FactoryBot patterns, let vs let! vs before, shared examples, VCR for external HTTP, system specs with Capybara + Cuprite, transactional vs truncation strategy, parallel testing, SimpleCov coverage. Use when writing or reviewing Rails tests, the user mentions RSpec, FactoryBot, Capybara, Cuprite, VCR, system specs, request specs, model specs, fixtures, factories, flaky tests, slow test suite, parallel_rspec, or asks for help with rails_helper / spec_helper. Bundles drop-in spec_helper.rb + rails_helper.rb + .rspec templates.
---

# RSpec Testing Pyramid

> Build a fast, deterministic Rails test suite. AI agents over-write system specs (slow, flaky), under-write request specs (the sweet spot), and reach for hard-coded `id: 1` instead of factories. This skill encodes the layer choices senior Rails devs make.

## Why this matters

A bad test suite is worse than no test suite. It slows CI, surfaces false positives, and trains devs to ignore failures. AI agents default to system specs because they read most like the user's intent — but a 200-spec system suite that runs 30 minutes and is 5% flaky is a productivity catastrophe.

## The opinion

> **Pyramid shape: lots of model + request specs (fast, deterministic), few system specs (slow, only critical user flows). Use FactoryBot, not fixtures. RSpec hooks: prefer `let` over `before` for setup that's used by some tests; `let!` only when the side-effect must precede the example. Stub external HTTP — use VCR for cassette-replay, WebMock for hand-rolled stubs. System specs with Cuprite over Selenium (faster, no driver install).**

Counter-position: Minitest + Rails fixtures is what DHH and the Rails core team use. It's faster to load and forces simpler tests. For greenfield apps that won't ship to a large dev team, Minitest is fine. We pick RSpec because most ecosystem libraries (FactoryBot, Shoulda Matchers, VCR) target RSpec first and the team-size break-even is around 3+ engineers.

## The pyramid (Rails-specific)

```
                  ┌──────────────┐
                  │ system specs │  ← 5-10% of specs. Critical user flows only.
                  │  (Cuprite)   │     Slow (1-5s each). Run separately in CI.
                  └──────┬───────┘
                         │
                ┌────────┴─────────┐
                │  request specs    │  ← 25-35% of specs. Full HTTP cycle,
                │  (rack-test)      │     no JS. Routes + controller + view.
                └────────┬──────────┘    Fast (10-50ms each).
                         │
              ┌──────────┴───────────┐
              │   model specs +       │  ← 50-60% of specs.
              │   service specs +     │     Pure Ruby, in-memory or single DB.
              │   helper specs        │     Fastest (1-10ms each).
              └───────────────────────┘
```

## Core patterns

### Pattern 1: Layer choice — when to write what

```ruby
# Model spec — for any ActiveRecord method beyond CRUD
RSpec.describe Post, type: :model do
  it "marks the post as published" do
    post = create(:post, :draft)
    post.publish!
    expect(post).to be_published
    expect(post.published_at).to be_present
  end
end

# Request spec — for any controller behavior the model can't cover
RSpec.describe "POST /posts/:id/publish", type: :request do
  it "publishes the post and redirects" do
    sign_in user
    draft = create(:post, :draft, author: user)
    post post_publish_path(draft)   # local is `draft`, not `post` — avoids shadowing the HTTP helper
    expect(response).to redirect_to(draft)
    expect(draft.reload).to be_published
  end

  it "returns 403 for non-author" do
    sign_in other_user
    draft = create(:post, :draft)
    post post_publish_path(draft)
    expect(response).to have_http_status(:forbidden)
  end
end

# System spec — only when JS or full user journey matters
RSpec.describe "User publishes a post", type: :system do
  it "shows the published banner after publish" do
    sign_in user
    post = create(:post, :draft, author: user)
    visit edit_post_path(post)
    click_button "Publish"
    expect(page).to have_content("Published")
  end
end
```

**Rule of thumb:** write the spec at the lowest layer that can verify the behavior. A model can be tested by model spec — don't write a system spec for it.

### Pattern 2: FactoryBot conventions

**Before** (AI-typical — repeated, brittle):

```ruby
let(:user) { User.create!(email: "test@example.com", password: "password123") }
let(:post) { Post.create!(title: "Hello", author: user, status: "draft") }
```

**After**:

```ruby
# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    confirmed_at { Time.current }  # Devise's confirmable

    trait :admin do
      role { "admin" }
    end
  end
end

# spec/factories/posts.rb
FactoryBot.define do
  factory :post do
    title { "Hello world" }
    body { "Body text" }
    association :author, factory: :user

    trait :draft do
      status { "draft" }
    end

    trait :published do
      status { "published" }
      published_at { 1.day.ago }
    end

    trait :with_comments do
      after(:create) { |draft| create_list(:comment, 3, post: draft) }
    end
  end
end

# spec
let(:user) { create(:user, :admin) }
let(:post) { create(:post, :published, :with_comments, author: user) }
```

**Why FactoryBot patterns matter:**
- **Sequences** for uniqueness (email) avoid validation failures across tests.
- **Traits** name common variants — `:admin`, `:draft`, `:with_comments` — without bloating the factory.
- **`association :author, factory: :user`** lets the named association be different from the model class name.
- **`after(:create)` callbacks** for composite setup, only when traits aren't enough.

### Pattern 3: `let` vs `let!` vs `before`

```ruby
# `let` — lazy. Block runs the first time the symbol is referenced.
let(:user) { create(:user) }

# `let!` — eager. Block runs in a `before` hook regardless of reference.
# Use only when the side effect (record creation, system state change) must happen
# BEFORE the example body even if the body doesn't touch the symbol.
let!(:user) { create(:user) }  # because the spec asserts User.count

# `before` — explicit setup that isn't a value.
before do
  sign_in user
  travel_to Date.new(2026, 1, 1)
end

# `before(:all)` — DANGEROUS. Runs once for the whole describe block.
# State leaks between examples. Don't use.
before(:all) { @user = create(:user) }  # AVOID
```

**Rules:**
- Prefer `let` over `before` + instance variable.
- Prefer `let!` only when the side effect must precede the test.
- Never `before(:all)` — leaks state, breaks parallel.
- Don't share state between examples within a spec — each example must be runnable in isolation.

### Pattern 4: Shared examples

For behavior that repeats across models / controllers:

```ruby
# spec/support/shared_examples/sluggable.rb
RSpec.shared_examples "sluggable" do
  it "generates a slug from the title" do
    record = create(described_class.model_name.singular.to_sym, title: "Hello World")
    expect(record.slug).to eq("hello-world")
  end

  it "ensures slug uniqueness" do
    create(described_class.model_name.singular.to_sym, title: "Same")
    expect { create(described_class.model_name.singular.to_sym, title: "Same") }
      .to change { described_class.last.slug }.to /same-/
  end
end

# spec/models/post_spec.rb
RSpec.describe Post do
  include_examples "sluggable"
end

# spec/models/page_spec.rb
RSpec.describe Page do
  include_examples "sluggable"
end
```

**When to use:** behavior is identical across 3+ models. For 2 models, just write the test twice — DRY testing is a frequent trap that hides per-model differences.

### Pattern 5: VCR + WebMock — stubbing external HTTP

Hitting real third-party APIs in tests is non-deterministic, slow, and a credential leak risk.

```ruby
# spec/support/vcr.rb
VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.default_cassette_options = { record: :new_episodes }
  config.filter_sensitive_data("<STRIPE_KEY>") { ENV["STRIPE_SECRET_KEY"] }
  config.filter_sensitive_data("<AUTH>") { |interaction|
    interaction.request.headers["Authorization"]&.first
  }
end

# Auto-cassette per spec with :vcr metadata
RSpec.describe SyncToHubspot, :vcr do
  it "upserts a contact" do
    contact = create(:contact, email: "test@example.com")
    SyncToHubspot.new(contact).call
    expect(contact.reload.hubspot_id).to be_present
  end
end
```

**Cassette hygiene:**
- Filter every credential from cassettes (`filter_sensitive_data`).
- Re-record annually or when the API changes (`record: :new_episodes` once, then `:once` after).
- Commit cassettes to git — they're test fixtures.

**Alternatively, WebMock** for hand-rolled stubs when you don't need a real response shape:

```ruby
before do
  stub_request(:post, "https://api.hubspot.com/contacts/v1/contact").to_return(
    status: 200, body: { id: 123 }.to_json, headers: { "Content-Type" => "application/json" }
  )
end
```

### Pattern 6: System specs — Cuprite over Selenium

```ruby
# Gemfile
group :test do
  gem "capybara"
  gem "cuprite"
end

# spec/support/system.rb
require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [1400, 900], headless: ENV.fetch("HEADLESS", "true") == "true")
end

Capybara.javascript_driver = :cuprite
Capybara.default_driver = :rack_test  # non-JS specs use rack-test

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by(:rack_test) }
  config.before(:each, type: :system, js: true) { driven_by(:cuprite) }
end
```

**Why Cuprite:**
- No Selenium driver to install (uses Chrome's DevTools Protocol directly).
- Faster than Selenium for the same work.
- Better debugging (`page.driver.debug` opens a real browser).
- One less dependency than `selenium-webdriver` + `webdrivers` / `selenium-manager`.

**System spec rules:**
- Keep the count low (5–10% of total specs).
- Cover the critical happy path of each feature, not exhaustive variants (cover variants with request specs).
- `js: true` only when the test actually needs JS. Most "click and assert" tests don't.

### Pattern 7: Transactional vs truncation

```ruby
# spec/rails_helper.rb
require "database_cleaner/active_record"

RSpec.configure do |config|
  # Keep Rails' transactional fixtures ON for everything except JS system specs.
  # Stacking DatabaseCleaner :transaction on top of use_transactional_fixtures = true
  # double-wraps and can roll back state unexpectedly. So we explicitly disable Rails'
  # built-in transactions ONLY for JS system specs, and run DatabaseCleaner truncation there.
  config.use_transactional_fixtures = true

  config.before(:each, type: :system, js: true) do
    self.use_transactional_tests = false
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.start
  end

  config.after(:each, type: :system, js: true) do
    DatabaseCleaner.clean
  end
end
```

**Why:** transactional tests roll back the entire test in a single SAVEPOINT, ~10× faster than truncation. But Capybara JS specs run the test and the app server in different threads — they need a real commit so the JS-driven request sees the data. Truncation handles that case.

On Rails 7+, the built-in `use_transactional_tests` covers the non-JS path; `database_cleaner-active_record` is still the cleanest way to handle JS-system-spec truncation.

### Pattern 8: Parallel testing

For suites over ~500 specs, parallel cuts wall time meaningfully:

```ruby
# Rails 6+ built-in
# config/environments/test.rb
config.eager_load = true  # required for parallel

# In CI:
bin/rails db:create RAILS_ENV=test  # creates test database
bin/rails test:prepare              # loads schema into each parallel test DB

# Run with N workers (one DB per worker):
bin/rspec --tag ~slow                       # serial, fastest for <500 specs
bundle exec parallel_rspec spec --type=rspec  # parallel_tests gem
```

```ruby
# spec/rails_helper.rb — auto-isolate DBs in parallel mode
require "rspec/rails"

# parallel_tests sets ENV["TEST_ENV_NUMBER"] for each worker (blank or "2", "3", …)
# Rails handles the DB name suffix automatically when:
# config/database.yml has:
#   test:
#     database: myapp_test<%= ENV["TEST_ENV_NUMBER"] %>
```

**Trade-off:** parallel CI per-worker DB setup is slower than a serial single-DB run for small suites. Break-even is around 500–800 specs.

### Pattern 9: SimpleCov — coverage tracking

```ruby
# spec/spec_helper.rb (must be FIRST require, before Rails)
require "simplecov"
SimpleCov.start "rails" do
  add_filter "/spec/"
  add_filter "/config/"
  add_filter "/vendor/"

  add_group "Models",      "app/models"
  add_group "Controllers", "app/controllers"
  add_group "Services",    "app/services"
  add_group "Jobs",        "app/jobs"

  minimum_coverage 80
  minimum_coverage_by_file 70
end
```

```yaml
# .github/workflows/ci.yml — upload coverage
- run: bundle exec rspec
- uses: actions/upload-artifact@v4
  with:
    name: coverage
    path: coverage/
```

**Threshold rationale:** 80% line coverage is a healthy floor. Coverage measures presence of tests, not quality — don't chase 100%. Untested code is rarely the bug source; subtle untested *cases* are. Coverage flags gaps; doesn't certify quality.

## Decision matrix — what spec at what layer

| Behavior | Spec type |
|---|---|
| Model validation, scope, method | Model spec |
| Service-object call | Service spec (model spec without ActiveRecord setup) |
| Background job logic | Job spec (`perform_now` directly) |
| Controller action — auth, params, response status, redirect | Request spec |
| Controller action — full render cycle, view content | Request spec |
| API endpoint — JSON shape | Request spec |
| Multi-page user flow with JS | System spec (Cuprite, `js: true`) |
| Form submit + redirect (no JS) | Request spec (NOT system spec) |
| Mailer rendering | Mailer spec + preview |
| ViewComponent / partial | View spec or component spec |

## Common mistakes to refuse

- Don't write system specs for things request specs cover — slower for no benefit.
- Don't share state with `before(:all)` or class instance variables — breaks isolation.
- Don't hit real external APIs in tests — VCR or WebMock.
- Don't `User.create!(email: "test@…")` repeatedly — use factories with sequences.
- Don't add `wait` / `sleep` to flaky system specs — fix the race instead (Capybara's matchers already wait).
- Don't disable failing tests to make CI green — fix or delete.
- Don't `Bundler.require` before SimpleCov — coverage will miss files loaded during boot.
- Don't aim for 100% coverage. 80% is the floor; quality matters more than line count.

## When NOT to use this skill

- The user is asking how to test something specific (`how do I test a Devise sign-in?`) — answer directly without restating the pyramid.
- The user is using Minitest — note this skill is RSpec-specific; the pyramid shape transfers but the API doesn't.

## See also

- `activerecord-patterns` — what to test in model specs
- `service-objects-vs-fat-models` — service spec setup
- `solid-queue-and-sidekiq` — job spec patterns
- `rails-api-design` — request spec patterns for API endpoints

## Bundled assets

- [`assets/spec-helper-template.rb`](assets/spec-helper-template.rb) — drop-in spec_helper.rb
- [`assets/rails-helper-template.rb`](assets/rails-helper-template.rb) — drop-in rails_helper.rb with FactoryBot, VCR, Cuprite
- [`assets/dot-rspec`](assets/dot-rspec) — .rspec config

## Sources

- [RSpec Rails docs](https://rspec.info/documentation/) — request/system/model spec types
- [FactoryBot — Getting Started](https://github.com/thoughtbot/factory_bot/blob/main/GETTING_STARTED.md)
- [Capybara README](https://github.com/teamcapybara/capybara)
- [Cuprite README](https://github.com/rubycdp/cuprite)
- [VCR README](https://github.com/vcr/vcr)
- [WebMock README](https://github.com/bblimke/webmock)
- [Shoulda Matchers](https://github.com/thoughtbot/shoulda-matchers)
- [SimpleCov README](https://github.com/simplecov-ruby/simplecov)
- [parallel_tests](https://github.com/grosser/parallel_tests)
- [Rails Guides — Testing](https://guides.rubyonrails.org/testing.html) — the canonical reference
- [thoughtbot — Let's Not](https://thoughtbot.com/blog/lets-not) — the case against overusing RSpec DSL
