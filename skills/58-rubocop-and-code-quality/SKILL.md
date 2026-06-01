---
name: rubocop-and-code-quality
description: Code-quality tooling for Rails — RuboCop with rubocop-rails / rubocop-performance / rubocop-rspec / rubocop-thread_safety extensions, the rubocop-rails-omakase preset (DHH's defaults, shipped with Rails 8), SimpleCov coverage with branch coverage + CI threshold, erb_lint for ERB templates, RBS / Sorbet for optional type checking, Reek / RubyCritic for code smells, autocorrect strategy, when to disable a cop vs fix the code. Use when the user mentions RuboCop, .rubocop.yml, code style, linting, SimpleCov, coverage threshold, erb_lint, Sorbet, RBS, type checking, code smell, omakase, or asks how to set up code quality / static analysis for Rails.
---

# RuboCop + Code Quality

> AI agents generate Ruby code that RuboCop hates: unfrozen string literals, long methods, wrong constant style. Then they disable the cops instead of fixing the code. This skill sets up RuboCop the way Rails core does it (omakase preset + extensions), wires it into CI, and gives the autocorrect-first workflow.

## The opinion

> **Use `rubocop-rails-omakase` as the base preset — it ships with Rails 8 and reflects DHH's defaults. Layer `rubocop-rails`, `rubocop-performance`, `rubocop-rspec`, `rubocop-thread_safety` only when you need cops beyond omakase. Run `rubocop -a` (safe autocorrect) on every PR; `-A` (all autocorrect including unsafe) only in dedicated cleanup PRs. Gate CI on `rubocop --parallel`. Coverage via SimpleCov with branch coverage + 80% line threshold. erb_lint for ERB templates. RBS for type checking only on stable domains; skip Sorbet unless you have a strong reason.**

Counter-positions:
- **Standardrb / Standard** — single-config zero-bikeshed alternative. Smaller team consensus, but less Rails-aware than rubocop-rails-omakase. Pick one or the other, not both.
- **Sorbet** — Stripe-grade. Heavy ceremony. Worth it for very large codebases (50k+ LOC, 50+ engineers). Most Rails apps don't need it.

## Pattern 1: RuboCop setup (Rails 8 default)

Rails 8 generates `.rubocop.yml` referencing `rubocop-rails-omakase` automatically:

```ruby
# Gemfile (Rails 8 default — already present)
gem "rubocop-rails-omakase", require: false
```

```yaml
# .rubocop.yml (Rails 8 default)
inherit_gem:
  rubocop-rails-omakase: rubocop.yml
```

That's the whole baseline. omakase enables ~120 cops aligned with the Rails core team's style. Run:

```bash
bundle exec rubocop                 # report
bundle exec rubocop -a              # safe autocorrect
bundle exec rubocop -A              # unsafe autocorrect — review diff carefully
bundle exec rubocop --parallel      # CI mode
bundle exec rubocop -l              # lint cops only
```

## Pattern 2: Adding extensions

When you outgrow omakase:

```ruby
# Gemfile
group :development, :test do
  gem "rubocop-rails", require: false       # Rails-specific cops (find_each, bulk insert, etc.)
  gem "rubocop-performance", require: false # micro-perf cops (gsub→tr, freeze, etc.)
  gem "rubocop-rspec", require: false       # spec-file conventions
  gem "rubocop-thread_safety", require: false # global-state pitfalls (matters in Puma/Sidekiq)
end
```

```yaml
# .rubocop.yml
inherit_gem:
  rubocop-rails-omakase: rubocop.yml

require:
  - rubocop-rails
  - rubocop-performance
  - rubocop-rspec
  - rubocop-thread_safety

AllCops:
  TargetRubyVersion: 3.3
  TargetRailsVersion: 8.0
  NewCops: enable             # auto-pick up new cops; review their effect before bumping
  Exclude:
    - bin/**/*
    - db/schema.rb
    - db/migrate/*_create_*.rb     # generator output; don't bikeshed
    - vendor/**/*
    - node_modules/**/*
    - tmp/**/*
    - storage/**/*
```

**Rule of thumb:** `Exclude` only for code you don't write (generators, vendor). Never exclude `app/` paths to avoid fixing a lint.

## Pattern 3: When to disable a cop

There IS a time. The bar is high.

```ruby
# Bad — blanket disable hiding a real issue
class MassiveService  # rubocop:disable all
  ...
end

# Good — surgical, with reason
def process_legacy_csv(row)
  # rubocop:disable Metrics/MethodLength
  # Format is fixed by an external vendor; splitting helpers would obscure the schema.
  row[0]  = parse_date(row[0])
  row[1]  = parse_currency(row[1])
  # ... 40 more lines
  # rubocop:enable Metrics/MethodLength
end
```

Rules:
- Always specify the cop. Never `disable all` or `disable` bare.
- Always include a one-line reason in a comment.
- Wrap the smallest possible scope. Re-enable right after.
- If you disable the same cop in 5+ places: change the config instead.

## Pattern 4: Autocorrect workflow

```bash
# Daily workflow before pushing
bundle exec rubocop -a              # safe autocorrect; review diff
git add -p                          # stage the autocorrects you accept

# After a big merge or upgrade
bundle exec rubocop -A              # unsafe autocorrect; review CAREFULLY
bin/rspec                           # tests still green?
git commit -m "rubocop -A cleanup"  # dedicated commit
```

**Never run `-A` mid-feature.** It rewrites semantics-adjacent code (e.g., changes `each` to `each_with_object`) and reviewing a 200-file diff next to a feature change is impossible.

## Pattern 5: CI integration

```yaml
# .github/workflows/ci.yml — see skill 55
lint:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4
    - uses: ruby/setup-ruby@v1
      with: { bundler-cache: true }
    - run: bundle exec rubocop --parallel --format github
```

`--format github` emits annotations on PRs (line-level comments at the offending location).

```bash
# Pre-commit hook (optional, via Overcommit gem)
# Gemfile dev group
gem "overcommit"
```

```yaml
# .overcommit.yml
PreCommit:
  RuboCop:
    enabled: true
    command: ['bundle', 'exec', 'rubocop', '--force-exclusion']
    on_warn: fail
```

## Pattern 6: SimpleCov for coverage

```ruby
# Gemfile
gem "simplecov", require: false, group: :test
```

```ruby
# spec/spec_helper.rb (or test/test_helper.rb) — FIRST line, before any app code
require "simplecov"
SimpleCov.start "rails" do
  enable_coverage :branch                  # branch coverage in addition to line
  minimum_coverage line: 80, branch: 70    # CI fails if below threshold
  add_filter "/spec/"
  add_filter "/test/"
  add_filter "/db/migrate/"
  add_group "Services", "app/services"
  add_group "Jobs", "app/jobs"
end
```

`enable_coverage :branch` catches "every line ran, but only one branch was tested" — common when you have conditional logic with only the happy path covered.

```yaml
# CI artifact
- name: Upload coverage
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: coverage
    path: coverage/
```

Hook to Codecov / Coveralls for PR comments.

**Anti-pattern:** chasing 100% coverage. 80–90% is the sweet spot. Beyond that you're testing implementation, not behavior. See `rspec-testing-pyramid` for the pyramid logic.

## Pattern 7: erb_lint for templates

```ruby
# Gemfile
gem "erb_lint", require: false, group: :development
```

```yaml
# .erb-lint.yml
---
EnableDefaultLinters: true
linters:
  Rubocop:
    enabled: true                # runs rubocop on inline Ruby
  ErbSafety:
    enabled: true                # warns on <%= raw %> / .html_safe
  FinalNewline:
    enabled: true
  NoJavascriptTagHelper:
    enabled: true                # use <script> + CSP nonces, not javascript_tag
  AllowedScriptType:
    enabled: true
```

```bash
bundle exec erblint --lint-all
bundle exec erblint --lint-all --autocorrect
```

Catches `<%= user.bio.html_safe %>` (XSS) and other ERB-specific issues RuboCop misses.

## Pattern 8: Static analysis — Reek / RubyCritic (optional)

```ruby
# Gemfile
group :development do
  gem "reek", require: false
  gem "rubycritic", require: false
end
```

```bash
bundle exec reek app/                      # code-smell report
bundle exec rubycritic app/ --no-browser   # full quality dashboard at tmp/rubycritic/
```

Run quarterly on a code-quality day. Don't gate CI on them — they're heuristic, not deterministic.

## Pattern 9: Type checking — RBS (recommended over Sorbet)

For most Rails apps, type checking is overkill. When it earns its keep:
- Library code with a stable public API.
- A specific domain (billing, auth) where you want compile-time guarantees.

```ruby
# Gemfile
group :development do
  gem "rbs", require: false
  gem "steep", require: false   # type checker that consumes RBS
end
```

```rbs
# sig/app/models/order.rbs
class Order < ApplicationRecord
  attr_accessor total_cents: Integer
  attr_accessor status: String

  def total_dollars: () -> Float
  def place!: () -> Order
end
```

```bash
bundle exec steep check
```

**Why RBS over Sorbet:**
- RBS signatures live in a separate `sig/` tree — they don't pollute Ruby files.
- Sorbet requires `# typed: true` sigils in every file + `T.let` / `T.cast` annotations. High ceremony.
- RBS is the Ruby Core standard direction (Ruby 3+).
- Sorbet is faster but more invasive. Pick it if you're Stripe-scale.

## Pattern 10: Naming + style preferences not in omakase

omakase doesn't have an opinion on everything. Document yours in `.rubocop.yml`:

```yaml
# Examples — pick what matches your team's habits
Style/StringLiterals:
  EnforcedStyle: double_quotes   # omakase default; spell out if your team disagrees

Naming/MemoizedInstanceVariableName:
  EnforcedStyleForLeadingUnderscores: required   # if you prefix internal memoization

Layout/LineLength:
  Max: 120                       # omakase is 120; raise to 140 for view files if needed
  Exclude:
    - "**/*.rb"   # don't! the cop being on protects you from runaway lines
```

When new cops appear (after gem upgrade), `NewCops: enable` brings them in. Review the report next PR; either fix the code or explicitly disable with a reason.

## Common mistakes to refuse

- Don't disable a cop globally because it caught code you don't want to fix today. Disable per-scope with a reason, or fix the code.
- Don't add `rubocop:disable all` to large files. Surgical only.
- Don't run `rubocop -A` mid-feature. Dedicate a cleanup commit.
- Don't aim for 100% coverage. Chase behavior coverage, not line %.
- Don't skip erb_lint — ERB is where XSS gets generated.
- Don't add both RuboCop AND Standardrb. Pick one preset.
- Don't add Sorbet to a 1k-LOC app. RBS or nothing until you outgrow it.

## When NOT to use this skill

- The user is in a strict Standardrb shop. Standard handles ~80% of the same goals with zero config; use it instead of RuboCop.
- The user is mid-feature and asks "should I disable this cop?" Don't refactor mid-feature; queue a cleanup commit.

## See also

- `rspec-testing-pyramid` — coverage strategy, what to actually test
- `rails-security-baseline` — Brakeman + bundler-audit (security scanners, separate from style)
- `ci-cd-github-actions-rails` / `ci-cd-gitlab-rails` / `ci-cd-jenkins-rails` — wire these tools into CI
- `safe-migrations` — strong_migrations as a quality gate for DB changes

## Sources

- [rubocop-rails-omakase](https://github.com/rails/rubocop-rails-omakase) — Rails 8 default preset
- [RuboCop docs](https://docs.rubocop.org/)
- [rubocop-rails](https://github.com/rubocop/rubocop-rails)
- [rubocop-performance](https://github.com/rubocop/rubocop-performance)
- [rubocop-rspec](https://github.com/rubocop/rubocop-rspec)
- [rubocop-thread_safety](https://github.com/rubocop/rubocop-thread_safety)
- [SimpleCov](https://github.com/simplecov-ruby/simplecov)
- [erb_lint](https://github.com/Shopify/erb-lint)
- [RBS](https://github.com/ruby/rbs)
- [Steep](https://github.com/soutaro/steep)
- [Sorbet](https://sorbet.org/) — heavier alternative
- [Standard](https://github.com/standardrb/standard) — zero-config RuboCop alternative
- [Overcommit](https://github.com/sds/overcommit) — Git hook manager
