---
name: multi-tenancy
description: Multi-tenant architecture in Rails 8 — scoped-row vs schema-per-tenant vs database-per-tenant trade-offs, the acts_as_tenant gem, subdomain / path / header-based tenant resolution, query scoping that survives raw SQL, background job tenancy, file storage isolation, signup flows, plan-based feature gating. Use when the user mentions multi-tenant, SaaS, account, organization, workspace, acts_as_tenant, apartment, subdomain, tenant isolation, tenant_id, "each customer gets their own data", or asks how to build a B2B SaaS in Rails.
---

# Multi-Tenancy in Rails

> Most B2B SaaS Rails apps need multi-tenancy. AI agents default to either too-loose (forgetting `tenant_id` filters) or too-aggressive (one database per tenant for an MVP). The right answer is almost always row-scoped tenancy with a defense-in-depth gem.

## The opinion

> **Default to row-scoped tenancy with a `tenant_id` (or `account_id` / `organization_id`) column on every tenant-owned table. Use `acts_as_tenant` for automatic scoping that fails closed when tenant isn't set. Resolve tenant by subdomain or path. Pass tenant to every background job. Per-schema and per-database tenancy exist but should be reserved for compliance / data-residency reasons (HIPAA, GDPR, single-tenant Enterprise plans).**

Why row-scoped:
- One database, one schema, one migration. Operationally simple.
- Easy cross-tenant analytics (one query, not 1000).
- Cost: query overhead per row vs separate table — negligible on a tenant_id index.

Counter-positions:
- **`apartment` gem (schema-per-tenant)** — strong isolation, but breaks Rails 6+ multi-DB, fragile under migrations. Largely unmaintained.
- **Database-per-tenant** — strongest isolation, hardest ops. Reserve for regulated industries or Enterprise tier.

## Pattern 1: acts_as_tenant setup

```ruby
# Gemfile
gem "acts_as_tenant"
```

```ruby
# config/initializers/acts_as_tenant.rb
ActsAsTenant.configure do |config|
  config.require_tenant = true  # raise if a tenant model is queried without a tenant set
end
```

`require_tenant = true` is the line that prevents the worst category of bugs: forgetting to scope and leaking another tenant's data.

```ruby
# app/models/account.rb
class Account < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :posts, dependent: :destroy
end

# app/models/post.rb
class Post < ApplicationRecord
  acts_as_tenant :account
  validates :title, presence: true
end
```

Migration:

```ruby
class AddAccountIdToPosts < ActiveRecord::Migration[8.0]
  def change
    add_reference :posts, :account, null: false, foreign_key: true, index: true
  end
end
```

Index on `account_id` is non-negotiable — every query filters by it.

## Pattern 2: Resolve the tenant per request

### By subdomain

```ruby
class ApplicationController < ActionController::Base
  before_action :set_tenant

  private

  def set_tenant
    subdomain = request.subdomains.first
    return redirect_to_marketing_site unless subdomain.present?

    @account = Account.find_by(subdomain: subdomain)
    return head :not_found unless @account

    ActsAsTenant.current_tenant = @account
  end

  def redirect_to_marketing_site
    redirect_to ENV.fetch("MARKETING_URL", "https://example.com")
  end
end
```

### By path

```ruby
# config/routes.rb
scope ":account_slug" do
  resources :posts
end
```

```ruby
class ApplicationController < ActionController::Base
  before_action :set_tenant

  def set_tenant
    @account = Account.find_by!(slug: params[:account_slug])
    ActsAsTenant.current_tenant = @account
  end
end
```

### By header (API)

```ruby
class Api::BaseController < ActionController::API
  before_action :set_tenant

  def set_tenant
    api_key = request.headers["Authorization"]&.delete_prefix("Bearer ")
    ApiToken.find_by(token: api_key)&.tap { |t| ActsAsTenant.current_tenant = t.account } or head :unauthorized
  end
end
```

## Pattern 3: Background job tenancy

Jobs run outside the request cycle — `ActsAsTenant.current_tenant` is nil. Pass tenant explicitly.

```ruby
class PublishPostJob < ApplicationJob
  queue_as :default

  def perform(account_id, post_id)
    ActsAsTenant.with_tenant(Account.find(account_id)) do
      post = Post.find(post_id)
      post.publish!
    end
  end
end

# Enqueue:
PublishPostJob.perform_later(post.account_id, post.id)
```

Always pass `account_id` as the first job argument and wrap perform in `ActsAsTenant.with_tenant`. The gem ships Sidekiq middleware that serializes the current tenant into the job payload (`ActsAsTenant::Sidekiq`), but explicit beats implicit — code reviewers can see tenancy in the job signature.

For admin / cross-tenant jobs (reconciliation, billing roll-ups) that legitimately must run without a tenant, wrap them in `ActsAsTenant.without_tenant { ... }` — otherwise `require_tenant = true` raises in the worker.

## Pattern 4: Tenant-scoped sessions / cookies

```ruby
# config/initializers/session_store.rb
Rails.application.config.session_store :cookie_store,
  key: "_app_session",
  domain: :all,         # share cookies across subdomains
  tld_length: 2         # tighten if using two-level TLDs
```

But: if you want per-tenant session isolation (recommended for security), namespace the cookie:

```ruby
class ApplicationController < ActionController::Base
  before_action :scope_session_to_tenant

  def scope_session_to_tenant
    request.session_options[:key] = "_app_session_#{@account.id}"
  end
end
```

## Pattern 5: Plan-based feature gating

```ruby
class Account < ApplicationRecord
  enum :plan, { free: 0, starter: 1, pro: 2, enterprise: 3 }

  def can?(feature)
    case feature
    when :advanced_reports then pro? || enterprise?
    when :sso              then enterprise?
    when :api_access       then starter? || pro? || enterprise?
    else false
    end
  end
end
```

```erb
<% if Current.account.can?(:advanced_reports) %>
  <%= link_to "Reports", reports_path %>
<% end %>
```

Combine with Pundit policies for enforcement, not just UI gating. See `devise-pundit-rodauth`.

## Pattern 6: File storage isolation

Active Storage blobs by default land in one bucket. For larger tenancies, prefix:

```ruby
class Post < ApplicationRecord
  has_one_attached :cover_image do |blob|
    blob.variant :thumb, resize_to_limit: [300, 300]
  end

  def cover_image_key
    "accounts/#{account_id}/posts/#{id}/cover"
  end
end
```

For compliance-level isolation (HIPAA / GDPR), use a separate bucket per tenant or per-tenant encryption keys via `ActiveRecord::Encryption` with rotating keys.

## Pattern 7: The "leaked tenant_id" bug

This is the #1 multi-tenant bug. AI agents often write:

```ruby
# BAD — anyone can read another account's post by guessing the ID
class PostsController < ApplicationController
  def show
    @post = Post.find(params[:id])
  end
end
```

With `acts_as_tenant + require_tenant = true`, this raises if `current_tenant` is unset. But when it IS set, the query becomes `Post.where(account_id: current).find(params[:id])` automatically — and raises `ActiveRecord::RecordNotFound` if the post belongs to another tenant.

**Always:**
- Test that a user from account A can't load resources from account B (returns 404).
- Add a request spec for cross-tenant access on every controller.

```ruby
# spec/requests/posts_spec.rb
it "returns 404 for cross-tenant access" do
  other_account_post = create(:post, account: other_account)
  sign_in user  # in my_account

  get post_path(other_account_post)

  expect(response).to have_http_status(:not_found)
end
```

## Pattern 8: Signups and onboarding

```ruby
class SignupsController < ApplicationController
  def create
    ActiveRecord::Base.transaction do
      @account = Account.create!(name: params[:company_name], subdomain: params[:subdomain])
      @user = User.create!(email: params[:email], password: params[:password], account: @account, role: :owner)
    end

    sign_in @user
    redirect_to root_url(subdomain: @account.subdomain)
  end
end
```

Form-object refactor when the signup creates 3+ records — see `form-objects-query-objects-presenters`.

## Pattern 9: Tenant-aware admin

```ruby
class Admin::AccountsController < AdminController
  def impersonate
    account = Account.find(params[:id])
    ActsAsTenant.current_tenant = account
    redirect_to root_url(subdomain: account.subdomain)
  end
end
```

Audit log every impersonation. Don't share admin and tenant cookies.

## Common mistakes to refuse

- Don't use `default_scope` for tenancy. Hard to unscope, surprises in raw SQL.
- Don't use the `apartment` gem in greenfield apps (unmaintained, breaks with Rails 6+ multi-DB).
- Don't forget background-job tenancy. Always pass `account_id` and wrap with `ActsAsTenant.with_tenant`.
- Don't write `Post.find(params[:id])` without tenant scoping in tenant-owned controllers.
- Don't share Redis / cache keys across tenants without namespacing — cache leakage is real.
- Don't reach for schema-per-tenant unless you have a regulatory reason. Operational pain is high.

## When NOT to use this skill

- Single-tenant apps (an internal tool, a one-customer Enterprise installation).
- Apps where every user sees the same data (a blog, a marketing site).

## See also

- `devise-pundit-rodauth` — auth + Pundit policies for per-account permissions
- `solid-queue-and-sidekiq` — passing tenant to jobs
- `rails-caching-strategy` — namespacing caches per tenant
- `rails-security-baseline` — cross-tenant authorization checks
- `safe-migrations` — adding tenant_id columns to existing tables

## Sources

- [acts_as_tenant gem](https://github.com/ErwinM/acts_as_tenant)
- [Multi-tenancy with PostgreSQL — Citus blog](https://www.citusdata.com/blog/2017/03/09/multi-tenant-sharding-tutorial/)
- [Apartment gem (mentioned for completeness)](https://github.com/influitive/apartment)
- [Rails Multi-DB](https://guides.rubyonrails.org/active_record_multiple_databases.html)
- [Pundit](https://github.com/varvet/pundit)
- [37signals / Basecamp tenancy patterns](https://signalvnoise.com/)
