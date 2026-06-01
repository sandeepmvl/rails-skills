---
name: form-objects-query-objects-presenters
description: Architectural patterns beyond fat models — form objects for multi-model form binding, query objects for complex AR querying, presenters / decorators for view logic. When each earns its keep, naming, testing, common smells. Use when models bloat, forms span multiple models, queries get hard to read, views accumulate helpers, or the user mentions Reform, ActiveModel::Model, decorators, Draper, presenters, query objects.
---

# Form Objects, Query Objects, Presenters

> Three patterns for code that doesn't fit on the model and doesn't justify a service object. AI agents either over-extract (every form is a form object) or under-extract (1000-line model has its own form binding inline). This skill maps each pattern to the right trigger.

## The opinion

> **Form objects when a single form spans multiple models or has non-AR validations. Query objects when a query is 10+ lines or reused across actions. Presenters / decorators when view helpers grow procedural and need state. None of these for simple cases — keep the logic on the model or in the controller.**

## Decision matrix

| Problem | Pattern |
|---|---|
| Form posts to one model, no extra logic | Plain model (no extraction) |
| Form spans 2+ models (signup creates User + Account + Subscription) | **Form object** |
| Form has fields that aren't model attributes (terms of service checkbox) | **Form object** |
| Same complex query reused in 3+ controllers | **Query object** |
| Query is 15+ lines of scopes / joins / where chained together | **Query object** |
| View has 50 lines of "if this then that" formatting per record | **Presenter / decorator** |
| View calls `.formatted_name` and `.display_status` on every model | **Presenter** (or model methods, if simple) |
| Pure data transformation (Date → string) | **View helper** (not a pattern, just a helper) |

## Core patterns

### Pattern 1: Form objects

**The case:** signup creates a User + Account + Subscription.

```ruby
# app/forms/signup_form.rb
class SignupForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email, :string
  attribute :password, :string
  attribute :password_confirmation, :string
  attribute :company_name, :string
  attribute :plan_id, :string
  attribute :terms_accepted, :boolean

  validates :email, :password, :company_name, :plan_id, presence: true
  validates :password, length: { minimum: 12 }
  validate :password_matches
  validate :terms_must_be_accepted

  attr_reader :user

  def save
    return false unless valid?
    ActiveRecord::Base.transaction do
      account = Account.create!(name: company_name)
      @user = User.create!(email: email, password: password, account: account)
      account.subscriptions.create!(plan: Plan.find(plan_id))
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    false
  end

  private

  def password_matches
    errors.add(:password_confirmation, "doesn't match") unless password == password_confirmation
  end

  def terms_must_be_accepted
    errors.add(:terms_accepted, "must be accepted") unless terms_accepted
  end
end
```

```ruby
# Controller
def new
  @form = SignupForm.new
end

def create
  @form = SignupForm.new(signup_form_params)
  if @form.save
    sign_in @form.user
    redirect_to dashboard_path
  else
    render :new, status: :unprocessable_entity
  end
end
```

**Why this beats inline controller logic:**
- Errors are first-class via ActiveModel — render in views with the same helpers as model errors.
- The form has its own validation logic separate from model validations.
- Test the form object in isolation.

**Don't reach for Reform/Trailblazer** unless your team has chosen it. Plain `ActiveModel::Model` covers most cases.

### Pattern 2: Query objects

**The case:** filtered + sorted + paginated user search.

```ruby
# app/queries/user_search.rb
class UserSearch
  attr_reader :scope

  def initialize(scope = User.all)
    @scope = scope
  end

  def call(params)
    @scope = filter_by_status(@scope, params[:status])
    @scope = filter_by_role(@scope, params[:role])
    @scope = filter_by_search(@scope, params[:q])
    @scope = sort(@scope, params[:sort])
    @scope
  end

  private

  def filter_by_status(scope, status)
    return scope if status.blank?
    scope.where(status: status)
  end

  def filter_by_role(scope, role)
    return scope if role.blank?
    scope.where(role: role)
  end

  def filter_by_search(scope, q)
    return scope if q.blank?
    scope.where("name ILIKE :q OR email ILIKE :q", q: "%#{q}%")
  end

  def sort(scope, sort_key)
    allowed = %w[name email created_at]
    column = allowed.include?(sort_key) ? sort_key : "created_at"
    scope.order(column => :desc)
  end
end
```

```ruby
# Controller
def index
  users = UserSearch.new(policy_scope(User)).call(params)
  @pagy, @users = pagy(users)
end
```

**Why this beats inline:**
- Reusable in multiple controllers / contexts.
- Testable per-filter.
- Composes with Pundit's `policy_scope`.

**Anti-pattern:** a `User.search(params)` class method that does all of this. Class methods don't compose well, and they're harder to test in isolation.

### Pattern 3: Presenters / decorators

**The case:** a User has display rules (badge based on role, formatted last-login, masked phone).

```ruby
# app/presenters/user_presenter.rb
class UserPresenter
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def badge_class
    case user.role
    when "admin"   then "badge-red"
    when "manager" then "badge-blue"
    else "badge-gray"
    end
  end

  def formatted_last_login
    return "Never" if user.last_login_at.nil?
    if user.last_login_at > 1.hour.ago
      "Just now"
    elsif user.last_login_at > 24.hours.ago
      "#{((Time.current - user.last_login_at) / 3600).to_i}h ago"
    else
      user.last_login_at.strftime("%b %-d, %Y")
    end
  end

  def masked_phone
    return nil if user.phone.blank?
    "***-***-#{user.phone.last(4)}"
  end
end
```

```erb
<% presenter = UserPresenter.new(@user) %>
<span class="<%= presenter.badge_class %>"><%= @user.role.humanize %></span>
<span><%= presenter.formatted_last_login %></span>
```

**Method missing forwarding** for simple cases:

```ruby
class UserPresenter < SimpleDelegator
  def initialize(user, view_context)
    @view = view_context
    super(user)
  end

  def badge_class; ...; end
  def formatted_last_login; @view.time_ago_in_words(last_login_at); end
end
```

`SimpleDelegator` forwards unknown methods to the underlying user. Lets you call `presenter.email` directly.

**When Draper gem is justified:** large app, every model has a decorator, want auto-decoration via `decorate`. For small/medium apps, plain Ruby classes are simpler.

## Common mistakes to refuse

- Don't reach for form objects for single-model CRUD. Plain model is fine.
- Don't reach for query objects for one-line scopes. Use scopes (see `activerecord-patterns`).
- Don't reach for presenters for one-method formatting. Use a view helper.
- Don't bundle these into a single "FormQuery" mega-class.
- Don't extract patterns to "look professional." Extract when the model is groaning.

## When NOT to use this skill

- The user is in a service-object discussion — that's `service-objects-vs-fat-models`.
- The user is asking about ViewComponent — different pattern (component-based view rendering).

## See also

- `service-objects-vs-fat-models` — different trigger criteria
- `activerecord-patterns` — scopes, fat models, concerns
- `rspec-testing-pyramid` — testing each pattern

## Sources

- [ActiveModel::Model docs](https://api.rubyonrails.org/classes/ActiveModel/Model.html)
- [Reform gem (counter-position)](https://trailblazer.to/2.1/docs/reform/) — heavier form objects
- [Draper gem](https://github.com/drapergems/draper) — decorators
- [Code Climate — 7 Patterns for Refactoring Fat Models](https://thoughtbot.com/blog/refactor-models) (original Bryan Helmkamp post)
- [Sandi Metz — Practical Object-Oriented Design](https://sandimetz.com/)
- [thoughtbot — Decorators in Rails](https://thoughtbot.com/blog)
