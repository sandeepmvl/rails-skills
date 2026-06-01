# Evals for `db-migration-oracle-postgres`

## Prompt 1: "Leaving Oracle"
**User:** We want off Oracle. Postgres target. Plan?
**Expected:** Audit PL/SQL packages, triggers, views first. ora2pg for bulk. Dual-write cutover.
**Rubric:** [ ] Audit first [ ] ora2pg [ ] Dual-write

## Prompt 2: "Hierarchical query"
**User:** I have `CONNECT BY PRIOR employee_id = manager_id`. Postgres equivalent?
**Expected:** WITH RECURSIVE CTE. Sample query.
**Rubric:** [ ] WITH RECURSIVE [ ] Direct rewrite

## Prompt 3: "PL/SQL packages"
**User:** I have 30 PL/SQL packages. ora2pg auto-converts them?
**Expected:** No — manual port. Better question: do they need to be in DB? Consider migrating to Ruby.
**Rubric:** [ ] Manual port required [ ] Ruby-migration considered [ ] Did not auto-convert
