---
name: service-objects-vs-fat-models
description: Decide when Rails logic stays in the model and when it earns a service object. Use when the user asks about service objects, fat models, "where does this logic go", refactoring a controller, extracting business logic, the Result pattern, interactor gem, dry-monads, command objects, or is about to write a class ending in Service / Manager / Handler / Processor. Also use proactively when reviewing any controller action with more than ~10 lines of business logic, or any model file exceeding ~200 lines.
---

# Service Objects vs Fat Models

> Rails has one of the longest-running community debates over where business logic should live. AI agents reach for service objects on every controller action — over-extracting. Senior Rails devs keep logic on the model until it earns the trip out. This skill encodes the "earn it" criteria.

## The opinion (DHH-leaning, with explicit exceptions)

> **Default: keep logic in the model. Split fat models with `ActiveSupport::Concern`. Extract a service object only when (a) the workflow orchestrates 3+ models in one transactional unit, (b) the workflow calls an external API, (c) the workflow has multiple distinct outcomes that callers must branch on, or (d) the workflow has no obvious model home.**

Counter-position: at very large team size (20+ engineers) or in domains with heavy procedural business logic (insurance underwriting, multi-step billing, regulated workflows), small-object-per-responsibility scales reading better than fat models. We acknowledge that and recommend it — but only as a deliberate choice, not as the default. The Sandi Metz / "single responsibility" doctrine is real but expensive when applied prematurely.

DHH on this:

> "I far prefer `current_account.posts.visible_to(current_user)` to involving a third query object."
>
> "We have used this approach for about 8 years in the Basecamp code base and been so happy with the result that every subsequent app we've made has followed the same pattern with great results."

## Core patterns

### Pattern 1: The default — fat model

**Before** (premature extraction):

```ruby
# app/services/publish_post_service.rb
class PublishPostService
  def initialize(post)
    @post = post
  end

  def call
    @post.update(published_at: Time.current, status: "published")
  end
end

# controller
PublishPostService.new(@post).call
```

**After** (model method):

```ruby
# app/models/post.rb
class Post < ApplicationRecord
  def publish!
    update!(published_at: Time.current, status: "published")
  end
end

# controller
@post.publish!
```

**Why:** the service does *one thing on one model*. It's a method, not a workflow. The service-object version adds a class, a file, indirection, and zero capability. `post.publish!` reads naturally because publishing is what a Post does.

### Pattern 2: When a service object earns its keep

Four trigger conditions. If any of these are true, extract:

#### Trigger 1: Multi-model transactional orchestration

The workflow touches 3+ models that must commit together.

```ruby
# app/services/place_order.rb
class PlaceOrder
  Result = Data.define(:success?, :order, :error)

  def initialize(cart:, user:, payment_method:)
    @cart = cart
    @user = user
    @payment_method = payment_method
  end

  def call
    ActiveRecord::Base.transaction do
      order = build_order
      decrement_inventory(order)
      charge = capture_payment(order)
      order.update!(payment_id: charge.id, status: "paid")
      Result.new(success?: true, order: order, error: nil)
    end
  rescue Stripe::CardError => e
    Result.new(success?: false, order: nil, error: e.message)
  end

  private

  def build_order
    order = @user.orders.create!(cart: @cart, total: @cart.total)
    @cart.items.each { |item| order.line_items.create!(product: item.product, quantity: item.quantity, price: item.price) }
    order
  end

  def decrement_inventory(order)
    order.line_items.each do |li|
      li.product.lock!
      raise "Out of stock" if li.product.stock < li.quantity
      li.product.update!(stock: li.product.stock - li.quantity)
    end
  end

  def capture_payment(order)
    Stripe::PaymentIntent.create(amount: (order.total * 100).to_i, currency: "usd", payment_method: @payment_method.token, confirm: true)
  end
end

# controller
result = PlaceOrder.new(cart: @cart, user: current_user, payment_method: @payment_method).call
if result.success?
  redirect_to result.order
else
  flash[:error] = result.error
  render :new
end
```

**Why:** Cart, Order, LineItem, Product, Charge — five models in one workflow. None of them is the "natural home" for "place an order." Putting this on `Cart#checkout!` makes Cart know about Stripe; putting it on `Order.create_from_cart` makes Order know about inventory locking; etc. The service is the right home.

#### Trigger 2: External API call

External calls have failure modes (network, rate limits, expired tokens) that don't belong in models.

```ruby
# app/services/sync_to_hubspot.rb
class SyncToHubspot
  Result = Data.define(:status, :contact, :error)

  def initialize(contact)
    @contact = contact
  end

  def call
    response = Hubspot::Contact.upsert(@contact.to_hubspot_payload)
    @contact.update!(hubspot_id: response.id, hubspot_synced_at: Time.current)
    Result.new(status: :success, contact: @contact, error: nil)
  rescue Hubspot::RateLimitError
    SyncToHubspotJob.set(wait: 1.minute).perform_later(@contact.id)
    Result.new(status: :retrying, contact: @contact, error: nil)
  rescue Hubspot::Error => e
    @contact.update!(hubspot_error: e.message)
    Result.new(status: :failure, contact: @contact, error: e.message)
  end
end
```

**Why:** the workflow has retry logic, error handling specific to the external API, and writes back to the model. Doing this in `Contact#sync_to_hubspot!` pollutes the model with Hubspot concerns. The service owns the integration; the model owns the data.

#### Trigger 3: Multiple distinct outcomes (Result type)

When callers need to branch on three or more outcomes — `success`, `retry`, `failure`, `not_yet_eligible`, etc. — a Result type makes the branching explicit.

```ruby
class IssueRefund
  Result = Data.define(:status, :refund, :reason)

  def initialize(order:, amount:)
    @order = order
    @amount = amount
  end

  def call
    return Result.new(status: :already_refunded, refund: nil, reason: nil) if @order.refunded?
    return Result.new(status: :requires_approval, refund: nil, reason: "amount over threshold") if @amount > 10_000

    refund = Stripe::Refund.create(charge: @order.stripe_charge_id, amount: @amount * 100)
    @order.update!(refunded_at: Time.current, refund_amount: @amount)
    Result.new(status: :refunded, refund: refund, reason: nil)
  rescue Stripe::InvalidRequestError => e
    Result.new(status: :denied, refund: nil, reason: e.message)
  end
end

# controller
case IssueRefund.new(order: @order, amount: @amount).call
in { status: :refunded, refund: }
  redirect_to refund
in { status: :requires_approval }
  redirect_to admin_approvals_path
in { status: :denied, reason: }
  flash[:error] = reason
  render :new
end
```

Ruby 3.0+ pattern matching makes this elegant. Avoid raising exceptions for non-exceptional outcomes — Result types make the branching obvious.

#### Trigger 4: No obvious model home

```ruby
# Where does this go on a model?
class GenerateMonthlyReport
  def call
    # Pulls from 8 tables, builds a PDF, uploads to S3, emails to subscribers.
  end
end
```

`Report` doesn't exist as a model; the workflow spans tables; making it `User#generate_monthly_report` is wrong because reports aren't a User responsibility. Service object earns its place.

### Pattern 3: Naming convention

**Recommendation:** **`VerbNoun`** for action services (`PlaceOrder`, `RefundCharge`, `SyncContact`), **no `Service` suffix**.

| Naming | Verdict | Why |
|---|---|---|
| `PlaceOrder` | Good | The class IS the action. Reads naturally at the call site. |
| `OrderPlacer` | Acceptable | Common in older codebases. Personifies the action — fine. |
| `OrderPlacement` | Acceptable | Noun-style. Fine if the team prefers nouns. |
| `PlaceOrderService` | Avoid | Suffix is noise — every class is a "service" in some sense. The directory `app/services/` already names the layer. |
| `OrderService` | Bad | Too broad. "Order service that does what?" Becomes a god class. |
| `OrderManager` / `OrderHandler` / `OrderProcessor` | Bad | Vague verbs. Manager of what? Handler of which event? |

Call site reads better with VerbNoun:

```ruby
PlaceOrder.new(...).call            # clear
OrderService.new(...).place_order   # nested verb, why?
```

### Pattern 4: The Result pattern — three options

#### Option A — `Data.define` (Ruby 3.2+, no dependency)

```ruby
class PlaceOrder
  Result = Data.define(:success?, :order, :error)

  def call
    # ...
    Result.new(success?: true, order: order, error: nil)
  end
end
```

Lightweight. No dependencies. Pattern-matchable. Recommended for new code.

#### Option B — Custom Result class

```ruby
class Result
  attr_reader :value, :error
  def self.success(value); new(success: true, value: value, error: nil); end
  def self.failure(error); new(success: false, value: nil, error: error); end
  def initialize(success:, value:, error:); @success = success; @value = value; @error = error; end
  def success?; @success; end
end
```

Same idea as Option A pre-Ruby-3.2. Fine in legacy apps.

#### Option C — `dry-monads`

```ruby
require "dry/monads"

class PlaceOrder
  include Dry::Monads[:result]

  def call
    # ...
    Success(order)
  rescue Stripe::CardError => e
    Failure(e.message)
  end
end

# Caller:
PlaceOrder.new(...).call.bind { |order| ... }.value_or { |err| ... }
```

**Recommendation:** stick with Option A (Data.define) unless your team has already standardized on dry-monads. Dry-monads is powerful but adds a vocabulary every new dev must learn. The cost outweighs the benefit for most teams.

### Pattern 5: Service object structure

Pick one interface and apply it consistently across the codebase:

```ruby
# Style 1 — `call` instance method, `.call` class shortcut
class PlaceOrder
  def self.call(...) = new(...).call
  def initialize(cart:, user:); @cart = cart; @user = user; end
  def call; ...; end
end

PlaceOrder.call(cart: @cart, user: current_user)
```

```ruby
# Style 2 — verb name as the method
class PlaceOrder
  def initialize(cart:, user:); ...; end
  def place; ...; end
end

PlaceOrder.new(cart: @cart, user: current_user).place
```

**Recommendation:** Style 1 (`.call`) — uniform interface across all services, plays well with `Proc#call`, makes services swappable behind an interface.

### Pattern 6: When you really want the interactor gem

[`interactor`](https://github.com/collectiveidea/interactor) provides:
- Standardized `call` interface.
- `Interactor::Organizer` for chaining services with rollback.
- Built-in `context` object for in/out data.

```ruby
class PlaceOrder
  include Interactor::Organizer
  organize BuildOrder, ChargePayment, DecrementInventory, SendConfirmation
end
```

**When it helps:** you have many services that compose in sequences. The Organizer makes the composition declarative and auto-rolls-back on failure.

**When it doesn't:** the team finds the `context` object confusing (everything is a hash key — no clear contract per step). The standalone `Data.define` Result pattern is often clearer.

### Pattern 7: Anti-patterns

**Anti-pattern 1: Service that wraps one model method**

```ruby
# BAD
class DeletePostService
  def call(post); post.destroy!; end
end

# GOOD
post.destroy!
```

The service adds zero capability. If you find yourself writing this, the model method is the answer.

**Anti-pattern 2: Service that should be a job**

```ruby
# BAD — controller blocks on a 5-second external call
SyncToHubspot.new(contact).call

# GOOD — fire-and-forget
SyncToHubspotJob.perform_later(contact.id)
```

If the workflow doesn't need to complete before responding to the user, it's a job, not a service. (The job's `perform` calls the service — see below.) See `solid-queue-and-sidekiq`.

```ruby
class SyncToHubspotJob < ApplicationJob
  retry_on Hubspot::RateLimitError, wait: :polynomially_longer, attempts: 5

  def perform(contact_id)
    contact = Contact.find(contact_id)
    SyncToHubspot.new(contact).call
  end
end
```

**Anti-pattern 3: God-service that does everything**

```ruby
# BAD
class OrderService
  def place_order(...); end
  def cancel_order(...); end
  def refund_order(...); end
  def export_orders(...); end
  # ... 30 more methods
end
```

Split into `PlaceOrder`, `CancelOrder`, `RefundOrder`, `ExportOrders`. One verb per service.

**Anti-pattern 4: Service that does too little to justify itself**

If the service is ~5 lines, ask: is there a model method? Is there a job? Is the controller fine doing this inline?

### Pattern 8: Form objects vs service objects

Both extract logic out of controllers, but they solve different problems:

| Concern | Solution |
|---|---|
| User input → validation → save | Form object |
| Workflow orchestrating multiple models | Service object |
| Both: bind to a form AND orchestrate? | Form object for binding, calls a service for the work |

Quick example:

```ruby
class SignupForm
  include ActiveModel::Model
  attr_accessor :email, :password, :company_name
  validates :email, :password, :company_name, presence: true

  def save
    return false unless valid?
    OnboardCompany.call(email: email, password: password, company_name: company_name)
  end
end

class OnboardCompany
  def self.call(email:, password:, company_name:)
    ActiveRecord::Base.transaction do
      account = Account.create!(name: company_name)
      user = User.create!(email: email, password: password, account: account)
      DefaultPermissions.apply_to(user)
      WelcomeMailer.with(user: user).welcome_email.deliver_later
      user
    end
  end
end
```

Form object binds the form; service object does the work. Full form-object patterns live in the v0.2 skill `form-objects-query-objects-presenters`.

## Decision matrix

| Situation | Default |
|---|---|
| One model, one method, no external call | Model method |
| Many related methods on one model | Model + concerns (see `activerecord-patterns` Pattern 12) |
| Cross-model workflow, transactional, 3+ models | Service object |
| External API integration | Service object |
| Asynchronous side effect | Job (which can call a service) |
| Form-based input → validation | Form object (calls a service if needed) |
| Multiple outcomes (success/retry/failure/needs_approval) | Service object with Result type |
| Reusable read query | Scope (see `activerecord-patterns` Pattern 5) — NOT a service |

## Common mistakes to refuse

- Don't extract a service for `model.do_one_thing` — put it on the model.
- Don't name services `<Noun>Service` / `<Noun>Manager` — they become god classes.
- Don't raise exceptions for non-exceptional outcomes — use a Result type.
- Don't put external API calls in the model — pull them into a service.
- Don't put service-object work in the controller — controllers are HTTP glue, not workflow orchestration.
- Don't reach for `dry-monads` on a new project — `Data.define` is enough.
- Don't put a service object behind every controller action. Most actions don't need one.

## When NOT to use this skill

- Pure controller/routing question — answer directly.
- Pure data-modeling question with no workflow — `activerecord-patterns` is the right skill.
- Background job design — `solid-queue-and-sidekiq`.

## See also

- `activerecord-patterns` — Pattern 12 (fat models + concerns)
- `solid-queue-and-sidekiq` — when the workflow should be a job
- `rspec-testing-pyramid` — how to test service objects vs models
- Coming in v0.2: `form-objects-query-objects-presenters` — when models still aren't right

## Sources

- [DHH — Put Chubby Models on a Diet with Concerns](https://signalvnoise.com/posts/3372-put-chubby-models-on-a-diet-with-concerns)
- [Bryan Helmkamp — 7 Patterns to Refactor Fat ActiveRecord Models](https://thoughtbot.com/blog/refactor-models) (Code Climate; archived)
- [Rails Guides — Active Record Basics](https://guides.rubyonrails.org/active_record_basics.html)
- [Rails Guides — Active Record Callbacks](https://guides.rubyonrails.org/active_record_callbacks.html)
- [Avdi Grimm — Confident Ruby](https://avdi.codes/) (Result-style returns)
- [Interactor gem](https://github.com/collectiveidea/interactor)
- [dry-monads](https://dry-rb.org/gems/dry-monads/)
- [Ruby 3.2 Data.define](https://docs.ruby-lang.org/en/3.2/Data.html)
- [Sandi Metz — POODR](https://sandimetz.com/) (small-object doctrine, counter-position)
- [Ruby 3 pattern matching](https://docs.ruby-lang.org/en/3.0/syntax/pattern_matching_rdoc.html) — Result branching
