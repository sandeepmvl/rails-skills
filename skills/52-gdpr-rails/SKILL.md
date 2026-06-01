---
name: gdpr-rails
description: GDPR compliance for Rails apps — DSAR (Data Subject Access Request) export, right to erasure, lawful basis, consent management, data minimisation, processor vs controller responsibilities, DPAs with vendors, breach notification within 72 hours, cookie consent (and when you don't need a banner), pseudonymisation vs anonymisation, audit logs that survive erasure. Use when the user mentions GDPR, DSAR, "right to be forgotten", consent banner, cookie law, CCPA, lawful basis, data subject, EU users, data protection.
---

# GDPR for Rails

> GDPR governs personal data of EU residents. The technical asks: let users see, export, correct, and delete their data; record the lawful basis; minimize data collection; notify breaches in 72 hours. This skill is the engineering side — get a privacy lawyer for the legal program.

## The opinion

> **Build a Data Subject portal (export + delete) from day one — bolted on later is painful. Record lawful basis on every personal-data field (consent / contract / legitimate interest). Use pseudonymisation (replace identifiers with reference IDs) for analytics. Audit logs of personal-data access survive erasure. Sign Data Processing Agreements with every vendor handling EU data. Skip the cookie banner if you only use strictly-necessary cookies; otherwise use a consent-management platform (CMP).**

## What's personal data

Anything that identifies a person OR can be combined with other data to do so:
- Name, email, phone, address, DOB
- IP address, device ID, advertising ID, cookies
- Photos, voice recordings
- Account IDs, order history
- Location data
- Behaviour data when linked to a user

If you can answer "is X about a specific person?" with yes (or "with effort"), GDPR applies.

## Pattern 1: Data Subject Access Request (DSAR) export

```ruby
class DataSubjectRequest < ApplicationRecord
  belongs_to :user
  enum :request_type, { export: 0, deletion: 1, correction: 2 }
  enum :status, { pending: 0, in_progress: 1, completed: 2, denied: 3 }

  validates :request_type, presence: true
end
```

```ruby
class DsarExporter
  def initialize(user)
    @user = user
  end

  def call
    {
      account: account_data,
      orders: orders_data,
      activity: activity_data,
      consents: consent_data,
      messages: messages_data
    }
  end

  private

  def account_data
    @user.attributes.except("password_digest", "encrypted_password")
  end

  def orders_data
    @user.orders.map { |o| o.attributes.merge(lines: o.lines.map(&:attributes)) }
  end

  def activity_data
    # GDPR Art. 15 requires the full dataset — no silent truncation.
    AuditLog.where(user: @user).pluck(:action, :ip_address, :created_at)
  end

  def consent_data
    @user.consents.pluck(:purpose, :given_at, :revoked_at)
  end

  def messages_data
    Message.where(from_user: @user).or(Message.where(to_user: @user)).pluck(:subject, :body, :created_at)
  end
end
```

Deliver as a downloadable JSON or CSV bundle. Respond within 30 days (GDPR Art. 12). Build it as a self-service feature so users get the file in seconds.

## Pattern 2: Right to erasure ("right to be forgotten")

Distinguish:

- **Hard delete** — row gone.
- **Anonymise** — keep the row but scrub identifying fields (the row is no longer "personal data").
- **Pseudonymise** — keep the row but replace identifiers with opaque tokens (still personal data; reversible).

For most apps: anonymise. You keep order analytics; the user is gone.

```ruby
class UserErasureService
  def initialize(user)
    @user = user
  end

  def call
    ApplicationRecord.transaction do
      anonymise_user
      anonymise_orders
      scrub_messages
      delete_consents
      record_erasure
    end
  end

  private

  def anonymise_user
    @user.update!(
      email: "erased-#{@user.id}@example.invalid",
      first_name: nil,
      last_name: nil,
      phone: nil,
      birthdate: nil,
      address: nil,
      ip_address: nil,
      erased_at: Time.current
    )
  end

  def anonymise_orders
    @user.orders.find_each do |order|
      order.update!(
        shipping_address: nil,
        billing_address: nil,
        customer_notes: nil
      )
      # Keep order ID, items, amounts — non-personal once names are removed.
    end
  end

  def scrub_messages
    # NOTE: update_all skips AR callbacks + validations. Schema must permit nil on the
    # FK columns and "[redacted]" on body. Audit hooks (if any) must be invoked separately.
    Message.where(from_user_id: @user.id).update_all(from_user_id: nil, body: "[redacted]")
    Message.where(to_user_id: @user.id).update_all(to_user_id: nil, body: "[redacted]")
  end

  def delete_consents
    @user.consents.destroy_all
  end

  def record_erasure
    AuditLog.create!(
      action: "user_erased",
      target_type: "User",
      target_id: @user.id,
      created_at: Time.current
    )
    # Audit log persists; no PII in it.
  end
end
```

**Carve-outs:** GDPR allows retention for legal obligations (tax law: 7 years for invoices in most EU countries), legitimate interests (fraud investigation), public interest. Document each carve-out.

## Pattern 3: Lawful basis registration

Every personal-data field needs a lawful basis:

| Basis | When |
|---|---|
| **Consent** | Marketing emails, optional analytics |
| **Contract** | Email for account login, address for shipping |
| **Legal obligation** | Invoice records for tax law |
| **Vital interest** | Emergency contact info |
| **Public interest** | Government / public-service workflows |
| **Legitimate interest** | Fraud detection, security logs |

```ruby
class Consent < ApplicationRecord
  belongs_to :user
  enum :purpose, { marketing_email: 0, product_analytics: 1, third_party_share: 2 }
  enum :basis, { consent: 0, contract: 1, legitimate_interest: 2 }

  validates :given_at, presence: true
end
```

Record the exact opt-in:
- Timestamp
- IP address
- The exact wording shown
- The version of the privacy policy at the time

Revoking is free (Art. 7): UI for revoking each consent.

## Pattern 4: Consent banner — only when needed

You DON'T need a banner if you only set strictly-necessary cookies:
- Session cookie for auth
- CSRF token
- Load balancer affinity

You DO need a banner if you set:
- Analytics (Google Analytics, Mixpanel, even self-hosted Matomo)
- Advertising / retargeting (Facebook Pixel, Google Ads)
- A/B testing tools
- Functional cookies that go beyond minimal session

Use a consent management platform (CMP): Cookiebot, Osano, Iubenda. They handle:
- Per-purpose granular consent.
- Geographic targeting (only show in EU).
- Storing consent records (legally required to prove consent).

Set cookies AFTER user opts in:

```javascript
// Before opt-in: no analytics scripts loaded.
window.dataLayer = window.dataLayer || []
function gtag() { dataLayer.push(arguments) }

// Only after consent:
if (cookieConsent.granted("analytics")) {
  const script = document.createElement("script")
  script.src = "https://www.googletagmanager.com/gtag/js?id=G-XXX"
  document.head.appendChild(script)
  gtag("config", "G-XXX")
}
```

## Pattern 5: Data Processing Agreement (DPA) with vendors

Every vendor handling EU personal data needs a DPA. Most SaaS vendors have one ready:

- AWS / GCP / Azure
- Stripe
- SendGrid / Postmark / Mailgun
- Sentry / Datadog / New Relic
- Slack / Notion / Zoom
- Intercom / Zendesk

For US-based vendors: check that they participate in the EU-US Data Privacy Framework (replaced Privacy Shield in 2023), or use SCCs (Standard Contractual Clauses).

If a vendor refuses DPA: don't send them EU data.

## Pattern 6: Pseudonymisation for analytics

Don't send raw user emails to your analytics warehouse:

```ruby
# Bad
Snowflake.send_event(user_email: user.email, event: "checkout")

# Good
Snowflake.send_event(user_ref: pseudonymise(user.id), event: "checkout")

def pseudonymise(user_id)
  OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("PSEUDONYM_SALT"), user_id.to_s)
end
```

Pseudonymisation lets you keep analytics while reducing personal-data scope. Still personal data (it's reversible by you), but lower-risk.

## Pattern 7: Breach notification

GDPR Art. 33-34: notify the supervisory authority within 72 hours of becoming aware of a breach.

Engineering hooks:
- Alert on unusual data egress.
- Alert on unauthorized DB access.
- Have a documented incident response process — who declares the breach, who notifies.

When in doubt: report. Failure to report is a bigger fine than the breach itself.

## Pattern 8: Data minimisation

GDPR Art. 5: collect only what you need.

- Optional fields → don't make required.
- Don't ask for DOB if you only need "over 18" — ask "over 18?".
- Don't store full IP — store /24 subnet for fraud analytics.
- Delete data when no longer needed (retention schedule per data type).

Build a retention policy:

```yaml
retention:
  user_accounts: 2 years post-last-login → anonymise
  marketing_consents: until revoked, then 1 year for audit
  audit_logs: 6 years
  failed_logins: 90 days
  password_reset_tokens: 24 hours
```

Cron / Solid Queue recurring jobs implement the policy.

## Pattern 9: International transfer

EU → non-EU data flow needs a legal mechanism:
- EU-US Data Privacy Framework (for US providers in it).
- Standard Contractual Clauses (SCCs).
- Binding Corporate Rules.
- The data subject's explicit consent.

If you host EU-user data, prefer an EU region (eu-west, eu-central). Stripe / AWS / GCP all offer this. Document the region in your privacy policy.

## Common mistakes to refuse

- Don't store data "in case it's useful." Collect only what you need.
- Don't make consent the lawful basis for things that should be Contract (e.g., email for account).
- Don't bundle consents ("by signing up, you agree to marketing"). Separate opt-ins.
- Don't ignore DSARs. 30-day deadline.
- Don't anonymise badly ("user-42" is still personal data if you can map back).
- Don't send analytics events with raw email. Pseudonymise.
- Don't send EU data to non-DPA vendors.
- Don't keep dead users' data forever. Set a retention schedule.

## When NOT to bolt GDPR onto an existing app

- Refactor heavy. Better to bake DSAR + erasure into the data model from the start than reverse-engineer it.
- If you're a B2B SaaS and your customer is the Data Controller: you're the Processor. Your DPA template + their config = compliance. Read GDPR Art. 28.

## See also

- `rails-security-baseline` — TLS, secrets, log filtering
- `devise-pundit-rodauth` — auth, MFA
- `hipaa-rails` — overlapping but distinct
- `observability-baseline` — log filtering for PII
- `solid-queue-and-sidekiq` — recurring jobs for retention enforcement

## Sources

- [GDPR full text](https://gdpr-info.eu/)
- [EDPB guidelines](https://edpb.europa.eu/)
- [ICO (UK)](https://ico.org.uk/)
- [CNIL (France)](https://www.cnil.fr/en)
- [EU-US Data Privacy Framework](https://www.dataprivacyframework.gov/)
- [SCCs (Standard Contractual Clauses)](https://commission.europa.eu/law/law-topic/data-protection/international-dimension-data-protection/standard-contractual-clauses-scc_en)
- [Cookiebot](https://www.cookiebot.com/), [Osano](https://www.osano.com/), [Iubenda](https://www.iubenda.com/)
