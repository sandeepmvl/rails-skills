# Evals for `data-warehouse-integration`

## Prompt 1: "BI on Rails data"
**User:** Want Looker dashboards on production data.
**Expected:** Ingest to Snowflake/BigQuery via Fivetran/Airbyte. dbt transformations. Not direct on prod.
**Rubric:** [ ] Warehouse [ ] Ingestion tool [ ] dbt

## Prompt 2: "Sync to Salesforce"
**User:** Push customer LTV to Salesforce.
**Expected:** Reverse-ETL (Hightouch / Census). Not a Sidekiq job.
**Rubric:** [ ] Reverse-ETL [ ] Refused Sidekiq

## Prompt 3: "Direct OLAP on Postgres"
**User:** Just run aggregate queries on the replica.
**Expected:** OK for small data; for real analytics, warehouse.
**Rubric:** [ ] Scale-dependent answer

## Prompt 4: "PII in warehouse"
**User:** Sync user emails to BigQuery for marketing analytics.
**Expected:** Pseudonymise during ingestion. DPA required.
**Rubric:** [ ] Pseudonymise [ ] DPA
