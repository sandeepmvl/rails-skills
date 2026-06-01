---
name: data-warehouse-integration
description: Syncing Rails Postgres to a data warehouse (Snowflake, BigQuery, Redshift) — Fivetran / Airbyte / Hightouch / Stitch / Census / CDC via Debezium, when ELT beats ETL, dbt for transformation, reverse-ETL to push warehouse data back into ops tools, schemas for analytics vs OLTP, when to add columns vs separate tables, PII isolation in the warehouse. Use when the user mentions data warehouse, Snowflake, BigQuery, Redshift, dbt, Fivetran, Airbyte, Hightouch, Census, reverse ETL, "analytics on top of our Rails DB", or wants BI tooling on Rails data.
---

# Data Warehouse Integration

> The Rails Postgres is OLTP — optimized for "fetch one row by ID" + transactional writes. Analytics ("revenue by region by month, with seasonal adjustment") is a different problem. Don't run heavy analytics SQL on production. Replicate to a warehouse.

## The opinion

> **ELT, not ETL: load raw rows to the warehouse, transform there. Use a managed ingestion tool (Fivetran / Airbyte) over hand-rolling sync. Use dbt for transformations and tests. Use reverse-ETL (Hightouch / Census) to push insights back into ops tools. Keep PII out of the warehouse where you can — pseudonymise during ingestion. Use a separate analytics replica for ad-hoc queries to avoid taxing production.**

## Architecture

```
[Rails Postgres OLTP]
       │
       │ ingestion (Fivetran / Airbyte / Debezium)
       ▼
[Warehouse raw schema]      ← raw tables, near 1:1 with source
       │
       │ dbt transformations
       ▼
[Warehouse staging]         ← cleaned, typed, de-duped
       │
       │ dbt
       ▼
[Warehouse marts]           ← business-aligned, dimensional
       │
       │ reverse-ETL (Hightouch / Census)
       ▼
[Ops tools]                 ← Salesforce, HubSpot, Customer.io, Slack
```

## Pattern 1: Pick the ingestion tool

| Tool | When |
|---|---|
| **Fivetran** | Managed, pay-per-row. Many sources. Default for fast time-to-value. |
| **Airbyte** | Open-source. Self-host or cloud. Pay-per-volume. |
| **Stitch** | Mature, simpler than Fivetran. Talend owns it. |
| **Hightouch / Census Pipelines** | Both also do ingestion, but stronger on reverse-ETL. |
| **Debezium CDC + Kafka Connect** | Most flexible. Most operational cost. See `cdc-debezium-rails`. |
| **Custom Sidekiq job** | Don't. You'll regret it within 3 months. |

For most Rails shops: Fivetran or Airbyte until volume hits ~$5k/month, then evaluate Debezium for cost savings.

## Pattern 2: Source connector setup (Fivetran example)

1. Create a read-only Postgres user for Fivetran.
2. Enable logical replication (see `cdc-debezium-rails` — same Postgres setup).
3. In Fivetran UI: add Postgres source → pick schema → pick tables.
4. Set sync frequency: 5 min for "near real time," 1 hour for typical analytics.

Tables you DON'T want in the warehouse:
- `sessions` (PII, low value)
- `pg_search_documents` (re-derivable)
- `audit_events` (might want, but separate retention)
- `outbox_events` (after publish — sync the events themselves elsewhere)

Use Fivetran's table exclusion or `blocklist` patterns.

## Pattern 3: PII handling on ingestion

```sql
-- In dbt, transform on the way into staging:
SELECT
  id,
  account_id,
  -- Pseudonymise email
  MD5(email || '{{ var("pii_salt") }}') AS email_hash,
  -- Drop sensitive
  -- ssn IS NOT EXPOSED HERE
  created_at,
  updated_at
FROM {{ source('rails_app', 'users') }}
```

`pii_salt` is a dbt variable (Snowflake / BigQuery secret). The warehouse never sees raw PII.

For columns you must keep (e.g., name for personalized campaigns): apply column-level encryption in the warehouse, restrict access via RBAC.

## Pattern 4: dbt transformations

```yaml
# dbt_project.yml
models:
  my_warehouse:
    staging:
      +materialized: view
    marts:
      +materialized: table
```

```sql
-- models/staging/stg_orders.sql
WITH source AS (
  SELECT * FROM {{ source('rails_app', 'orders') }}
)
SELECT
  id AS order_id,
  account_id,
  total_cents,
  total_cents::float / 100 AS total_usd,
  created_at AS placed_at,
  status,
  CASE WHEN status = 'paid' THEN 1 ELSE 0 END AS is_paid
FROM source
WHERE _fivetran_deleted = false   -- soft-deletes from Fivetran's metadata
```

```sql
-- models/marts/orders_monthly.sql
SELECT
  DATE_TRUNC('month', placed_at) AS month,
  COUNT(DISTINCT account_id) AS unique_buyers,
  SUM(total_usd) AS revenue,
  AVG(total_usd) AS avg_order_value
FROM {{ ref('stg_orders') }}
WHERE is_paid = 1
GROUP BY 1
ORDER BY 1
```

```yaml
# models/sources.yml (NOT tests/ — dbt scans models/)
sources:
  - name: rails_app
    tables:
      - name: orders
        columns:
          - name: id
            tests: [unique, not_null]
          - name: total_cents
            tests:
              - not_null
              - dbt_utils.accepted_range:
                  min_value: 0
```

Run `dbt build` daily / hourly. Failed tests block downstream materialization.

## Pattern 5: Reverse-ETL

```
Warehouse `marts.high_value_accounts`
       │
       │ Hightouch / Census
       ▼
[Salesforce]  ← updates customer record
[HubSpot]     ← updates lead score
[Customer.io] ← triggers campaign
```

```yaml
# Hightouch sync config
source: snowflake
model: SELECT * FROM marts.high_value_accounts WHERE updated_at > NOW() - INTERVAL '1 day'
destination: salesforce
mapping:
  account_id → External_ID__c
  lifetime_value_usd → LTV__c
  segment → Customer_Segment__c
```

Reverse-ETL eliminates one-off "we need this data in Salesforce" Sidekiq jobs.

## Pattern 6: Schemas — don't pollute Rails with warehouse columns

Rails OLTP tables should reflect business state. Don't add `lifetime_value_usd` to `users` because BI needs it — that lives in the warehouse.

If Rails needs an analytics-derived value:
- Compute it in the warehouse.
- Reverse-ETL into a separate `account_insights` table on Rails.
- Display from `account_insights`, not from `users`.

## Pattern 7: Cost control

Warehouse costs surprise people. Watchpoints:

- **Snowflake** auto-suspend warehouses (1-5 min idle).
- **BigQuery** clustered tables + partitioning + `LIMIT` in dashboards.
- **dbt** `+materialized: incremental` for huge tables instead of full rebuilds.

```sql
-- Incremental dbt model — built from staging, not raw source.
{{ config(materialized='incremental', unique_key='order_id') }}

SELECT * FROM {{ ref('stg_orders') }}
{% if is_incremental() %}
  WHERE updated_at > (SELECT MAX(updated_at) FROM {{ this }})
{% endif %}
```

## Pattern 8: Replicas vs warehouse

A read replica (see `multi-database-and-replicas`) and a warehouse are NOT the same thing:

| | Replica | Warehouse |
|---|---|---|
| Engine | Postgres | Snowflake / BigQuery |
| Query model | OLTP, row-oriented | OLAP, columnar |
| Latency | Real-time | 5min-24h depending on sync |
| Best for | "Show me a user's orders" | "Show me orders by region by month" |

Heavy aggregates → warehouse. Per-user queries → replica.

## Pattern 9: ELT vs ETL

- **ETL** — Extract, Transform on the way, Load. Old-school. Slow. Brittle.
- **ELT** — Extract, Load raw, Transform in the warehouse. Modern. Cheap compute in warehouse.

dbt embodies ELT — transformations live in the warehouse, version-controlled, tested.

## Pattern 10: Don't sync everything

For Postgres, ingestion tools can sync EVERY table. Don't:

- `sessions` — high churn, useless analytically.
- Internal Rails tables (`ar_internal_metadata`, `schema_migrations`).
- Sensitive tables you're not ready to handle in the warehouse (`payment_methods` raw).

Explicit allowlist beats blocklist.

## Common mistakes to refuse

- Don't run analytics SQL on production Postgres. Pages on-call.
- Don't write Sidekiq jobs to sync to a warehouse. Use a managed tool.
- Don't ETL — ELT.
- Don't sync raw PII without pseudonymisation.
- Don't ship "lifetime value" columns back to Rails for ops UI. Put in a separate table.
- Don't ignore dbt tests. They're your data-quality CI.

## When NOT to use a warehouse

- < 1M rows total. Postgres + read replica handles it.
- No analytics team / no dashboards. Don't build a warehouse for future-you.
- The "analytics" you need is "count orders per day" — that's a Postgres query.

## See also

- `multi-database-and-replicas` — replica for read scaling, NOT for warehouse
- `cdc-debezium-rails` — DIY ingestion alternative
- `gdpr-rails` / `hipaa-rails` — PII / PHI handling
- `safe-migrations` — schema changes that warehouse ingestion picks up
- `rails-security-baseline` — DPA with Fivetran / Airbyte etc.

## Sources

- [dbt docs](https://docs.getdbt.com/)
- [Fivetran](https://www.fivetran.com/)
- [Airbyte](https://airbyte.com/)
- [Hightouch](https://hightouch.com/)
- [Census](https://www.getcensus.com/)
- [Snowflake](https://www.snowflake.com/)
- [BigQuery](https://cloud.google.com/bigquery)
- [Modern Data Stack — Tristan Handy / Fishtown / dbt Labs](https://www.getdbt.com/blog/the-modern-data-stack-past-present-and-future)
