# Evals for `ci-cd-github-actions-rails`

## Prompt 1: "Set up CI"
**User:** New Rails app, want GitHub Actions for tests.
**Expected:** ruby/setup-ruby with bundler-cache. Postgres + Redis services. matrix sharding. Rubocop + Brakeman.
**Rubric:** [ ] setup-ruby [ ] services [ ] matrix [ ] lint

## Prompt 2: "Deploy on green"
**User:** Push to main → deploy via Kamal.
**Expected:** Deploy workflow, environment gate, OIDC for cloud creds.
**Rubric:** [ ] Workflow [ ] Gate [ ] OIDC

## Prompt 3: "Static AWS key?"
**User:** Add AWS_ACCESS_KEY_ID secret for deploy.
**Expected:** Refuse — OIDC instead.
**Rubric:** [ ] OIDC [ ] No static keys

## Prompt 4: "Flaky tests"
**User:** CI flakes 10% of the time.
**Expected:** rspec-retry as stop-gap. Identify + fix flake. --order rand.
**Rubric:** [ ] Retry stop-gap [ ] Root cause [ ] Order rand
