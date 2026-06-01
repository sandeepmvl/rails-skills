---
name: hipaa-rails
description: HIPAA compliance for Rails apps handling PHI (Protected Health Information) — Active Record Encryption for PHI at rest, audit logs that survive deletion, access controls (RBAC), Business Associate Agreements (BAAs) with cloud providers, breach detection, the 18 HIPAA identifiers, when NOT to handle PHI in your app. Use when the user mentions HIPAA, PHI, ePHI, medical records, healthcare app, BAA, audit log, Privacy Rule, Security Rule, or asks "can our Rails app store medical info." This skill encodes engineering controls — it does not replace legal counsel.
---

# HIPAA for Rails

> HIPAA is a US law governing how Protected Health Information (PHI) is handled. The technical safeguards (Security Rule) translate to engineering controls in your Rails app. This skill encodes those controls. **It does not replace legal counsel — get a healthcare-attorney-reviewed compliance program before going live with PHI.**

## The opinion

> **Don't build a HIPAA app casually. The compliance burden is real (BAAs with every vendor, audit logs that survive deletion, 6-year retention, breach notification within 60 days). If you can avoid storing PHI by integrating with a covered provider (e.g., Health Gorilla, Akute, Redox, Particle Health), do that instead. If you must store PHI: encrypt at rest with Active Record Encryption, audit-log every PHI access, restrict by role, BAA with AWS / GCP / your DB host, and get a compliance vendor (Drata / Vanta / Compaas) before launch.**

## What's PHI?

The 18 HIPAA identifiers, when combined with health information:

1. Name
2. Address (more specific than state)
3. Dates (birth, admission, discharge — except year)
4. Phone
5. Fax
6. Email
7. SSN
8. Medical record number
9. Health plan beneficiary number
10. Account number
11. Certificate / license number
12. Vehicle ID / VIN
13. Device ID / serial
14. URL
15. IP address
16. Biometric ID (fingerprint, voiceprint)
17. Full-face photo
18. Any other unique identifying number / characteristic / code

Plus: health information itself (diagnoses, treatment, payment for treatment).

PHI in your DB → HIPAA applies.

## Pattern 1: Encrypt PHI at rest

```ruby
# Rails 7+ Active Record Encryption
class Patient < ApplicationRecord
  encrypts :ssn, deterministic: false  # non-deterministic; can't query directly
  encrypts :date_of_birth, deterministic: false
  encrypts :medical_record_number, deterministic: true  # need to look up — deterministic
  encrypts :diagnosis_notes  # default non-deterministic; encrypted blob
end
```

Setup:

```bash
bin/rails db:encryption:init
# Adds active_record_encryption.* to credentials.
```

`bin/rails db:encryption:init` writes three keys into `config/credentials.yml.enc` under the `active_record_encryption` namespace:

```yaml
# config/credentials.yml.enc (decrypted view)
active_record_encryption:
  primary_key: ...
  deterministic_key: ...
  key_derivation_salt: ...
```

Rails reads them from credentials automatically. For key rotation, configure `config.active_record.encryption.key_provider` with a list — see the Rails AR Encryption guide.

**Why both encrypted columns AND encrypted DB volumes:** AR encryption protects against DB dump access. Volume encryption protects against physical access. Both required for defense in depth.

**`deterministic: true` cost:** the same plaintext always encrypts to the same ciphertext (so `where(medical_record_number: x)` works). Trade-off: less secure than non-deterministic. Use only when you must look up by that field.

## Pattern 2: Audit log every PHI access

```ruby
# Migration
create_table :phi_access_logs do |t|
  t.references :user, null: false  # actor
  t.string :resource_type, null: false  # e.g. "Patient"
  t.bigint :resource_id, null: false
  t.string :action, null: false  # view, edit, export, delete
  t.string :reason, null: true  # treatment, payment, operations, etc.
  t.string :ip_address
  t.string :user_agent
  t.datetime :created_at, null: false
end
add_index :phi_access_logs, [:resource_type, :resource_id]
add_index :phi_access_logs, :user_id
add_index :phi_access_logs, :created_at
```

```ruby
class PatientsController < ApplicationController
  def show
    @patient = Patient.find(params[:id])
    PhiAccessLog.create!(
      user: current_user,
      resource_type: "Patient",
      resource_id: @patient.id,
      action: "view",
      reason: params[:reason],  # require a documented reason
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
  end
end
```

**Critical:** audit logs must survive deletion of the source record (HIPAA requires 6-year retention). Don't `dependent: :destroy` audit logs.

Better: write logs to an immutable / append-only system (CloudWatch with retention, S3 with object lock).

## Pattern 3: Minimum necessary access

Only show users the PHI they need for their role:

```ruby
class PatientPolicy < ApplicationPolicy
  def show?
    return true if user.attending_physician?(record)
    return true if user.assigned_nurse?(record)
    return true if user.billing? && record.in_billing_workflow?
    false
  end
end
```

```erb
<!-- Even if authorized, redact what isn't strictly needed for the role -->
<% if policy(@patient).show_full_ssn? %>
  <%= @patient.ssn %>
<% else %>
  <%= "***-**-#{@patient.ssn&.last(4)}" %>
<% end %>
```

## Pattern 4: Session security

```ruby
# config/initializers/session_store.rb
Rails.application.config.session_store :cookie_store,
  key: "_app_session",
  secure: true,
  httponly: true,
  same_site: :strict,
  expire_after: 15.minutes  # HIPAA recommends short timeouts for unattended sessions
```

```ruby
# config/initializers/devise.rb
config.timeout_in = 15.minutes
```

15-minute idle timeout is industry standard for HIPAA portals.

## Pattern 5: Break-glass access logging

Sometimes a non-authorized user MUST access PHI (medical emergency, audit). Build a "break the glass" workflow:

```ruby
class BreakGlassController < ApplicationController
  def create
    @access = BreakGlassAccess.create!(
      user: current_user,
      patient_id: params[:patient_id],
      justification: params[:justification],  # required, recorded
      expires_at: 4.hours.from_now
    )

    # Notify compliance officer immediately
    ComplianceMailer.break_glass_alert(@access).deliver_later

    redirect_to patient_path(@access.patient_id)
  end
end
```

Compliance reviews every break-glass event. Patterns of misuse trigger discipline.

## Pattern 6: Data deletion (Right to deletion is NOT a HIPAA right — but US states vary)

HIPAA does NOT give patients a general right to delete their PHI (the data belongs to the covered entity). Some states do. Build deletion as a workflow:

```ruby
class PatientDeletionRequest < ApplicationRecord
  belongs_to :patient
  belongs_to :requested_by, class_name: "User"

  enum :status, %i[pending under_review approved denied executed]

  def execute!
    transaction do
      # Hard delete or scrub fields — depends on legal requirements
      patient.update!(
        name: "[REDACTED]",
        date_of_birth: nil,
        ssn: nil,
        # ... PHI fields scrubbed
        deleted_at: Time.current
      )
      update!(status: :executed)
    end
  end
end
```

Audit log entries STAY. Only the linked PHI is scrubbed.

## Pattern 7: Vendor BAAs

Every vendor that handles PHI needs a Business Associate Agreement:

- **Cloud host:** AWS / GCP / Azure — all offer BAA-eligible services. NOT every service (some AWS services are not BAA-eligible).
- **Database:** RDS / Cloud SQL — yes via BAA. Heroku Postgres — Heroku Shield only.
- **Email:** Postmark Shield, SendGrid + BAA. Not Mailgun's basic plan.
- **Error tracking:** Sentry with PII scrubbing + BAA OR self-host. Standard Sentry without is non-compliant.
- **Analytics:** Don't send PHI to Google Analytics. Use a self-hosted Matomo or HIPAA-compliant vendor.
- **APM:** Datadog has a HIPAA-eligible tier. New Relic offers FedRAMP-equivalent.

If a vendor refuses to sign a BAA: don't send PHI to them. Period.

## Pattern 8: Logs without PHI

Filter PHI from request logs:

```ruby
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += %i[
  ssn date_of_birth medical_record_number diagnosis
  prescription notes phi
]
```

Set `Rails.logger.level = Logger::WARN` in production. Verbose logging accumulates PHI in log aggregators.

For Sentry: enable `send_default_pii: false` and scrub aggressively. See `rails-security-baseline`.

## Pattern 9: Breach detection

HIPAA requires breach notification within 60 days of discovery. You can only detect breaches if you're monitoring:

- Unusual access patterns (single user reading 1000 patient records).
- Failed login storms (credential stuffing).
- Data exfiltration alerts (egress > N MB to non-corporate IPs).
- Unauthorized configuration changes.

Build alerts via your SIEM (Datadog Cloud SIEM, Splunk, Panther) — see `observability-rails-advanced`.

## Pattern 10: Don't be the covered entity if you can help it

If you can integrate with a HIPAA-compliant provider that holds the PHI:

- **EHR integration:** Health Gorilla, Redox, Particle Health, FHIR APIs.
- **Telehealth video:** Zoom for Healthcare (BAA), Twilio Video + BAA.
- **Documents:** Box Healthcare, Dropbox Business + BAA.
- **Payments:** Stripe (BAA for Stripe Treasury / Identity), Square Healthcare.

Send the absolute minimum into your DB. The less you store, the smaller your compliance burden.

## Common mistakes to refuse

- Don't send PHI to non-BAA vendors (Google Analytics, Mixpanel, Slack channels, Discord).
- Don't store PHI in non-encrypted columns.
- Don't `dependent: :destroy` audit logs.
- Don't use long session timeouts. 15-30 min idle max.
- Don't log unfiltered request params to production.
- Don't claim HIPAA compliance because you encrypted some fields. Compliance is procedural + technical + legal.
- Don't take on PHI to "see what users want" if a vendor already handles it.

## When NOT to build HIPAA in-house

- You're a non-healthcare app that "occasionally" handles PHI (e.g., a CRM that some doctors use). Restrict the workflow to not store PHI.
- You can integrate with an EHR / FHIR provider instead. Do that.
- You're early-stage and PHI isn't the core value. Build the rest first; add PHI later with a compliance vendor.

## See also

- `rails-security-baseline` — XSS, CSRF, secret rotation
- `devise-pundit-rodauth` — authentication, RBAC
- `observability-baseline` — log filtering, error scrubbing
- `gdpr-rails` — separate compliance regime for EU
- `soc2-rails` — overlapping but distinct compliance

## Sources

- [HHS Security Rule](https://www.hhs.gov/hipaa/for-professionals/security/index.html)
- [HHS Privacy Rule](https://www.hhs.gov/hipaa/for-professionals/privacy/index.html)
- [NIST 800-66 (HIPAA Security)](https://csrc.nist.gov/pubs/sp/800/66/r2/final)
- [Rails Active Record Encryption](https://guides.rubyonrails.org/active_record_encryption.html)
- [AWS HIPAA Eligible Services](https://aws.amazon.com/compliance/hipaa-eligible-services-reference/)
- [Drata](https://drata.com/), [Vanta](https://www.vanta.com/), [Compaas](https://compaas.io/) — compliance automation
- [Health Gorilla](https://www.healthgorilla.com/), [Redox](https://www.redoxengine.com/) — EHR integration
