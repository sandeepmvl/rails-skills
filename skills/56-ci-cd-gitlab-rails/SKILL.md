---
name: ci-cd-gitlab-rails
description: GitLab CI/CD for Rails 8 — .gitlab-ci.yml structure, RSpec + lint + security parallel stages, cache strategy (bundler, yarn, assets), services keyword for Postgres + Redis, Auto DevOps caveats, deploy via Kamal or AutoDevOps, OIDC for cloud credentials, environments + protected branches. Use when the user mentions GitLab CI, .gitlab-ci.yml, runners, Auto DevOps, GitLab Runner, or is on GitLab and asks how to set up CI for a Rails app.
---

# GitLab CI for Rails

> The same principles as GitHub Actions, different YAML. If you're on GitLab, use the platform's native CI rather than mixing in Jenkins / GitHub Actions. Auto DevOps is tempting but opinionated — overrides are common.

## The opinion

> **One `.gitlab-ci.yml` per repo, stages in order (build → test → security → deploy). Use `cache` for gems / yarn. Use `services` for Postgres + Redis. Use `parallel: N` for RSpec sharding. Deploy via Kamal in a `deploy` stage gated on protected `main` branch + manual approval for production. Use OIDC (GitLab CI ID Token) for cloud auth — never static keys in CI variables.**

## Pattern 1: Top-level structure

```yaml
# .gitlab-ci.yml
default:
  image: ruby:3.3
  before_script:
    - apt-get update -qq && apt-get install -y nodejs yarn
  cache:
    key:
      files: [Gemfile.lock, yarn.lock]
    paths:
      - vendor/bundle
      - node_modules

stages:
  - build
  - test
  - security
  - deploy

variables:
  POSTGRES_HOST_AUTH_METHOD: trust
  DATABASE_URL: postgres://postgres@postgres:5432/myapp_test
  REDIS_URL: redis://redis:6379/1
  BUNDLE_PATH: vendor/bundle
  RAILS_ENV: test
```

`cache.key.files` hashes the lockfiles → cache hit only when deps actually match.

## Pattern 2: Test stage

```yaml
test:
  stage: test
  parallel: 4    # GitLab runs 4 parallel jobs
  services:
    - postgres:16
    - redis:7
  script:
    - bundle install --jobs 4
    - bin/rails db:prepare
    - bundle exec rspec --tag ~slow

  artifacts:
    when: always
    paths:
      - tmp/screenshots/
      - coverage/
    reports:
      junit: tmp/rspec-junit.xml
```

`parallel: 4` sets `$CI_NODE_TOTAL=4` and `$CI_NODE_INDEX=1..4` for sharding. Pair with `knapsack_pro` or `flatware`.

`artifacts.reports.junit` populates GitLab's MR test report UI.

## Pattern 3: Linting + security in parallel

```yaml
rubocop:
  stage: test
  script:
    - bundle install --jobs 4
    - bundle exec rubocop --parallel

brakeman:
  stage: security
  script:
    - bundle install --jobs 4
    - bundle exec brakeman -q --no-pager --no-progress --color
  allow_failure: false

bundle_audit:
  stage: security
  script:
    - bundle install --jobs 4
    - bundle exec bundle-audit check --update
  allow_failure: false

sast:
  stage: security
  include:
    - template: Security/SAST.gitlab-ci.yml
```

GitLab ships built-in SAST templates. The Ruby analyzer is Brakeman under the hood — the template handles the orchestration.

## Pattern 4: System specs

```yaml
system_specs:
  stage: test
  image: ruby:3.3
  services:
    - postgres:16
    - redis:7
  before_script:
    - apt-get update && apt-get install -y nodejs yarn chromium
    - yarn install --frozen-lockfile
    - bundle install --jobs 4
    - bin/rails assets:precompile
    - bin/rails db:prepare
  script:
    - bundle exec rspec spec/system
  artifacts:
    when: on_failure
    paths: [tmp/screenshots/]
```

For Cuprite to find Chromium: `ENV["CUPRITE_BROWSER_PATH"] = "/usr/bin/chromium"` in your spec setup.

## Pattern 5: Deploy stage

```yaml
deploy_production:
  stage: deploy
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
      when: manual          # human approval before deploying production
  environment:
    name: production
    url: https://myapp.example.com

  before_script:
    - apt-get update && apt-get install -y openssh-client
    - eval $(ssh-agent -s)
    - echo "$DEPLOY_SSH_KEY" | tr -d '\r' | ssh-add -
    - mkdir -p ~/.ssh && chmod 700 ~/.ssh
    - echo "$DEPLOY_KNOWN_HOSTS" >> ~/.ssh/known_hosts

  script:
    - bundle install --jobs 4
    - bundle exec kamal deploy
```

`environment` enables the Operations → Environments UI with deploy history, lock, rollback.

`when: manual` — must click "Play" in GitLab UI to trigger production deploy. For staging, omit `when` so it deploys automatically on merge.

## Pattern 6: OIDC (GitLab ID Token)

```yaml
deploy_aws:
  stage: deploy
  id_tokens:
    AWS_ID_TOKEN:
      aud: https://gitlab.com
  script:
    - export AWS_ROLE_ARN=arn:aws:iam::123456789012:role/gitlab-deploy
    - export AWS_WEB_IDENTITY_TOKEN_FILE=$(mktemp)
    - echo "$AWS_ID_TOKEN" > "$AWS_WEB_IDENTITY_TOKEN_FILE"
    - aws sts get-caller-identity
```

IAM trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::123456789012:oidc-provider/gitlab.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "gitlab.com:aud": "https://gitlab.com" },
      "StringLike":   { "gitlab.com:sub": "project_path:mygroup/myrepo:ref_type:branch:ref:main" }
    }
  }]
}
```

No long-lived AWS keys in CI/CD Variables.

## Pattern 7: Variables and secrets

CI/CD Settings → Variables:

- **Protected** — only available to jobs running on protected branches/tags.
- **Masked** — hidden in job logs (must be a single token, no quotes / spaces).
- **Expanded** — interpolate `$OTHER_VAR` in the value.
- **Environment scope** — variable applies only to specific environment(s).

`RAILS_MASTER_KEY` → protected + masked + environment=production.

## Pattern 8: Cache strategy

Three cache patterns:

```yaml
# Per-branch cache — fastest, may diverge across branches
cache:
  key: "$CI_COMMIT_REF_SLUG"
  paths: [vendor/bundle]

# Per-lockfile cache — most predictable
cache:
  key:
    files: [Gemfile.lock]
  paths: [vendor/bundle]

# Pull-only for downstream jobs to avoid races
cache:
  policy: pull
```

For Rails: `files: [Gemfile.lock, yarn.lock]` is the sweet spot.

## Pattern 9: Merge request pipelines vs branch pipelines

```yaml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == "main"
    - when: never
```

This runs pipelines on MRs and on the protected main, NOT on every random branch push. Saves runner minutes.

## Pattern 10: Auto DevOps — when to use, when to skip

Auto DevOps is GitLab's opinionated default pipeline (auto-build, auto-test, auto-deploy to k8s via Helm).

**When it fits:**
- You're already on GitLab + Kubernetes.
- You use GitLab's container registry.
- You're OK with Helm + Auto DevOps' opinions.

**When to skip:**
- You deploy via Kamal (you do, per `kamal-docker-production`).
- You have specific test or build steps.
- You need control over migrations / asset compilation.

Most Rails teams disable Auto DevOps and write `.gitlab-ci.yml` explicitly. The visibility outweighs the convenience.

## Pattern 11: Branch protection

Settings → Repository → Protected branches:
- **main** — push/merge limited to Maintainers, code owner approval required.
- **production** — push limited to nobody (deploys only).

Settings → Merge requests:
- Merge if pipeline succeeds.
- Resolve all threads.
- Code owner approval required.

## Common mistakes to refuse

- Don't put deploy logic in `before_script`. It runs for every job. Put deploy in a stage.
- Don't use unprotected CI variables for production secrets.
- Don't skip cache. CI gets 10x slower.
- Don't run on every branch push. Use `workflow.rules` to limit to MR + main.
- Don't deploy from `feature/*` branches. Protected branches only.
- Don't keep an Auto DevOps pipeline AND a custom `.gitlab-ci.yml` — they fight.

## See also

- `ci-cd-github-actions-rails` — same patterns, GHA flavor
- `kamal-docker-production` — deploy target
- `rspec-testing-pyramid` — what to test
- `rails-security-baseline` — Brakeman + bundle-audit
- `safe-migrations` — migration timing in deploy

## Sources

- [GitLab CI/CD docs](https://docs.gitlab.com/ee/ci/)
- [.gitlab-ci.yml reference](https://docs.gitlab.com/ee/ci/yaml/)
- [GitLab JWT / OIDC](https://docs.gitlab.com/ee/ci/cloud_services/aws/)
- [Auto DevOps](https://docs.gitlab.com/ee/topics/autodevops/)
- [GitLab SAST templates](https://docs.gitlab.com/ee/user/application_security/sast/)
- [Knapsack Pro on GitLab](https://docs.knapsackpro.com/ci/gitlab/)
