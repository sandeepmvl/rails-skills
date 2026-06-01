---
name: rails-security-baseline
description: Security baseline for Ruby on Rails 8 apps — strong params (and their common bypass mistakes), CSRF for browser apps, CSRF for SPAs, Brakeman + bundler-audit + Dependabot, Rails credentials per environment, JWT best practices (short-lived + refresh rotation, never put secrets in payload), CORS without wildcards, Rack::Attack for rate limiting and brute-force, OWASP Top 10 mapped to Rails. Use when reviewing or writing any controller, when the user mentions security, CSRF, params, mass assignment, secrets, credentials, JWT, CORS, Brakeman, bundler-audit, OWASP, secure headers, content security policy, or asks "is this safe to ship". Use proactively before any commit that touches auth, params, or external input.
---

# Rails Security Baseline

> Ship a Rails 8 app without the obvious vulnerabilities. AI agents introduce common security bugs by default: permissive strong params, CSRF disabled with `protect_from_forgery null_session` "to make it work", JWTs with secrets in payload, CORS wildcards. This skill encodes the floor.

## Why this matters

A web app is an attack surface. Every default that ships is a potential vulnerability if mis-wired. Rails defaults are mostly good but a single misconfiguration can leak data, hijack sessions, or grant admin. This skill names the patterns and the mistakes.

## The opinion

> **Strong params with `require` + explicit `permit` keys. CSRF on for browser apps, bearer tokens for cross-origin APIs. Brakeman + bundler-audit + Dependabot in CI from day one. Rails credentials per environment, master keys in env vars. JWTs short-lived (5-15 min) + refresh tokens with rotation. CORS with explicit origins (never `*` for authenticated endpoints). Rack::Attack on login, signup, password reset. secure_headers gem for CSP / HSTS / X-Frame-Options.**

## The OWASP Top 10 → Rails mapping

See [`references/owasp-rails-mapping.md`](references/owasp-rails-mapping.md) for the full breakdown. Quick reference:

| OWASP | Rails defense |
|---|---|
| A01: Broken Access Control | Pundit policies + `verify_authorized` after_action |
| A02: Cryptographic Failures | bcrypt via Devise; Rails credentials (AES-256-GCM); no MD5/SHA1 |
| A03: Injection | Parameterized queries (default in AR); never `where("foo = #{params[:x]}")` |
| A04: Insecure Design | Threat model auth + sessions before scaffolding |
| A05: Security Misconfiguration | secure_headers gem; HSTS; CSP; `force_ssl` |
| A06: Vulnerable Components | Dependabot + bundler-audit + `bundle outdated` weekly |
| A07: Auth Failures | Devise/Rodauth defaults; lockable; bcrypt cost ≥12 |
| A08: Software & Data Integrity | Sign artifacts; verify webhook signatures; SRI for CDN scripts |
| A09: Logging Failures | lograge + Sentry + PII scrubbing (see `observability-baseline`) |
| A10: SSRF | Validate user-supplied URLs; allowlist hosts; never `Net::HTTP.get(URI(params[:url]))` |

## Core patterns

### Pattern 1: Strong params — the bypass mistakes

**Before** (AI default — permissive):

```ruby
def user_params
  params.require(:user).permit!  # WRONG — permits everything
end

def user_params
  params.require(:user).permit(params[:user].keys)  # WRONG — same effect
end
```

Either gives the attacker mass-assignment to admin: `POST /users` with `{ user: { email: "...", admin: true } }`.

**After** (explicit allowlist):

```ruby
def user_params
  params.require(:user).permit(:email, :name, :password, :password_confirmation)
end

# For nested attributes:
def post_params
  params.require(:post).permit(:title, :body, :status, tag_ids: [], comments_attributes: %i[id body _destroy])
end

# When a field is sometimes-present (e.g. password on edit):
def user_params
  permitted = params.require(:user).permit(:email, :name)
  permitted.merge!(params[:user].permit(:password, :password_confirmation)) if params[:user][:password].present?
  permitted
end
```

**Always:**
- `require` the top-level key. Without it, `params[:user]` might be nil and `nil.permit` raises in a confusing way.
- `permit` the leaf keys explicitly. List every one.
- For arrays: `tag_ids: []`.
- For nested resources: `attribute: %i[allowed keys]`.
- For arbitrarily-shaped JSON: don't accept arbitrarily-shaped JSON. Define the shape.

### Pattern 2: CSRF — browser apps

Rails' default `protect_from_forgery with: :exception` is correct. Don't change it.

**Common AI mistakes:**

```ruby
# WRONG — silently logs the user out
protect_from_forgery with: :null_session

# WRONG — disables CSRF
protect_from_forgery with: :null_session, prepend: true

# WORST — disables CSRF entirely
skip_before_action :verify_authenticity_token
```

`:null_session` is for API-only controllers where you DON'T use cookies — turning it on in cookie-based apps means session is silently emptied on CSRF failure rather than throwing. Confusing failure mode.

**For Turbo / Hotwire AJAX requests:** Rails handles automatically — Turbo includes the CSRF token in headers.

**For external webhook endpoints** (Stripe, GitHub, Slack): legitimate to skip CSRF, but VERIFY the webhook signature instead.

```ruby
class WebhooksController < ActionController::Base
  skip_before_action :verify_authenticity_token

  def stripe
    payload = request.raw_post
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]
    event = Stripe::Webhook.construct_event(payload, sig_header, Rails.application.credentials.stripe_webhook_secret)
    # ... process event
    head :ok
  rescue Stripe::SignatureVerificationError
    head :bad_request
  end
end
```

### Pattern 3: CSRF — SPAs

Two correct options:

**Option A: Cookies + CSRF token endpoint** (recommended for first-party SPAs).

```ruby
# Server: expose the CSRF token
class CsrfController < ApplicationController
  def show
    render json: { csrf_token: form_authenticity_token }
  end
end

# SPA: fetch the token, include it in X-CSRF-Token header on mutations
```

**Option B: Bearer tokens, no cookies.**

`skip_before_action :verify_authenticity_token` is fine when:
- Auth is via `Authorization: Bearer <token>` header.
- No cookies used for auth.
- Token is from a request-only source (not stored in JS-accessible storage long-term).

CSRF is a cookie problem. No cookies → no CSRF.

### Pattern 4: Brakeman, bundler-audit, Dependabot

```yaml
# .github/workflows/security.yml
name: Security
on: [push, pull_request]
jobs:
  brakeman:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { bundler-cache: true }
      - run: bundle exec brakeman --no-progress --quiet --confidence-level 2

  bundler-audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with: { bundler-cache: true }
      - run: bundle exec bundle-audit check --update

  dependabot:
    # .github/dependabot.yml
    # version: 2
    # updates:
    #   - package-ecosystem: bundler
    #     directory: "/"
    #     schedule:
    #       interval: weekly
```

**Why each:**
- **Brakeman**: static analysis for Rails security smells (SQL injection, mass assignment, dynamic render, etc.).
- **bundler-audit**: checks `Gemfile.lock` against CVE database.
- **Dependabot**: opens PRs to bump gems with known vulnerabilities.

All three run in CI; CI fails on findings; you tune `confidence-level` to balance signal vs noise.

### Pattern 5: Rails credentials — per environment

```bash
# Create per-environment credentials
EDITOR=vim bin/rails credentials:edit --environment=production
EDITOR=vim bin/rails credentials:edit --environment=staging
EDITOR=vim bin/rails credentials:edit --environment=development

# Generated:
config/credentials/production.yml.enc       (committed, encrypted)
config/credentials/production.key           (gitignored, the decryption key)
```

```ruby
# Access in code:
Rails.application.credentials.stripe_secret_key
Rails.application.credentials.dig(:aws, :access_key_id)
```

**Why per-environment:**
- Production credentials in dev = developer machines can hit prod systems (one wrong rake task away from disaster).
- Staging credentials = isolated test setup against staging vendor accounts.
- Compromise of one environment's credentials doesn't reveal others.

**Master key handling:**

```bash
# Production: RAILS_MASTER_KEY env var (Kamal env.secret, ECS task def, Heroku config var)
RAILS_MASTER_KEY=<production-key> bundle exec rails server

# Never commit master.key. .gitignore should have it.
```

**Rotation:**

```bash
# Generate new key + rewrite credentials
mv config/credentials/production.key config/credentials/production.key.bak
bin/rails credentials:edit --environment=production  # rails creates a new key
# Update RAILS_MASTER_KEY in your deploy secrets store
# Verify, then delete the backup
```

### Pattern 6: JWT best practices

```ruby
# Anti-pattern — 30-day token with user data in payload
def jwt_payload(user)
  {
    user_id: user.id,
    email: user.email,           # email in payload — visible to anyone with the token
    admin: user.admin?,           # privilege flag in payload — token can't be revoked
    exp: 30.days.from_now.to_i    # 30-day window for a leaked token
  }
end
```

```ruby
# Correct — short-lived access + refresh token with rotation
def access_token_for(user)
  JWT.encode(
    { user_id: user.id, exp: 15.minutes.from_now.to_i, jti: SecureRandom.hex },
    Rails.application.credentials.jwt_secret,
    "HS256"
  )
end

# Refresh token — stored server-side (rotated on use)
def refresh_token_for(user)
  raw = SecureRandom.hex(32)
  RefreshToken.create!(user: user, token_digest: Digest::SHA256.hexdigest(raw), expires_at: 14.days.from_now)
  raw  # only the user gets the raw token; DB has the digest
end

# Refresh endpoint
def refresh
  digest = Digest::SHA256.hexdigest(params[:refresh_token])
  rt = RefreshToken.where(token_digest: digest).where("expires_at > ?", Time.current).first
  return head :unauthorized unless rt

  # Rotate: invalidate the old one, issue a new pair
  rt.destroy
  new_access  = access_token_for(rt.user)
  new_refresh = refresh_token_for(rt.user)
  render json: { access_token: new_access, refresh_token: new_refresh }
end
```

**Rules:**
- Access tokens: 5-15 minutes.
- Refresh tokens: 7-14 days, rotated on every use.
- Store refresh tokens as digests, not plaintext.
- Never put secrets, PII, or privilege flags in JWT payloads — they're base64, not encrypted. Anyone with the token can decode.
- Use the `jti` claim + a denylist (Redis or DB) if you need to revoke individual tokens.

### Pattern 7: CORS without wildcards

```ruby
# WRONG
allow do
  origins "*"
  resource "/api/*"
end

# RIGHT
allow do
  origins ENV.fetch("CORS_ORIGINS", "").split(",")
  resource "/api/*",
    headers: :any,
    methods: %i[get post put patch delete options head],
    credentials: false,  # only true if you need browser cookies cross-origin
    max_age: 600
end
```

`*` + `credentials: true` is forbidden by browsers anyway, but `*` + `credentials: false` is still bad: any rogue site can hit your API. As soon as you add an authenticated endpoint, the wildcard lets that site call it with the user's bearer token attached.

### Pattern 8: Rack::Attack for brute-force and rate limits

See `rails-api-design` Pattern 5 for the full config. Minimum:

```ruby
# Throttle login attempts
Rack::Attack.throttle("login/ip", limit: 5, period: 20.seconds) do |req|
  req.ip if req.path == "/login" && req.post?
end

Rack::Attack.throttle("login/email", limit: 5, period: 20.seconds) do |req|
  if req.path == "/login" && req.post?
    req.params.dig("user", "email").presence
  end
end

# Throttle password resets per email
Rack::Attack.throttle("password_reset/email", limit: 3, period: 1.hour) do |req|
  if req.path == "/password_resets" && req.post?
    req.params.dig("user", "email").presence
  end
end

# Block known-bad IPs / patterns
Rack::Attack.blocklist("block bad bots") do |req|
  req.user_agent =~ /known-bad-bot/i
end
```

### Pattern 9: Secure headers (CSP, HSTS, X-Frame-Options)

```ruby
# Gemfile
gem "secure_headers"

# config/initializers/secure_headers.rb
SecureHeaders::Configuration.default do |config|
  config.hsts = "max-age=31536000; includeSubDomains; preload"
  config.x_frame_options = "DENY"
  config.x_content_type_options = "nosniff"
  config.x_xss_protection = "0"  # modern OWASP guidance — legacy XSS auditors had their own vulns; CSP is the real defense
  config.x_download_options = "noopen"
  config.x_permitted_cross_domain_policies = "none"
  config.referrer_policy = "strict-origin-when-cross-origin"

  config.csp = {
    default_src: %w['self'],
    script_src:  %w['self' https://js.stripe.com https://cdn.example.com],
    style_src:   %w['self' 'unsafe-inline' https://fonts.googleapis.com],
    font_src:    %w['self' https://fonts.gstatic.com data:],
    img_src:     %w['self' data: blob: https:],
    connect_src: %w['self' https://api.stripe.com],
    frame_src:   %w['self' https://js.stripe.com],
    object_src:  %w['none'],
    base_uri:    %w['self'],
    form_action: %w['self'],
    upgrade_insecure_requests: true
  }
end
```

**Why CSP matters:** an XSS that injects `<script>` is mostly neutralized if CSP blocks inline scripts. Defense in depth.

**Tune CSP carefully:** start with `csp_report_only` to see violations without blocking, then promote to `csp`.

### Pattern 10: SSRF — user-supplied URLs

**Vulnerable:**

```ruby
def import
  url = params[:url]
  body = Net::HTTP.get(URI(url))  # SSRF — user can hit http://169.254.169.254 (AWS metadata)
  # ...
end
```

**Fix:**

```ruby
require "resolv"

def import
  url = params[:url]
  uri = URI(url)

  # Allow only http/https
  return render(plain: "Invalid scheme", status: :bad_request) unless %w[http https].include?(uri.scheme)

  # Resolve and validate the IP
  begin
    ip = Resolv.getaddress(uri.host)
  rescue Resolv::ResolvError
    return render(plain: "Unknown host", status: :bad_request)
  end

  if IPAddr.new(ip).private? || IPAddr.new(ip).loopback? || IPAddr.new(ip).link_local?
    return render(plain: "Private IP not allowed", status: :forbidden)
  end

  # Use Faraday with a short timeout and no redirect-following
  conn = Faraday.new(url: uri.to_s) do |f|
    f.options.timeout = 5
    f.options.open_timeout = 3
  end
  response = conn.get
  # ...
end
```

**Or use the `lockdown` gem / `dnsmasq` allowlist in the container.** Or restrict the container's network egress entirely if you can.

## Common mistakes to refuse

- Don't `permit!` strong params.
- Don't `skip_before_action :verify_authenticity_token` on a cookie-auth controller.
- Don't disable CSRF with `:null_session` "to fix" errors. Diagnose first.
- Don't commit `master.key` or `*.key` files.
- Don't put secrets in JWT payloads (base64, not encrypted).
- Don't use 30-day JWTs without refresh rotation.
- Don't allow `origins "*"` in CORS for anything that takes auth.
- Don't `Net::HTTP.get(URI(params[:url]))` without IP validation.
- Don't use `MD5` / `SHA1` for password hashing — bcrypt only.
- Don't trust `params[:redirect_to]` without origin allowlist (open redirect).
- Don't skip Brakeman / bundler-audit in CI.
- Don't store credit-card data — let Stripe / Adyen handle it.

## When NOT to use this skill

- The user is asking about a specific compliance requirement (HIPAA, PCI, SOC 2) — those are v0.3 skills.
- The user has a specific vuln to fix — answer directly, link to the relevant pattern.

## See also

- `devise-pundit-rodauth` — auth + authz specifics
- `rails-api-design` — Pattern 5 (rate limiting), CORS configuration
- `solid-queue-and-sidekiq` — jobs shouldn't carry credentials in args
- `observability-baseline` — PII scrubbing in logs and Sentry
- Coming in v0.3: `hipaa-rails`, `pci-dss-rails`, `gdpr-rails`, `soc2-rails`

## Reference files

- [`references/owasp-rails-mapping.md`](references/owasp-rails-mapping.md) — full OWASP Top 10 → Rails defense breakdown

## Sources

- [Rails Guides — Securing Rails Applications](https://guides.rubyonrails.org/security.html) — canonical
- [Brakeman — checks list](https://brakemanscanner.org/docs/checks/)
- [bundler-audit README](https://github.com/rubysec/bundler-audit)
- [secure_headers README](https://github.com/github/secure_headers)
- [rack-attack README](https://github.com/rack/rack-attack)
- [OWASP Top 10 2021](https://owasp.org/Top10/)
- [OWASP Rails Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Ruby_on_Rails_Cheat_Sheet.html)
- [JWT.io — Best Practices](https://datatracker.ietf.org/doc/html/rfc8725)
- [CSP Evaluator](https://csp-evaluator.withgoogle.com/) — sanity check your CSP
- [Stripe — Webhook signing](https://docs.stripe.com/webhooks/signatures)
