---
name: rails-upgrade-3-to-4
description: Upgrade a Ruby on Rails app from 3.x to 4.x — strong parameters replacing attr_accessible / attr_protected, the asset pipeline overhaul, the Turbolinks arrival, Ruby 2.0+ requirement, Bundler-style routes file, the version hop sequence. Use when upgrading legacy Rails 3 apps, the user mentions attr_accessible, Turbolinks, protected_attributes gem, asset pipeline, or asks how to escape Rails 3.
---

# Rails 3 → 4 Upgrade

> Legacy upgrade. Rails 3.2 is past EOL (Rails 3 LTS exists but is paid). The 3.2 → 4.0 hop is API-breaking; budget for a real project, not a weekend.

## The opinion

> **Dual-boot with `next_rails`. Hop 3.2 → 4.0 → 4.1 → 4.2. Ruby 2.0+ required for 4.0; Ruby 2.2.2+ for 4.2. Use the `protected_attributes` gem as a temporary bridge from `attr_accessible` to strong parameters.**

## The hop sequence

```
3.2 → 4.0 → 4.1 → 4.2
```

## Core patterns

### Pattern 1: 3.2 → 4.0

**Mandatory:**
- Ruby 2.0+.
- Switch from `attr_accessible` / `attr_protected` to strong parameters (or stay on `protected_attributes` gem as a bridge).
- New asset pipeline; old Sprockets behavior changed.
- Turbolinks ships (can disable if breaking the app).

**`attr_accessible` removal:**

```ruby
# Rails 3 model
class User < ActiveRecord::Base
  attr_accessible :name, :email
end

# Rails 4 — two paths

# Path A: use the `protected_attributes` gem (keeps old API; quick win for legacy)
gem "protected_attributes_continued"  # community-maintained for 4+

# Path B: migrate to strong parameters (the long-term path)
# Remove attr_accessible from model.
# In controllers:
def user_params
  params.require(:user).permit(:name, :email)
end
```

**Turbolinks:**

```javascript
# Gemfile
gem "turbolinks"

# JS that depends on $(document).ready needs to listen for "page:load" too
$(document).on('page:load ready', function() { ... })
```

Most Rails 3 apps with custom JS break under Turbolinks. Disable per-link with `data-no-turbolink` while you migrate.

### Pattern 2: 4.0 → 4.1

Spring (preloader) arrives. Configuration changes:
- `secrets.yml` replaces `config/initializers/secret_token.rb`.
- Mailer previews (Action Mailer Preview) ship.

### Pattern 3: 4.1 → 4.2

Active Job arrives — the abstraction over Sidekiq / DelayedJob / etc. Migrate background jobs:

```ruby
# Rails 4.1 (Sidekiq worker)
class HardWorker
  include Sidekiq::Worker
  def perform(name); end
end

# Rails 4.2 (Active Job)
class HardWorkerJob < ActiveJob::Base
  queue_as :default
  def perform(name); end
end
```

Adapter is configured globally; the same job class works with Sidekiq / DelayedJob / SQS / etc.

### Pattern 4: Gem audit

Rails 3 era gems often have no 4.x version. Audit:

```bash
bundle outdated
bundle update --major-version-only
# Compare each gem against its 4.x compat docs
```

Common replacements:
- `state_machine` → `aasm` or `state_machines-activerecord`.
- `paperclip` → Active Storage (or shrine).
- `cancan` → `cancancan` (community fork).
- `inherited_resources` → kept but mature; replace if you can.

## Common mistakes to refuse

- Don't ditch `attr_accessible` for strong_parameters in the same PR as the version bump. Use `protected_attributes_continued` first.
- Don't enable Turbolinks if your JS doesn't handle it.
- Don't skip 4.1 (Active Job arrives; migrating workers is easier here).

## See also

- `rails-upgrade-4-to-5` — next hop
- `solid-queue-and-sidekiq` — Active Job (introduced in 4.2)

## Sources

- [Rails 4.0 release notes](https://guides.rubyonrails.org/4_0_release_notes.html)
- [Rails 4.2 release notes](https://guides.rubyonrails.org/4_2_release_notes.html)
- [Strong Parameters intro](https://api.rubyonrails.org/classes/ActionController/StrongParameters.html)
- [protected_attributes_continued gem](https://github.com/westonganger/protected_attributes_continued)
- [Active Job basics](https://guides.rubyonrails.org/active_job_basics.html)
- [Rails LTS (legacy security backports)](https://railslts.com/)
