---
name: devise-pundit-rodauth
description: Authentication and authorization for Ruby on Rails — Devise + Pundit as the default monolith combo, Rodauth when Devise hits its limits (MFA, WebAuthn, advanced password policies), devise-jwt for API-only apps, Rails 8's built-in `bin/rails generate authentication` for simple cases, secure defaults checklist (confirmable, lockable, password complexity), Pundit policy structure, the scope pattern for index actions, common authorization smells. Use when adding sign-in / sign-up, the user mentions Devise, Pundit, Rodauth, JWT auth, authorization, policies, can-can, CanCanCan, role-based access, MFA, WebAuthn, or asks "how do I auth in Rails".
---

# Devise + Pundit + Rodauth

> Authentication = "who you are". Authorization = "what you can do". AI agents conflate them and reach for whatever gem name they saw most recently. This skill picks the right combo per use case and locks in the secure defaults.

## The opinion

> **Default monolith stack: Devise (authn) + Pundit (authz). When Devise hits its limits (MFA, WebAuthn, audit logging, account-level password policies, OAuth2 server), switch to Rodauth. For API-only apps, devise-jwt or rodauth-rails. For tiny apps, Rails 8's built-in `bin/rails generate authentication` is enough — skip Devise.**

Counter-positions:
- **CanCanCan** (ability-based DSL): popular historically. We default to Pundit — its plain-Ruby policy-per-model maps cleaner to OOP. CanCanCan's centralized Ability class becomes hard to read at scale.
- **Clearance** (thoughtbot): minimalist, no email confirmation. Fine for greenfield, but Devise's modules cover more out of the box.
- **Rolling your own auth**: don't. Auth is hard. Use a library.

## Decision matrix — pick the auth stack

| Use case | Stack |
|---|---|
| Rails 8 monolith, simple login/signup, you don't need confirmable | `bin/rails generate authentication` (built-in) + Pundit |
| Rails 7/8 monolith, standard features (confirm, recover, lockable, password complexity) | Devise + Pundit |
| Rails monolith with MFA, WebAuthn, audit logging, JWT API | Rodauth (`rodauth-rails`) |
| API-only Rails app | devise-jwt + Pundit, OR rodauth-rails JWT |
| Multi-tenant SaaS with per-account roles | Devise + Pundit (with namespaced policies) |
| Anything regulated (HIPAA, PCI, SOC 2) | Rodauth (max-security defaults) — see v0.3 compliance skills |

## Core patterns

### Pattern 1: Rails 8 built-in authentication (simplest)

For new apps that need *just* sign-in/sign-up:

```bash
bin/rails generate authentication
```

Generates a `User`, `Session`, `PasswordsController`, secure cookie-based sessions. Doesn't bring confirmable / recoverable. When you outgrow it, swap to Devise — the model migration is straightforward.

**Use when:** internal tools, MVPs, demos. Anything where you can do password reset by emailing support.

**Outgrow indicators:** you need email confirmation, "remember me", account lockout, sign in via OmniAuth (Google/GitHub), or password complexity rules.

### Pattern 2: Devise — secure defaults

```ruby
# Gemfile
gem "devise"

# bin/rails generate devise:install
# bin/rails generate devise User
# bin/rails db:migrate
```

**Lock these in from day one** (`config/initializers/devise.rb`):

```ruby
Devise.setup do |config|
  # === Password security ===
  config.password_length = 12..128                              # 12 minimum (current OWASP)
  config.stretches = Rails.env.test? ? 1 : 12                   # bcrypt cost — 12 is current sane default
  config.pepper = Rails.application.credentials.devise_pepper   # add to credentials, never check in

  # === Lockable (brute-force) ===
  config.lock_strategy = :failed_attempts
  config.maximum_attempts = 10
  config.unlock_strategy = :time
  config.unlock_in = 30.minutes

  # === Confirmable (email verification) ===
  config.allow_unconfirmed_access_for = 0.days  # require confirm before login
  config.reconfirmable = true                    # must reconfirm email changes

  # === Recoverable (password reset) ===
  config.reset_password_within = 1.hour          # reset link expires in 1 hour
  config.reset_password_keys = [:email]

  # === Timeoutable (idle session expiry) ===
  config.timeout_in = 30.minutes                 # only for browser sessions

  # === Rememberable ===
  config.expire_all_remember_me_on_sign_out = true
  config.remember_for = 2.weeks
end

class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable,
         :rememberable, :validatable, :confirmable, :lockable, :trackable,
         :timeoutable
end
```

**Why each setting:**
- `password_length: 12..128` — OWASP 2024 baseline. Don't impose a max-length below 64.
- `stretches: 12` — bcrypt work factor. 12 = ~250ms per hash on modern hardware; tuned annually.
- `pepper` — application-wide secret added to every password hash. Means a leaked DB alone can't crack passwords offline.
- `maximum_attempts: 10` — locks the account after 10 failed attempts.
- `confirmable + allow_unconfirmed_access_for: 0` — block login until email is verified. Prevents email-stealing signups.
- `reset_password_within: 1.hour` — short window reduces leak-window.

### Pattern 3: Devise — common gotchas

**Gotcha 1: Strong params for custom fields**

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up,        keys: %i[name company])
    devise_parameter_sanitizer.permit(:account_update, keys: %i[name company avatar])
  end
end
```

Without this, custom fields silently drop and the user wonders why "name" is always nil.

**Gotcha 2: After-sign-in redirect for multi-tenant**

```ruby
class ApplicationController < ActionController::Base
  def after_sign_in_path_for(user)
    user.default_workspace_path  # OR root_path, NOT something based on params (open redirect)
  end
end
```

Never trust `params[:redirect_to]` for post-login redirect without strict origin check.

**Gotcha 3: `reset_session` on sign-out**

Devise's default `sign_out` does this. But if you write a custom logout, never just `session[:user_id] = nil` — `reset_session` invalidates the entire session cookie. Half-cleared sessions leak data.

### Pattern 4: Rodauth — when Devise doesn't fit

```ruby
# Gemfile
gem "rodauth-rails"

# bin/rails generate rodauth:install
# bin/rails db:migrate
```

Rodauth is database-agnostic, configures via a DSL in `app/misc/rodauth_app.rb`:

```ruby
class RodauthApp < Rodauth::Rails::App
  configure do
    enable :create_account, :verify_account, :login, :logout, :reset_password,
           :change_password, :change_login, :remember,
           :otp, :recovery_codes, :webauthn,           # ← MFA
           :audit_logging, :password_complexity, :disallow_password_reuse

    password_minimum_length 12
    # Rodauth's password_complexity feature exposes individual setting methods, not a hash.
    # For stronger checks, prefer the `:disallow_common_passwords` feature or the `zxcvbn` gem.
    password_meets_requirements? { |pw| pw =~ /[A-Z]/ && pw =~ /\d/ && pw =~ /[^\w]/ }
    require_password_confirmation? true
    audit_logging_redact_request_params %w[password password_confirmation]

    # Email verification grace period
    verify_account_grace_period 7.days

    # Account-lockout settings
    lockout_after_failed_logins 10
    lockout_duration 30.minutes
  end
end
```

**Why Rodauth over Devise for these features:**
- WebAuthn / passkeys: Rodauth's `webauthn` feature is first-class; Devise needs `devise-passwordless` or `devise-otp` patches.
- Audit logging built in (logs login events with metadata).
- Password complexity / reuse prevention built in.
- DB-level password isolation: Postgres user/role separation for the password table (the password table is owned by a different DB role than the app).

**Migration from Devise:** painful but documented. Plan a 2-3 sprint migration. Convert one account at a time on next login (rehash with Rodauth's algorithm); old hashes are recognized for a sunset window.

### Pattern 5: Pundit — authorization basics

```ruby
# Gemfile
gem "pundit"
# bin/rails generate pundit:install
```

```ruby
# app/policies/application_policy.rb (generated)
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  class Scope
    attr_reader :user, :scope
    def initialize(user, scope); @user = user; @scope = scope; end
    def resolve; raise NoMethodError; end
  end
end

# app/policies/post_policy.rb
class PostPolicy < ApplicationPolicy
  def index?
    true  # signed-in users can list posts
  end

  def show?
    record.published? || owner?
  end

  def create?
    user.present?
  end

  def update?
    owner? || user.admin?
  end

  def destroy?
    user.admin?
  end

  class Scope < Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(published: true).or(scope.where(author_id: user.id))
      end
    end
  end

  private

  def owner?
    user.present? && record.author_id == user.id
  end
end
```

**In the controller:**

```ruby
class PostsController < ApplicationController
  before_action :authenticate_user!

  def index
    @posts = policy_scope(Post).order(created_at: :desc)
  end

  def show
    @post = Post.find(params[:id])
    authorize @post  # raises Pundit::NotAuthorizedError if show? returns false
  end

  def update
    @post = Post.find(params[:id])
    authorize @post
    @post.update(post_params) ? redirect_to(@post) : render(:edit)
  end
end

class ApplicationController < ActionController::Base
  include Pundit::Authorization
  rescue_from Pundit::NotAuthorizedError, with: :forbidden

  # Force every action to call authorize / policy_scope or fail
  after_action :verify_authorized,    except: %i[index], unless: :devise_controller?
  after_action :verify_policy_scoped, only:   %i[index], unless: :devise_controller?

  private

  def forbidden
    redirect_to root_path, alert: "Not authorized."
  end
end
```

**The two `verify_*` after_actions are the key insight.** They make forgetting `authorize` a development-time error, not a security hole that ships.

### Pattern 6: Pundit — the scope pattern for `index`

```ruby
# WRONG — leaks unauthorized records
def index
  @posts = Post.all  # admin sees everything; user sees everything they shouldn't
end

# RIGHT
def index
  @posts = policy_scope(Post)  # filtered by user's permissions
end
```

The `Scope.resolve` method is where authorization on collections lives. Without it, index actions are the most common Rails authorization bug.

### Pattern 7: Pundit — namespaced policies

For admin vs regular access on the same model:

```ruby
# app/policies/admin/post_policy.rb
class Admin::PostPolicy < ApplicationPolicy
  def index?;   user.admin?; end
  def destroy?; user.admin?; end
  class Scope < Scope
    def resolve; scope.all; end  # admin sees everything
  end
end

# app/controllers/admin/posts_controller.rb
class Admin::PostsController < AdminController
  def index
    @posts = policy_scope([:admin, Post])
  end

  def destroy
    @post = Post.find(params[:id])
    authorize [:admin, @post]
    @post.destroy
  end
end
```

Same model, different policy per namespace. Cleaner than overloading one policy with admin branches.

### Pattern 8: API auth — devise-jwt

```ruby
# Gemfile
gem "devise"
gem "devise-jwt"

class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Denylist
  devise :database_authenticatable, :registerable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: self
end
```

```ruby
# config/initializers/devise.rb — required for devise-jwt to boot
Devise.setup do |config|
  config.jwt do |jwt|
    jwt.secret = Rails.application.credentials.devise_jwt_secret_key  # MUST be set
    jwt.expiration_time = 15.minutes.to_i                              # integer seconds
    jwt.dispatch_requests = [["POST", %r{^/login$}]]
    jwt.revocation_requests = [["DELETE", %r{^/logout$}]]
  end
end
```

```ruby
# Migration for the Denylist strategy
create_table :jwt_denylist do |t|
  t.string :jti, null: false
  t.datetime :exp, null: false
end
add_index :jwt_denylist, :jti
```

**Why short JWTs + Denylist:**
- `expiration_time: 15.minutes` — leaked JWT is valid for 15 min, not 30 days.
- Denylist strategy: server can revoke a token before its natural expiry (logout, password change, account lockout).

**Refresh tokens:** devise-jwt doesn't ship refresh tokens. Build them yourself (long-lived `refresh_token` column on User, rotates on every use), or pick rodauth-rails which has the pattern built in.

### Pattern 9: Testing auth and authz

```ruby
# spec/policies/post_policy_spec.rb
RSpec.describe PostPolicy do
  subject { described_class }

  let(:admin)  { build_stubbed(:user, :admin) }
  let(:author) { build_stubbed(:user) }
  let(:user)   { build_stubbed(:user) }
  let(:post)   { build_stubbed(:post, author: author, published: false) }

  permissions :show? do
    it "allows the author" do
      expect(subject).to permit(author, post)
    end
    it "denies non-author when unpublished" do
      expect(subject).not_to permit(user, post)
    end
    it "allows everyone when published" do
      published = build_stubbed(:post, published: true)
      expect(subject).to permit(user, published)
    end
  end

  describe "Scope" do
    let!(:published_post) { create(:post, published: true) }
    let!(:draft_post)     { create(:post, published: false, author: author) }

    it "returns published + own drafts to non-admin" do
      expect(Pundit.policy_scope(user, Post)).to match_array([published_post])
    end
    it "returns everything to admin" do
      expect(Pundit.policy_scope(admin, Post)).to include(published_post, draft_post)
    end
  end
end
```

## Common mistakes to refuse

- Don't store passwords in plaintext or with weak hashing (MD5, SHA1). Use bcrypt via Devise / Rodauth.
- Don't set `password_length` minimum below 12.
- Don't skip confirmable on a public-signup site (email-stealing signups).
- Don't use `Post.all` in an index action — use `policy_scope`.
- Don't forget `verify_authorized` / `verify_policy_scoped` after_actions — they catch missing auth checks.
- Don't put authorization logic in the model — it grows tangled. Use policies.
- Don't use long-lived JWTs (>30 min). Short + refresh.
- Don't trust `params[:redirect_to]` post-login without origin check (open redirect).
- Don't write your own auth. Use a library.

## When NOT to use this skill

- The user is asking about session security at the Rack level — that's `rails-security-baseline`.
- The user is asking about OAuth flows specifically — touch lightly here, full coverage is out of scope for v0.1.

## See also

- `rails-security-baseline` — CSRF, secure cookies, JWT payloads, secrets
- `rails-api-design` — auth headers, login rate limiting
- Coming in v0.3: `hipaa-rails`, `pci-dss-rails`, `soc2-rails` — compliance-grade auth requirements

## Sources

- [Devise README](https://github.com/heartcombo/devise)
- [Rodauth docs](https://rodauth.jeremyevans.net/) + [rodauth-rails](https://github.com/janko/rodauth-rails)
- [Pundit README](https://github.com/varvet/pundit)
- [devise-jwt README](https://github.com/waiting-for-dev/devise-jwt)
- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [Rails 8 authentication generator](https://guides.rubyonrails.org/security.html#authentication)
- [thoughtbot — Clearance](https://github.com/thoughtbot/clearance) (counter-position)
- [CanCanCan](https://github.com/CanCanCommunity/cancancan) (counter-position)
- [WebAuthn Guide](https://webauthn.guide/) — for Rodauth MFA features
