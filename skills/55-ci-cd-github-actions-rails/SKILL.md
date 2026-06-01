---
name: ci-cd-github-actions-rails
description: GitHub Actions CI/CD for Rails 8 — RSpec, Brakeman, RuboCop, bundle audit, system specs with Cuprite, parallel matrix tests, caching gems and node_modules, Kamal deploy job gated on green main, OIDC + AWS / GCP without long-lived keys, branch protection rules. Use when the user mentions GitHub Actions, GHA, CI, workflow, .github/workflows, deploy via GitHub, OIDC, push protection, or asks how to set up CI for a Rails app.
---

# GitHub Actions for Rails

> The default CI/CD for new Rails projects. Fast, free up to 2000 min/month for private repos, generous for public. This skill gives you a production-grade workflow file plus the principles (cache aggressively, parallelize tests, gate deploys on green main, OIDC over long-lived secrets).

## The opinion

> **One workflow per concern (CI, Deploy, Security Scan). Parallelize tests via matrix. Cache gems, Yarn, and asset builds. Use the official `ruby/setup-ruby` action with `bundler-cache: true`. Use OIDC for AWS / GCP — never long-lived `AWS_ACCESS_KEY_ID` secrets. Deploy via Kamal on push to main, after CI passes. Branch protection on main: PR + 1 review + green CI + linear history.**

## Pattern 1: The CI workflow

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true   # cancel earlier runs on the same branch

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 20

    services:
      postgres:
        image: postgres:16
        ports: ["5432:5432"]
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd "pg_isready -U postgres"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

      redis:
        image: redis:7
        ports: ["6379:6379"]
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    strategy:
      fail-fast: false
      matrix:
        ci_node_total: [4]
        ci_node_index: [0, 1, 2, 3]

    env:
      RAILS_ENV: test
      DATABASE_URL: postgres://postgres:postgres@localhost:5432/myapp_test
      REDIS_URL: redis://localhost:6379/1
      CI_NODE_TOTAL: ${{ matrix.ci_node_total }}
      CI_NODE_INDEX: ${{ matrix.ci_node_index }}

    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true   # gems cached automatically per Gemfile.lock hash

      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: yarn

      - run: yarn install --frozen-lockfile

      - name: Build assets
        run: bin/rails assets:precompile

      - name: Database setup
        run: bin/rails db:prepare

      - name: RSpec (sharded)
        run: bin/rspec --tag ~slow

      - name: Upload coverage
        if: matrix.ci_node_index == 0
        uses: codecov/codecov-action@v4
        with:
          token: ${{ secrets.CODECOV_TOKEN }}
```

`bundler-cache: true` caches by `Gemfile.lock` content hash. Cache hit = 5-10s instead of 60-90s `bundle install`.

`concurrency.cancel-in-progress` cancels older runs when you push again. Saves minutes.

Matrix shards split RSpec into 4 parallel jobs (use `knapsack_pro`, `parallel_tests`, or `flatware` for actual sharding).

## Pattern 2: Linting + security in separate jobs

```yaml
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - run: bundle exec rubocop --parallel
      - run: bundle exec brakeman --no-pager --quiet -A
      - run: bundle exec bundle-audit check --update

  security_scan:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      # GitHub's CodeQL — free for public, paid for private
      - uses: github/codeql-action/init@v3
        with: { languages: ruby }
      - uses: github/codeql-action/analyze@v3
```

Separate jobs = parallel = faster signal.

## Pattern 3: System specs with Cuprite

```yaml
  system_specs:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    services:
      postgres:
        image: postgres:16
        ports: ["5432:5432"]
        env: { POSTGRES_PASSWORD: postgres }

    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - uses: actions/setup-node@v4
        with: { node-version: "20", cache: yarn }
      - run: yarn install --frozen-lockfile
      - run: bin/rails assets:precompile

      - name: Run system specs
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/myapp_test
          RAILS_ENV: test
        run: bin/rspec spec/system

      - name: Upload screenshots on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: system-screenshots
          path: tmp/screenshots
```

Cuprite + Chromium is in the Ubuntu runner by default. No Selenium driver setup needed.

## Pattern 4: Deploy via Kamal on push to main

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

permissions:
  id-token: write   # for OIDC if you use AWS / GCP
  contents: read

concurrency:
  group: production-deploy
  cancel-in-progress: false   # never cancel a deploy mid-flight

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    environment: production    # required-reviewer gate in GH UI

    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Set up SSH for Kamal
        uses: webfactory/ssh-agent@v0.9.0
        with:
          ssh-private-key: ${{ secrets.DEPLOY_SSH_KEY }}

      - name: Kamal deploy
        env:
          KAMAL_REGISTRY_PASSWORD: ${{ secrets.GITHUB_TOKEN }}
          RAILS_MASTER_KEY: ${{ secrets.RAILS_MASTER_KEY }}
        run: bundle exec kamal deploy
```

The `environment: production` gate lets you require manual approval before deploy from the Settings UI.

Wait for CI green via branch protection (set in repo Settings → Branches → main).

## Pattern 5: OIDC instead of static AWS keys

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789012:role/github-deploy
    aws-region: us-east-1
    # NO aws-access-key-id / aws-secret-access-key
```

Set up the IAM role with a trust policy referencing GitHub's OIDC:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": "repo:myorg/myrepo:ref:refs/heads/main" }
    }
  }]
}
```

No long-lived keys, no rotation, scoped to a specific repo + branch.

## Pattern 6: Database migrations safely

Run migrations as part of deploy, but with safeguards:

```yaml
- name: Run migrations
  run: bundle exec kamal app exec -- bin/rails db:migrate
```

For long migrations (see `safe-migrations`): run them BEFORE the deploy, not as part of it. Add a separate workflow:

```yaml
# .github/workflows/migrate.yml
name: Run migrations
on:
  workflow_dispatch:    # manual trigger
```

## Pattern 7: PR previews / review apps

For frontend changes, deploy a preview environment per PR (optional, expensive):

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  preview:
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: superfly/flyctl-actions/setup-flyctl@master
      - run: flyctl deploy --app myapp-pr-${{ github.event.number }}
```

Or use Render / Heroku Review Apps — they handle this natively.

## Pattern 8: Branch protection

In Settings → Branches → main:

- ✅ Require a pull request before merging
- ✅ Require approvals (1 minimum)
- ✅ Require status checks to pass: `test`, `lint`, `security_scan`
- ✅ Require branches to be up to date
- ✅ Require linear history (preferred)
- ✅ Include administrators (no escape hatch)
- ✅ Restrict who can push

## Pattern 9: Secret management

- App secrets: GitHub Secrets (Settings → Secrets → Actions).
- Org-wide secrets: Org Secrets.
- Environment-scoped (production only): Environment Secrets.
- Static tokens: avoid. Prefer OIDC + short-lived credentials.

NEVER commit secrets. Use `secret_scanning` (default for public repos, optional for private — enable it).

## Pattern 10: Test reliability

Flaky tests destroy CI value. Mitigations:

- `bin/rspec --order rand` to catch order dependencies.
- `--fail-fast` on PRs but not on main (you want full results on main).
- Retry flaky tests with `rspec-retry`, but log and triage them weekly:

```ruby
# spec/spec_helper.rb
require "rspec/retry"
RSpec.configure do |config|
  config.verbose_retry = true
  config.default_retry_count = ENV["CI"] ? 2 : 1
  config.exceptions_to_retry = [Net::ReadTimeout, Selenium::WebDriver::Error::WebDriverError]
end
```

The retry count is a stop-gap. Real fix: identify the flake, file an issue, fix it.

## Common mistakes to refuse

- Don't put `bundle install` without caching. CI gets 5x slower.
- Don't use static AWS keys. Use OIDC.
- Don't deploy from a forked PR. Restrict who can push to deploy branches.
- Don't skip `--frozen-lockfile`. CI must use the committed lockfile.
- Don't run lint + tests in the same job. Parallelize.
- Don't commit secrets. Even briefly. Even in test files.
- Don't `pull_request_target` carelessly. It gives the workflow access to repo secrets with the PR's code — RCE vector.

## See also

- `kamal-docker-production` — the deploy target
- `rspec-testing-pyramid` — what to run
- `rails-security-baseline` — Brakeman + bundle-audit
- `safe-migrations` — migration workflow during deploy
- `observability-baseline` — alert on CI failures via webhook

## Sources

- [GitHub Actions docs](https://docs.github.com/en/actions)
- [ruby/setup-ruby](https://github.com/ruby/setup-ruby)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials)
- [knapsack_pro](https://knapsackpro.com/)
- [Kamal docs](https://kamal-deploy.org/)
- [Branch protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
