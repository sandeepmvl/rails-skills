---
name: soc2-rails
description: SOC 2 readiness for Rails apps — the 5 Trust Services Criteria (Security, Availability, Processing Integrity, Confidentiality, Privacy), audit log requirements, access reviews, change management, vendor management, the role of compliance vendors (Drata / Vanta / Secureframe), Type I vs Type II reports, SOC 2 vs ISO 27001. Use when the user mentions SOC2, SOC 2, Trust Services, audit, Drata, Vanta, Secureframe, "we need to be SOC 2 compliant", "enterprise customer requires SOC 2", or is preparing for an audit.
---

# SOC 2 for Rails

> SOC 2 is the de-facto enterprise procurement requirement. Most US-based B2B SaaS deals over ~$25k/year now demand a SOC 2 Type II report. Getting compliant is 60% policies + procedures (Drata/Vanta-shaped), 40% engineering. This skill covers the engineering 40%.

## The opinion

> **Adopt a compliance vendor (Drata, Vanta, Secureframe) from day one — DIY SOC 2 is a quagmire. The vendor handles ~80% of evidence collection via integrations. Engineering's job: audit logs that survive deletion, automated access reviews via SCIM, change-management via PR review + CI, vendor inventory, MFA on every privileged surface. Aim for SOC 2 Type II from the start — Type I is a snapshot; Type II covers a period (typically 6-12 months) and is what customers want to see.**

## Trust Services Criteria

SOC 2 is built on the **5 TSCs**. You pick which apply:

| TSC | Required? | What it covers |
|---|---|---|
| **Security** | Always | Access controls, change management, monitoring |
| **Availability** | If you offer uptime SLA | Capacity, backup, BCDR |
| **Processing Integrity** | If you process customer data accurately matters | Data quality, processing correctness |
| **Confidentiality** | If you handle confidential customer data | Encryption, NDA, deletion |
| **Privacy** | If you handle personal data (often paired with GDPR/CCPA) | Consent, retention, breach notification |

Most B2B SaaS: Security + Availability + Confidentiality. Sometimes Privacy.

## Pattern 1: Audit logs that survive

```ruby
# Migration
create_table :audit_events do |t|
  t.references :actor, polymorphic: true, null: true  # user or system
  t.references :target, polymorphic: true, null: false
  t.string :action, null: false  # e.g. "user.login", "order.delete"
  t.jsonb :before_state
  t.jsonb :after_state
  t.string :ip_address
  t.string :user_agent
  t.datetime :created_at, null: false
end
add_index :audit_events, [:target_type, :target_id, :created_at]
add_index :audit_events, [:actor_type, :actor_id, :created_at]
add_index :audit_events, :action
add_index :audit_events, :created_at
```

```ruby
class AuditLogger
  def self.log(actor:, target:, action:, before: nil, after: nil)
    AuditEvent.create!(
      actor: actor,
      target: target,
      action: action,
      before_state: before,
      after_state: after,
      ip_address: Current.ip_address,
      user_agent: Current.user_agent
    )
  end
end
```

**Critical:** audit events do NOT get deleted with their targets. `dependent: :nullify` not `:destroy`.

**Ship to immutable storage:** S3 Object Lock with retention, or CloudWatch Logs with retention. Local audit logs alone aren't auditor-proof.

## Pattern 2: Access reviews (quarterly)

Auditors will ask: "Who has admin access?" "When was access last reviewed?"

```ruby
# app/models/access_review.rb
class AccessReview < ApplicationRecord
  has_many :access_review_entries

  validates :quarter, :reviewer, presence: true
end

class AccessReviewEntry < ApplicationRecord
  belongs_to :access_review
  belongs_to :user
  enum :decision, { keep: 0, revoke: 1, downgrade: 2 }

  validates :role, :decision, presence: true
end
```

Quarterly job lists all privileged users, sends a review request to the team lead, captures the decision.

Drata / Vanta integrate with your IdP (Okta, Google, Azure AD) to automate this. Worth the cost.

## Pattern 3: Change management — PR review + CI

Auditors will ask: "How do you ensure code changes are reviewed?"

Engineering controls:
1. **Protected main branch** — no direct push. Require PR.
2. **Required reviewers** — at least one approval from someone OTHER than the author.
3. **Required CI checks** — green tests before merge.
4. **CODEOWNERS** — sensitive paths require specific reviewer.
5. **Audit trail** — GitHub / GitLab keeps the PR + review history.

```yaml
# .github/CODEOWNERS
# Anything in app/security requires security team review
app/security/*  @company/security
db/migrate/*    @company/dba
config/initializers/*  @company/platform
```

```yaml
# Branch protection (set in GitHub UI or via API)
require_pull_request_reviews: true
required_approving_review_count: 1
require_code_owner_reviews: true
require_status_checks: true
require_signed_commits: true   # optional but auditor-friendly
```

## Pattern 4: Deployment auditing

Auditors will ask: "How do you know what's running in production?"

Tag every deploy with the commit SHA, link to PR, recorded in a deploy log:

```ruby
# config/initializers/version.rb
RELEASE = ENV.fetch("RELEASE_SHA", "dev")
```

Kamal records each deploy with timestamps. Alternative: emit a deploy event to your audit log:

```bash
# In your CI/CD pipeline post-deploy step
curl -X POST $APP_URL/internal/deploys \
  -H "Authorization: Bearer $INTERNAL_TOKEN" \
  -d "{\"sha\":\"$GITHUB_SHA\",\"actor\":\"$GITHUB_ACTOR\",\"pr\":\"$PR_NUMBER\"}"
```

```ruby
class Internal::DeploysController < ActionController::API
  before_action :authenticate_internal!

  def create
    AuditEvent.create!(
      action: "deploy.completed",
      after_state: params.permit(:sha, :actor, :pr).to_h,
      target_type: "Application",
      target_id: 0
    )
    head :created
  end
end
```

## Pattern 5: Vendor inventory

Auditors want a list of every vendor that handles customer data:

```ruby
class Vendor < ApplicationRecord
  enum :category, { hosting: 0, email: 1, monitoring: 2, payments: 3, analytics: 4, support: 5, other: 99 }

  validates :name, :data_types_handled, :region, presence: true
end
```

Drata / Vanta integrate with billing systems (Brex, Ramp, Stripe Billing) to auto-discover vendors. Engineers add the data each one handles.

Each vendor needs:
- Signed DPA / BAA / appropriate contract.
- Documented data they handle.
- Documented sub-processors (e.g., Sentry runs on AWS).

## Pattern 6: MFA on every privileged surface

Required by SOC 2 Security:

- Production console: SSH + MFA (e.g., AWS SSM with MFA).
- Admin UI: 2FA mandatory.
- GitHub: org-wide 2FA enforced.
- Cloud console (AWS, GCP): hardware key required for root.
- Database direct access: VPN + MFA.

```ruby
# config/initializers/devise.rb (with devise-two-factor)
config.warden do |manager|
  manager.failure_app = TwoFactorFailureApp
end
```

For admin users specifically — enforce 2FA via a Warden hook (since `before_create` callbacks cannot actually block sign-in flows):

```ruby
# app/controllers/admin/base_controller.rb
class Admin::BaseController < ApplicationController
  before_action :require_2fa!

  private

  def require_2fa!
    return if current_user&.otp_required_for_login? && current_user.otp_active?
    redirect_to new_two_factor_setup_path, alert: "Admin access requires 2FA."
  end
end
```

With `devise-two-factor`, `otp_required_for_login` is an attribute on the user. Setup flow lives at `Users::TwoFactorSetupController`.

## Pattern 7: Encryption requirements

SOC 2 Confidentiality:
- TLS 1.2+ in transit (HSTS preload).
- AES-256 at rest (RDS / GCS / S3 server-side encryption is fine).
- Application-level encryption for sensitive fields (Active Record Encryption).
- Key rotation procedures (Active Record Encryption supports rotation).

See `rails-security-baseline` for the security baseline.

## Pattern 8: BCDR (Business Continuity / Disaster Recovery)

If you claim Availability TSC:

- RPO (Recovery Point Objective): how much data can you lose? E.g., 1 hour.
- RTO (Recovery Time Objective): how fast can you recover? E.g., 4 hours.
- Test recovery quarterly. Document the test.

```yaml
# Sample DR runbook
backup_strategy:
  database: continuous WAL + daily snapshot to S3 cross-region
  rpo: 5 minutes
  rto: 2 hours
test_schedule: every 90 days
last_tested: 2026-03-15
last_test_result: PASS — 1h47m restore
```

## Pattern 9: Incident response

Auditors will ask: "What happens when you have an incident?"

Documented process:
1. Detection (PagerDuty / Sentry).
2. Triage (severity assignment).
3. Declaration (Slack #incident channel, incident commander assigned).
4. Communication (status page, customer email for major incidents).
5. Resolution.
6. Post-mortem (blameless, action items tracked).

Tools: Incident.io, FireHydrant, Rootly. Built-in templates that produce SOC 2-friendly evidence.

## Pattern 10: Pen testing + vuln scanning

- Annual external penetration test (required for most Trust Services).
- Continuous vuln scanning (Snyk, Dependabot, GitHub Security).
- Triage SLA for vulns:
  - Critical: 7 days
  - High: 30 days
  - Medium: 90 days
  - Low: as scheduled

## Common mistakes to refuse

- Don't DIY SOC 2. Pay for Drata / Vanta / Secureframe — they have control templates already mapped.
- Don't `dependent: :destroy` audit logs.
- Don't skip access reviews. Auditors check.
- Don't deploy from local machines. Pipeline only.
- Don't share admin credentials. Every action must trace to a person.
- Don't ignore failed audit-control evidence. Fix or document the compensating control.

## SOC 2 vs alternatives

| Standard | When |
|---|---|
| **SOC 2 Type II** | US B2B SaaS, default enterprise requirement |
| **ISO 27001** | International / European customers prefer this |
| **HIPAA** | Healthcare-specific; orthogonal |
| **FedRAMP** | US government customers |
| **PCI-DSS** | Card data; orthogonal |
| **SOC 1 Type II** | Financial reporting; usually for accounting / payroll SaaS |

If most customers are EU: ISO 27001 first. If US enterprise: SOC 2 first.

## See also

- `rails-security-baseline` — encryption, secret management
- `hipaa-rails` — overlapping controls
- `gdpr-rails` — privacy TSC
- `observability-rails-advanced` — audit logging, incident response
- `devise-pundit-rodauth` — authentication, MFA, RBAC

## Sources

- [AICPA SOC 2 overview](https://www.aicpa-cima.com/topic/audit-assurance/audit-and-assurance-greater-than-soc-2)
- [Trust Services Criteria](https://us.aicpa.org/content/dam/aicpa/interestareas/frc/assuranceadvisoryservices/downloadabledocuments/trust-services-criteria.pdf)
- [Drata](https://drata.com/) / [Vanta](https://www.vanta.com/) / [Secureframe](https://secureframe.com/)
- [Incident.io](https://incident.io/) / [FireHydrant](https://firehydrant.com/) / [Rootly](https://rootly.com/)
- [Snyk](https://snyk.io/), [Dependabot](https://github.com/dependabot)
- [Github branch protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
