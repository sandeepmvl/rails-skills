# OWASP Top 10 (2021) — Rails Defense Mapping

> The OWASP Top 10 is the industry standard "top vulnerabilities in web apps" list. This file maps each category to the specific Rails defense.

## TOC

- A01 — Broken Access Control
- A02 — Cryptographic Failures
- A03 — Injection
- A04 — Insecure Design
- A05 — Security Misconfiguration
- A06 — Vulnerable and Outdated Components
- A07 — Identification and Authentication Failures
- A08 — Software and Data Integrity Failures
- A09 — Security Logging and Monitoring Failures
- A10 — Server-Side Request Forgery (SSRF)

---

## A01 — Broken Access Control

**The risk:** users can perform actions or access data they shouldn't. The single most common web vulnerability.

**Rails defenses:**

1. **Pundit policies for every controller action.**
   - `authorize @record` raises if denied; readers know auth was checked.
   - `policy_scope(Model)` filters collections — `Model.all` is the bug.

2. **`verify_authorized` / `verify_policy_scoped` after_actions.**
   - Catches missing `authorize` calls at development time.
   - Adds to ApplicationController, exempts `devise_controller?` actions.

3. **Don't trust the URL.**
   - `Project.find(params[:id])` without auth check leaks data via incrementing IDs.
   - Use `current_user.projects.find(params[:id])` to bound the query.

4. **Don't trust client-side hides.**
   - Hiding a delete button in the view doesn't prevent a direct DELETE request. Server enforces.

**Example fix:**

```ruby
# Bad — IDOR
def show
  @order = Order.find(params[:id])
end

# Good
def show
  @order = current_user.orders.find(params[:id])  # 404s if not the user's
  authorize @order
end
```

## A02 — Cryptographic Failures

**The risk:** sensitive data is stored or transmitted insecurely.

**Rails defenses:**

1. **Passwords: bcrypt only.**
   - Devise / Rodauth / has_secure_password use bcrypt by default.
   - Cost factor ≥ 12.
   - Add a `pepper` (app-wide secret) for defense against DB-only leaks.

2. **App secrets: Rails credentials.**
   - AES-256-GCM encryption at rest.
   - Master key in env var, not in repo.

3. **TLS everywhere.**
   - `config.force_ssl = true` in production.
   - HSTS via secure_headers (or `config.ssl_options`).

4. **Database column encryption for PII.**
   - `encrypts :email` (Active Record Encryption, Rails 7+).
   - Deterministic vs non-deterministic mode — pick based on whether you need to query.

5. **Never use MD5 / SHA1 for credentials.**
   - Both broken. Period.

## A03 — Injection

**The risk:** untrusted data is interpreted as code (SQL, OS command, NoSQL, LDAP, XSS).

**Rails defenses:**

1. **SQL: parameterized queries (default in ActiveRecord).**
   ```ruby
   User.where("email = ?", params[:email])           # safe
   User.where(email: params[:email])                 # safe
   User.where("email = '#{params[:email]}'")         # SQL injection
   ```

2. **Order / group / select / pluck — sanitize column names.**
   ```ruby
   # User-provided column name — dangerous:
   Post.order(params[:sort])  # `params[:sort] = "1=1; DROP TABLE posts; --"` is a real risk
   # Allowlist:
   safe_sort = %w[created_at title status].include?(params[:sort]) ? params[:sort] : "created_at"
   Post.order(safe_sort)
   ```

3. **Raw SQL via `execute` / `sanitize_sql`:**
   ```ruby
   ActiveRecord::Base.connection.execute(
     ActiveRecord::Base.sanitize_sql_array(["UPDATE posts SET status = ? WHERE id = ?", "published", id])
   )
   ```

4. **XSS: ERB auto-escapes; `raw` and `.html_safe` are dangerous.**
   ```erb
   <%= @post.title %>           # safe — auto-escaped
   <%= raw @post.title %>       # dangerous if title is user input
   <%= @post.title.html_safe %> # equally dangerous
   ```
   - Use `sanitize` if you need user-provided HTML (e.g. ActionText).
   - CSP (see A05) is the second line.

5. **OS command injection: avoid `system(params[:x])`, `\`#{params[:x]}\``.**
   ```ruby
   system("convert", params[:file])  # array form — safe, args don't get shell-interpreted
   system("convert #{params[:file]}") # shell interp — injection
   ```

## A04 — Insecure Design

**The risk:** the threat model is wrong from the start.

**Rails defenses:**

1. **Think before scaffolding auth.** Who can do what? What happens on password reset? On account deletion?
2. **Default-deny.** New routes deny by default; explicitly grant.
3. **Separation of duties.** Admin actions live in `Admin::` controllers with stricter policies.
4. **Multi-step destructive actions.** `destroy_account` requires re-entering password.

This category is mostly process; Rails alone doesn't fix it.

## A05 — Security Misconfiguration

**The risk:** defaults left dangerous, or production differs from staging.

**Rails defenses:**

1. **secure_headers gem.**
   - HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy.
   - See SKILL.md Pattern 9.

2. **`config.force_ssl = true` in production.**

3. **Disable debug pages in production.**
   - `config.consider_all_requests_local = false` (default in prod).
   - Sentry / Honeybadger for error capture, NOT the better_errors page.

4. **Lock down the Rails console.**
   - Production console access is a credential. Audit who has it.

5. **No default credentials.**
   - No admin/admin, no shipped-with-the-app passwords.

## A06 — Vulnerable and Outdated Components

**Rails defenses:**

1. **bundler-audit in CI.** Fails on known-CVE gems.
2. **Dependabot.** Auto-PRs to bump vulnerable gems.
3. **`bundle outdated` reviewed weekly.** Don't sit on multiple major-version-behind gems.
4. **Rails LTS for legacy apps** (if you can't upgrade off 4.x/5.x) — paid security backports.

## A07 — Identification and Authentication Failures

**Rails defenses:**

1. **Devise / Rodauth defaults.**
   - bcrypt, lockable, confirmable, password complexity.
   - See `devise-pundit-rodauth`.

2. **Session security.**
   - `config.session_store :cookie_store, secure: true, httponly: true, same_site: :lax`
   - `secure: true` requires HTTPS (`force_ssl` covers).
   - `httponly: true` blocks JS access (defense vs XSS).
   - `same_site: :lax` (or `:strict`) blocks CSRF on cross-site requests.

3. **Logout = `reset_session`, never `session[:user_id] = nil`.**

4. **MFA for admin / privileged accounts.**
   - Rodauth's OTP / WebAuthn features.

## A08 — Software and Data Integrity Failures

**Rails defenses:**

1. **Verify webhook signatures.**
   ```ruby
   # Stripe — uses gem helper
   Stripe::Webhook.construct_event(payload, sig_header, secret)

   # GitHub — manual HMAC verification (no gem helper)
   expected = "sha256=" + OpenSSL::HMAC.hexdigest("sha256", secret, payload)
   raise "Bad signature" unless ActiveSupport::SecurityUtils.secure_compare(expected, sig_header.to_s)
   ```

2. **Subresource Integrity for CDN scripts.**
   ```erb
   <script src="https://cdn.example.com/lib.js"
           integrity="sha384-..." crossorigin="anonymous"></script>
   ```

3. **Pin gem sources.** Don't pull from random Git URLs without commit pins.

## A09 — Security Logging and Monitoring Failures

**Rails defenses:**

1. **lograge** for structured logs.
2. **Sentry / Honeybadger / Rollbar** for error tracking.
3. **PII scrubbing.**
   - `Rails.application.config.filter_parameters += [:password, :ssn, :credit_card, :authentication_token]`
   - Same list mirrored in Sentry config.
4. **Alerts on auth-fail spikes.** Brute-force, credential stuffing should page someone.

Full coverage in `observability-baseline`.

## A10 — Server-Side Request Forgery (SSRF)

**Rails defenses:**

1. **Validate user-supplied URLs.** See SKILL.md Pattern 10.
2. **Allowlist destination hosts** for known integrations.
3. **Network-level egress restrictions.** Container can only reach specific outbound IPs.
4. **Avoid `Net::HTTP.get(URI(params[:x]))`.** Always validate the resolved IP before fetching.

---

## Related sources

- [OWASP Top 10 (2021)](https://owasp.org/Top10/)
- [OWASP Ruby on Rails Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Ruby_on_Rails_Cheat_Sheet.html)
- [Rails Security Guide](https://guides.rubyonrails.org/security.html)
- [Active Record Encryption](https://guides.rubyonrails.org/active_record_encryption.html)
