# Evals for `multi-tenancy`

## Prompt 1: "Build a SaaS"
**User:** New project — each customer has their own data, their own users. What's the architecture?
**Expected:** Row-scoped with acts_as_tenant. tenant_id on every owned table. Subdomain resolver. require_tenant = true.
**Rubric:** [ ] Row-scoped [ ] acts_as_tenant [ ] require_tenant [ ] Index on tenant_id

## Prompt 2: "Database per tenant?"
**User:** Should each customer get their own database for security?
**Expected:** Push back unless compliance-driven. Row-scoping is enough for 99% of cases.
**Rubric:** [ ] Refused over-engineering [ ] Compliance carve-out

## Prompt 3: "Background job leaked tenant"
**User:** A SendDigestJob ran and emailed account A's posts to account B's users.
**Expected:** Tenant not set in job. Use ActsAsTenant.with_tenant + pass account_id explicitly.
**Rubric:** [ ] Tenant in jobs [ ] with_tenant block

## Prompt 4: "Apartment gem?"
**User:** Should I use the apartment gem?
**Expected:** No — unmaintained, conflicts with Rails 6+ multi-DB. Use acts_as_tenant.
**Rubric:** [ ] Refused apartment [ ] Recommended alternative
