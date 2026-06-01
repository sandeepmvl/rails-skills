---
name: feature-flagging
description: Feature flags in Ruby on Rails 8 — Flipper as the canonical gem, percentage-rollout and group-based flags, the per-request and per-user evaluation patterns, integration with admin UI and CI, deprecating flags safely, the "every feature behind a flag" anti-pattern. Use when the user mentions Flipper, feature flags, percentage rollout, A/B testing infrastructure, dark launch, gradual rollout, kill switch, or asks how to ship features safely.
---

# Feature Flagging

> Feature flags let you ship code without enabling features for users. Use them for gradual rollouts, kill switches, and A/B tests. AI agents either (a) skip them entirely, or (b) flag every line of code — both wrong.

## The opinion

> **Flipper for Rails feature flags. Flag launches (gradual rollouts, kill switches), not every line. Set a deprecation date when you add a flag — flags that live forever become technical debt. Read flags once per request via a wrapper that's mockable in tests. Admin UI for ops, but flag flips should ideally be in code (committed) for audit trail.**

Counter-positions:
- **LaunchDarkly / Statsig / GrowthBook** — managed services with deeper analytics. Pay-per-flag-evaluation gets expensive. Flipper covers 80% for small/medium apps.
- **rollout gem** — older, less actively maintained. Flipper won.
- **Conditional based on `Rails.env.production?`** — anti-pattern. That's not a flag, that's a fork.

## Core patterns

### Pattern 1: Flipper setup

```ruby
# Gemfile
gem "flipper"
gem "flipper-active_record"
gem "flipper-ui"  # admin UI (optional)

# bin/rails generate flipper:active_record
# bin/rails db:migrate
```

```ruby
# config/initializers/flipper.rb
require "flipper/middleware/memoizer"

Rails.application.config.middleware.use Flipper::Middleware::Memoizer

# Optional: register groups
Flipper.register(:admins) { |actor| actor.respond_to?(:admin?) && actor.admin? }
Flipper.register(:beta_users) { |actor| actor.respond_to?(:beta?) && actor.beta? }
```

```ruby
# config/routes.rb — mount admin UI
authenticate :user, ->(u) { u.admin? } do
  mount Flipper::UI.app(Flipper) => "/_flipper"
end
```

### Pattern 2: Reading flags

```ruby
# In a controller / view / model
if Flipper.enabled?(:new_dashboard, current_user)
  render :new_dashboard
else
  render :dashboard
end
```

`current_user` (or any actor with `flipper_id`) gets per-user flag state. Pass `nil` for global flags.

```ruby
# Model needs flipper_id
class User < ApplicationRecord
  def flipper_id
    "User;#{id}"
  end
end
```

### Pattern 3: Enabling — three rollout modes

```ruby
# Mode A — boolean (everyone)
Flipper.enable(:new_dashboard)

# Mode B — percentage of actors
Flipper.enable_percentage_of_actors(:new_dashboard, 25)
# 25% of actors based on hash of flipper_id — stable; same user always gets same answer

# Mode C — specific actor
Flipper.enable_actor(:new_dashboard, User.find(42))

# Mode D — group
Flipper.enable_group(:new_dashboard, :admins)
```

**Rollout strategy for a real launch:**

1. `enable_actor` for the team (you + product manager).
2. `enable_group(:beta_users)` (1-2 weeks of internal use).
3. `enable_percentage_of_actors(5)` for 24h. Watch metrics.
4. `enable_percentage_of_actors(25)`. Watch.
5. `enable_percentage_of_actors(100)` or full `enable`.
6. Set a calendar reminder: 2 weeks later, remove the flag and the old code path.

### Pattern 4: Kill switch

For features that depend on a flaky upstream:

```ruby
class HubspotSyncJob < ApplicationJob
  def perform(user_id)
    return unless Flipper.enabled?(:hubspot_sync)
    SyncToHubspot.new(User.find(user_id)).call
  end
end
```

When Hubspot goes down, flip the flag off. Jobs pile up but don't fail. Flip back on when the dependency recovers.

### Pattern 5: A/B test flag

```yaml
# Variant: A or B
variant = Flipper.enabled?(:new_checkout_design, current_user) ? :variant_b : :control

# Log the assignment for analytics
StatsD.increment("checkout.variant.#{variant}")

# Render the right variant
render @order, variant: variant
```

Same-user-same-variant guarantee comes from `enable_percentage_of_actors` (hashed on flipper_id).

For real A/B testing (statistical significance, lift calculation), pair Flipper with an analytics tool (Mixpanel, Amplitude) or move to a dedicated A/B platform (Statsig, GrowthBook).

### Pattern 6: Testing with flags

```ruby
# spec/support/flipper_helpers.rb
module FlipperHelpers
  def enable_flag(name, actor = nil)
    actor ? Flipper.enable_actor(name, actor) : Flipper.enable(name)
  end

  def disable_flag(name)
    Flipper.disable(name)
  end
end

RSpec.configure { |c| c.include FlipperHelpers }

# In a spec
it "shows the new dashboard when flag is on" do
  enable_flag(:new_dashboard, user)
  sign_in user
  get root_path
  expect(response.body).to include("New Dashboard")
end

it "shows the old dashboard otherwise" do
  disable_flag(:new_dashboard)
  sign_in user
  get root_path
  expect(response.body).to include("Old Dashboard")
end
```

Use a global default in `spec_helper.rb`:

```ruby
RSpec.configure do |config|
  config.before(:each) do
    Flipper.features.each { |f| Flipper.disable(f.name) }
  end
end
```

Every test starts with all flags off, so flags don't leak between tests.

### Pattern 7: Flag deprecation

```bash
# When the rollout is complete, remove the flag.
# Find usages:
grep -r "Flipper.enabled?(:new_dashboard" app/

# Remove each. Drop the old code path.

# Then drop the flag from Flipper:
Flipper.remove(:new_dashboard)
```

**Anti-pattern:** keeping flags around "just in case." Old flags = old code paths = forgotten branches = bugs.

**Process:** add a calendar reminder when adding a flag. 2-4 weeks after full rollout, remove.

### Pattern 8: Anti-patterns

```ruby
# WRONG — flag for what should be config
Flipper.enabled?(:smtp_host_postmark) ? "smtp.postmarkapp.com" : "smtp.sendgrid.net"
# This is config. Use ENV / credentials.

# WRONG — flag for what should be permissions / authz
Flipper.enabled?(:admin_can_delete_users, current_user)
# This is authorization. Use Pundit policy.

# WRONG — flag everywhere in one feature
if Flipper.enabled?(:new_checkout, current_user) && Flipper.enabled?(:new_checkout_pricing, current_user) && ...
# Flag the entry point, not each detail.

# WRONG — flag based on env (not a flag)
def new_feature?
  Rails.env.production? ? false : true
end
# Use environments for environment differences. Use flags for runtime toggles.
```

## Decision matrix

| Use case | Use |
|---|---|
| Gradual rollout of a new feature | Percentage of actors |
| Show feature to admins/internal users first | Group |
| Kill switch for a flaky integration | Boolean (on/off) |
| A/B test with simple analytics | Percentage of actors |
| A/B test with statistical lift calculation | Statsig / GrowthBook / LaunchDarkly |
| Environment-specific config | ENV / credentials, NOT flags |
| Permission/role | Pundit, NOT flags |

## Common mistakes to refuse

- Don't put authn/authz logic behind a flag.
- Don't flag environment config.
- Don't flag every line — flag entry points.
- Don't keep flags around forever.
- Don't toggle flags without an audit trail (use the UI's history or commit the change in code).
- Don't read the same flag 50 times per request (Flipper::Middleware::Memoizer covers this).

## When NOT to use this skill

- The user is doing a real A/B test with statistical analysis — defer to a managed A/B platform.
- The user is doing permissions — that's `devise-pundit-rodauth`.

## See also

- `devise-pundit-rodauth` — authorization, NOT feature flags
- `solid-queue-and-sidekiq` — kill switch on jobs
- `observability-baseline` — log flag assignments

## Sources

- [Flipper docs](https://www.flippercloud.io/docs)
- [Flipper Rails guide](https://github.com/flippercloud/flipper/blob/main/docs/Rails.md)
- [Flipper UI](https://github.com/flippercloud/flipper/tree/main/lib/flipper/ui)
- [GrowthBook (counter-position)](https://www.growthbook.io/)
- [Statsig (counter-position)](https://statsig.com/)
- [Martin Fowler — Feature Toggles](https://martinfowler.com/articles/feature-toggles.html) — taxonomy
- [LaunchDarkly (managed)](https://launchdarkly.com/)
