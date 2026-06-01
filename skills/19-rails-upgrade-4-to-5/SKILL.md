---
name: rails-upgrade-4-to-5
description: Upgrade a Ruby on Rails app from 4.x to 5.x — dual-boot via next_rails, ApplicationRecord introduction, ActionCable arrival, strong parameters becoming mandatory, params no longer hash-like, the version hop sequence, the Rails 5.1 system tests and `yarn` arrival, the Rails 5.2 ActiveStorage + credentials. Use when upgrading from Rails 4 to 5, the user mentions ApplicationRecord, strong parameters, params.permit, ActionCable, the params HashWithIndifferentAccess change, or asks how to leave Rails 4.
---

# Rails 4 → 5 Upgrade

> Rails 4.2 → 5.0 is one of the biggest API breaks in the past decade. `params` stop being a Hash. Strong parameters become mandatory. ApplicationRecord arrives. Treat as a multi-month project for a non-trivial app.

## The opinion

> **Dual-boot with `next_rails`. Hop 4.2 → 5.0 → 5.1 → 5.2. Ruby 2.2.2+ for Rails 5.0; Ruby 2.5+ for 5.2. Budget weeks-to-months for a non-trivial app.**

## The hop sequence

```
4.2 → 5.0 → 5.1 → 5.2
```

## Core patterns

### Pattern 1: 4.2 → 5.0 — the breaking changes

**Required code changes:**

```ruby
# Rails 4 — base model inheriting from ActiveRecord::Base
class User < ActiveRecord::Base
end

# Rails 5 — inherit from ApplicationRecord
class User < ApplicationRecord
end

# Generate the new base class
bin/rails generate application_record
```

**`params` change — biggest gotcha:**

```ruby
# Rails 4 — params was a HashWithIndifferentAccess
params[:user][:email]                 # worked
params.permit(:foo, :bar)             # explicit but not required
User.create(params[:user])            # silently allowed any column

# Rails 5 — params is ActionController::Parameters
params[:user][:email]                 # works (subclass of Hash)
params.merge(...)                     # returns Parameters, not Hash
User.create(params[:user])            # raises ForbiddenAttributesError — must permit
```

Audit every `Model.create(params[:foo])` / `update(params[:foo])` call. Add `permit`.

**Other 5.0 changes:**
- ActionCable arrives (no impact unless you use it).
- `belongs_to` is required by default (`optional: true` to opt out).
- Test framework default switches; `Rails.test` may need `--clean` runs.
- `head :ok` after a `respond_to` block is no longer needed (slight behavior change).

### Pattern 2: 5.0 → 5.1

- yarn arrives for managing JS packages.
- System tests (Capybara wrapper) ship.
- `form_for` / `form_tag` start to be deprecated in favor of `form_with`.
- `secrets.yml` partially deprecated (full deprecation in 5.2).

### Pattern 3: 5.1 → 5.2

- Active Storage ships (file uploads).
- Encrypted credentials (`config/credentials.yml.enc`) replace `secrets.yml`.
- `Date.current` recommended over `Date.today` for time-zone safety.

```bash
# Migrate secrets.yml → credentials
EDITOR=vim bin/rails credentials:edit
# Paste secrets.yml contents into the encrypted file
```

### Pattern 4: `belongs_to` required

```ruby
# Rails 4 — nil author was allowed silently
class Post < ApplicationRecord
  belongs_to :author
end

# Rails 5 — validation fires on save if author is nil
# Either fix the data or opt out:
belongs_to :author, optional: true
```

Audit every `belongs_to` for `optional: true` cases.

## Common mistakes to refuse

- Don't skip 5.0 (the Parameters change has to land cleanly).
- Don't allow `Model.create(params[:foo])` in 5.0+; permit everything.
- Don't migrate ActionCable + ApplicationRecord + secrets.yml in the same PR.

## See also

- `rails-upgrade-3-to-4` — previous hop
- `rails-upgrade-5-to-6` — next hop

## Sources

- [Rails 5.0 release notes](https://guides.rubyonrails.org/5_0_release_notes.html)
- [Rails 5.2 release notes](https://guides.rubyonrails.org/5_2_release_notes.html)
- [Strong Parameters](https://api.rubyonrails.org/classes/ActionController/StrongParameters.html)
- [Encrypted credentials guide](https://guides.rubyonrails.org/security.html#custom-credentials)
- [FastRuby — Rails 5 upgrade walkthrough](https://www.fastruby.io/blog)
