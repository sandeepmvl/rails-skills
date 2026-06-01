---
name: actionmailer-baseline
description: ActionMailer baseline for Rails 8 — mailer setup, deliver_later by default (never deliver_now in the request path), Mailer previews in dev, mailer specs with RSpec, Letter Opener for dev inspection, transactional delivery via Postmark / SendGrid / SES / Mailgun, bounce and complaint handling, idempotent transactional sends, attachments and inline images, i18n for subject lines and bodies. Use when the user mentions ActionMailer, mailers, deliver_later, deliver_now, mailer previews, transactional email, Postmark, SendGrid, SES, Mailgun, bounces, mailer specs, Letter Opener, or asks how to send email from Rails.
---

# ActionMailer Baseline

> Send email from a Rails 8 app without four classic mistakes: blocking the request thread, double-sending on retry, leaking PII in logs, or rendering broken HTML that bounces. AI agents reach for `ActionMailer::Base.mail` with `deliver_now` by default and stop there. This skill covers the rest.

## Why this matters

Email is the integration most teams underestimate. It's external infrastructure (SMTP, vendor APIs), it has rate limits, it has bounce rules, it has spam-trap consequences. Doing it casually means either sluggish requests, lost mail, or your domain on a deny-list.

## The opinion

> **`deliver_later` is the default. Never `deliver_now` in the request path. Mailer previews wired in development. Postmark / SendGrid / SES / Mailgun via the vendor's Rails adapter; don't roll your own SMTP. Bounce + complaint handling required for any user-facing app at scale. Idempotency on transactional sends (password reset link generated once per request, not per retry). PII filtered from logs and error reports.**

Counter-positions:
- **`deliver_now`** is legitimate in tests (synchronous) and in admin tools (where blocking the admin user 200ms is fine). Never in user-facing request paths.
- **Action Mailbox** for *receiving* email — different scope (deferred to v0.2). This skill covers sending.

## Core patterns

### Pattern 1: Generate + set up

```bash
bin/rails generate mailer UserMailer welcome reset_password
```

```ruby
# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "no-reply@example.com")
  layout "mailer"
end

# app/mailers/user_mailer.rb
class UserMailer < ApplicationMailer
  default template_path: "user_mailer"  # explicit; not required but reads better

  def welcome(user)
    @user = user
    @url = sign_in_url
    mail(to: @user.email, subject: I18n.t("mailers.user.welcome.subject"))
  end

  def reset_password(user, raw_token)
    @user = user
    @reset_url = edit_password_reset_url(token: raw_token)
    mail(to: @user.email, subject: I18n.t("mailers.user.reset_password.subject"))
  end
end
```

```erb
<!-- app/views/user_mailer/welcome.html.erb -->
<h1>Welcome, <%= @user.name %>!</h1>
<p><%= link_to "Get started", @url %></p>

<!-- app/views/user_mailer/welcome.text.erb -->
Welcome, <%= @user.name %>!

Get started: <%= @url %>
```

**Always ship both HTML and text versions.** Spam filters score multipart higher; some clients still render text only.

### Pattern 2: `deliver_later` (never `deliver_now` in requests)

**Before** (AI default, blocks the request):

```ruby
def create
  @user = User.create!(user_params)
  UserMailer.welcome(@user).deliver_now  # 200-1000ms blocking call
  redirect_to @user
end
```

**After**:

```ruby
def create
  @user = User.create!(user_params)
  UserMailer.welcome(@user).deliver_later  # enqueues a job; returns immediately
  redirect_to @user
end
```

**Why `deliver_later`:**
- Email delivery is network I/O against an external service (SMTP, API). Latency varies — sometimes 200ms, sometimes 5 seconds.
- The user shouldn't wait. Enqueue, respond, deliver in background.
- Retries happen automatically when the worker fails (job adapter handles).

**Where `deliver_now` is fine:**
- Tests (`deliver_now` is the default test adapter; assertions look at `ActionMailer::Base.deliveries`).
- Rake tasks where the operator is waiting.
- Mailer previews (the preview is the response; no async).

### Pattern 3: Mailer previews

```ruby
# spec/mailers/previews/user_mailer_preview.rb
class UserMailerPreview < ActionMailer::Preview
  def welcome
    user = User.first || User.new(email: "test@example.com", name: "Alice")
    UserMailer.welcome(user)
  end

  def reset_password
    user = User.first || User.new(email: "test@example.com")
    UserMailer.reset_password(user, "fake-token-for-preview")
  end
end
```

```ruby
# config/environments/development.rb
config.action_mailer.preview_paths = ["#{Rails.root}/spec/mailers/previews"]
```

Now visit `http://localhost:3000/rails/mailers/user_mailer/welcome` to see the rendered HTML.

**Why this matters:** AI agents (and humans) can't easily eyeball mailer templates without rendering them. Previews let you check the design in your browser in seconds. Every mailer action gets a preview.

### Pattern 4: Letter Opener for dev (open emails in the browser)

```ruby
# Gemfile (development group)
gem "letter_opener", group: :development

# config/environments/development.rb
config.action_mailer.delivery_method = :letter_opener
config.action_mailer.perform_deliveries = true
```

Now `UserMailer.welcome(user).deliver_now` in dev opens the email in a new browser tab. Easier than checking `tmp/letter_opener/` files.

Pair with `letter_opener_web` to get a `/letter_opener` route showing the history.

### Pattern 5: Production delivery — Postmark / SendGrid / SES / Mailgun

```ruby
# config/environments/production.rb

# === Postmark (recommended for transactional) ===
config.action_mailer.delivery_method = :postmark
config.action_mailer.postmark_settings = {
  api_token: Rails.application.credentials.postmark_api_token
}

# === SendGrid ===
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address: "smtp.sendgrid.net",
  port: 587,
  domain: "example.com",
  user_name: "apikey",
  password: Rails.application.credentials.sendgrid_api_key,
  authentication: :plain,
  enable_starttls_auto: true
}

# === AWS SES via the official SDK ===
# Gemfile: gem "aws-sdk-rails"
config.action_mailer.delivery_method = :ses
# Uses your AWS credentials chain

# === Mailgun ===
# Gemfile: gem "mailgun-ruby"
config.action_mailer.delivery_method = :mailgun
config.action_mailer.mailgun_settings = {
  api_key: Rails.application.credentials.mailgun_api_key,
  domain: "mg.example.com"
}
```

**Decision matrix:**

| Vendor | Best for | Why |
|---|---|---|
| Postmark | Transactional (signup, password reset, receipts) | Highest deliverability; aggressive filtering of marketing-like mail keeps reputation high |
| SendGrid | Mixed (transactional + marketing) | Large free tier; widely supported |
| AWS SES | High volume, cost-sensitive | Cheapest at scale (~$0.10 per 1k); requires more reputation management |
| Mailgun | EU sovereignty, log-search workflows | Good EU presence; logs are queryable |

**Never** `delivery_method: :smtp` to your own mail server in 2026 — deliverability is dominated by sender reputation and DKIM/DMARC. Vendors handle these.

### Pattern 6: Bounce and complaint handling

Every mail vendor sends webhooks for bounces (hard / soft) and complaints (spam-marked):

```ruby
# config/routes.rb
post "/webhooks/postmark", to: "webhooks#postmark"

# app/controllers/webhooks_controller.rb
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def postmark
    # Verify signature first — see rails-security-baseline
    return head(:bad_request) unless valid_postmark_signature?

    case params[:RecordType]
    when "Bounce"      then handle_bounce(params)
    when "SpamComplaint" then handle_complaint(params)
    end
    head :ok
  end

  private

  def handle_bounce(payload)
    email = payload[:Email]
    if payload[:Type] == "HardBounce"
      User.where(email: email).find_each { |u| u.update!(email_status: "bounced", deliverable: false) }
    end
  end

  def handle_complaint(payload)
    email = payload[:Email]
    User.where(email: email).find_each { |u| u.update!(email_status: "complained", deliverable: false) }
  end
end
```

**Why this matters:** continuing to send to bounced or complaining addresses kills your sender reputation. Vendors give you the signal — wire it.

**Suppression list:** maintain `User#deliverable?`. Use a global ActionMailer interceptor — it sees the rendered `Mail::Message` and can drop deliveries based on the `to` field:

```ruby
# config/initializers/mailer_interceptors.rb
class SuppressUndeliverableInterceptor
  def self.delivering_email(message)
    emails = Array(message.to)
    if User.where(email: emails, deliverable: false).exists?
      message.perform_deliveries = false
    end
  end
end

ActionMailer::Base.register_interceptor(SuppressUndeliverableInterceptor)
```

Interceptors run for every mailer, take the rendered message, and can mutate it (or stop delivery). This is the right hook — `before_action` in the mailer fires before the action sets `@user` and doesn't expose the message object.

### Pattern 7: Idempotent transactional sends

```ruby
class PasswordResetsController < ApplicationController
  def create
    user = User.find_by(email: params[:email])
    if user
      # Generate the token ONCE per request, not per retry
      raw_token = SecureRandom.urlsafe_base64(32)
      user.update!(
        password_reset_token: Digest::SHA256.hexdigest(raw_token),
        password_reset_sent_at: Time.current
      )
      UserMailer.reset_password(user, raw_token).deliver_later
    end
    # Always respond the same way — don't leak whether the email exists
    redirect_to root_path, notice: "Check your email for instructions."
  end
end
```

**Why idempotent:** if the user double-clicks, you don't want two separate password-reset emails with different tokens. The above pattern works because the controller is one request, but for jobs that retry:

```ruby
class WelcomeEmailJob < ApplicationJob
  retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 3

  def perform(user_id)
    user = User.find(user_id)
    return if user.welcome_sent_at.present?  # already sent — retry is a no-op

    UserMailer.welcome(user).deliver_now  # delivered synchronously inside the job
    user.update!(welcome_sent_at: Time.current)
  end
end
```

**Or use a delivery-tracking column** for any mailer that retries. The job's idempotency guard prevents duplicate sends.

### Pattern 8: Attachments and inline images

```ruby
class InvoiceMailer < ApplicationMailer
  def monthly_statement(invoice)
    @invoice = invoice
    attachments["statement-#{invoice.id}.pdf"] = invoice.pdf  # binary content
    attachments.inline["logo.png"] = File.read(Rails.root.join("app/assets/images/logo.png"))
    mail(to: invoice.user.email, subject: "Your statement for #{invoice.month}")
  end
end
```

```erb
<%# View — reference inline attachment by content-id %>
<img src="<%= attachments['logo.png'].url %>" alt="Logo">
```

**Inline images** vs **attachments**:
- Inline (cid:) appear in the message body (rendered logos, embedded images).
- Attachments appear as downloadable files at the bottom.

Both add to message size. Vendors charge by size — don't embed 5MB images casually.

### Pattern 9: i18n for subjects and bodies

```yaml
# config/locales/en.yml
en:
  mailers:
    user:
      welcome:
        subject: "Welcome to MyApp"
        greeting: "Welcome, %{name}!"
      reset_password:
        subject: "Reset your password"
```

```ruby
class UserMailer < ApplicationMailer
  def welcome(user)
    @user = user
    I18n.with_locale(user.locale || I18n.default_locale) do
      mail(to: user.email, subject: I18n.t("mailers.user.welcome.subject"))
    end
  end
end
```

```erb
<%= I18n.t("mailers.user.welcome.greeting", name: @user.name) %>
```

**Why `I18n.with_locale`:** without it, the mailer uses whatever locale was set on the request — wrong if the user prefers a different language. Pass the user's preferred locale explicitly.

### Pattern 10: Testing mailers

```ruby
# spec/mailers/user_mailer_spec.rb
RSpec.describe UserMailer, type: :mailer do
  describe "#welcome" do
    let(:user) { create(:user, name: "Alice") }
    let(:mail) { described_class.welcome(user) }

    it "renders the headers" do
      expect(mail.subject).to eq("Welcome to MyApp")
      expect(mail.to).to eq([user.email])
      expect(mail.from).to eq(["no-reply@example.com"])
    end

    it "renders the body" do
      expect(mail.body.encoded).to include("Welcome, Alice")
      expect(mail.html_part.body.encoded).to include("<h1>Welcome, Alice!</h1>")
      expect(mail.text_part.body.encoded).to include("Welcome, Alice!")
    end
  end
end

# spec/jobs/welcome_email_job_spec.rb
RSpec.describe WelcomeEmailJob, type: :job do
  # The job calls `UserMailer.welcome(user).deliver_later`. `have_enqueued_mail`
  # checks the Active Job queue, so the job body must use `deliver_later`. If your
  # job uses `deliver_now` instead, assert `ActionMailer::Base.deliveries.size`.
  it "enqueues the welcome mail" do
    user = create(:user)
    expect {
      described_class.perform_now(user.id)
    }.to have_enqueued_mail(UserMailer, :welcome).with(user)
  end

  it "is idempotent" do
    user = create(:user, welcome_sent_at: 1.hour.ago)
    expect {
      described_class.perform_now(user.id)
    }.not_to have_enqueued_mail(UserMailer, :welcome)
  end
end

# spec/requests/registrations_spec.rb
RSpec.describe "POST /users", type: :request do
  it "enqueues a welcome email" do
    expect {
      post users_path, params: { user: attributes_for(:user) }
    }.to have_enqueued_mail(UserMailer, :welcome)
  end
end
```

**`have_enqueued_mail` matcher** is the rspec-rails idiom — checks that the mailer is *enqueued* (via `deliver_later`) without actually delivering.

## Decision matrix

| Need | Use |
|---|---|
| Send from a controller | `deliver_later` |
| Send from a job (already async) | `deliver_now` inside the job |
| Send from a rake task | `deliver_now` (or `deliver_later` if you want the worker to handle it) |
| Preview in dev | Mailer Preview + visit `/rails/mailers` |
| Inspect actual rendering in dev | Letter Opener |
| Transactional vendor | Postmark for highest deliverability |
| Marketing-friendly vendor | SendGrid |
| Cost-sensitive at high volume | AWS SES |
| Bounce/complaint handling | Webhook + suppression list |
| Idempotency | Pre-check a sent_at column |
| Multi-language users | I18n.with_locale per recipient |

## Common mistakes to refuse

- Don't `deliver_now` in a controller — block the response.
- Don't skip text part — spam filters score multipart higher.
- Don't ignore bounces — your sender reputation dies.
- Don't use your own SMTP server — vendor required for prod deliverability.
- Don't generate tokens inside a job that retries — token gets a new value every retry.
- Don't include the entire user object in the JWT-style token URL — keep it short.
- Don't send the same email twice on retry — pre-check sent_at.
- Don't put secrets in mailer templates — they end up in the rendered HTML.
- Don't render variables that could be nil without a fallback — broken email → bounce.

## When NOT to use this skill

- The user is asking about *receiving* email — that's Action Mailbox, deferred to v0.2.
- The user is asking about email *deliverability* at the DNS level (SPF, DKIM, DMARC) — out of scope here; vendor docs cover it.

## See also

- `solid-queue-and-sidekiq` — mailer jobs are jobs
- `activerecord-patterns` — Pattern 7 (`after_commit` to enqueue welcome mail)
- `rails-security-baseline` — webhook signature verification
- `observability-baseline` — PII scrubbing applies to mailer payloads in error reports
- Coming in v0.2: `i18n-and-timezones` — full i18n coverage

## Sources

- [Rails Guides — Action Mailer Basics](https://guides.rubyonrails.org/action_mailer_basics.html)
- [Rails Guides — Testing Mailers](https://guides.rubyonrails.org/testing.html#testing-your-mailers)
- [Postmark Rails docs](https://postmarkapp.com/developer/integrations/ruby-on-rails)
- [SendGrid Rails integration](https://docs.sendgrid.com/for-developers/sending-email/integrating-with-the-smtp-api)
- [AWS SES via aws-sdk-rails](https://github.com/aws/aws-sdk-rails)
- [Letter Opener](https://github.com/ryanb/letter_opener)
- [letter_opener_web](https://github.com/fgrehm/letter_opener_web)
- [rspec-rails mailer matchers](https://github.com/rspec/rspec-rails) — `have_enqueued_mail`
- [Email deliverability — Postmark blog](https://postmarkapp.com/guides/email-best-practices)
- [DKIM / SPF / DMARC — Cloudflare guide](https://www.cloudflare.com/learning/email-security/email-spoofing/)
