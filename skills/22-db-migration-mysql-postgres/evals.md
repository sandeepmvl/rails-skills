# Evals for `db-migration-mysql-postgres`

## Prompt 1: "Move to Postgres"
**User:** MySQL to Postgres. How?
**Expected:** pgloader. Casts (tinyint→boolean, datetime→timestamptz). Dual-write cutover. Sequence reset.
**Rubric:** [ ] pgloader [ ] Cast list [ ] Dual-write [ ] Sequence reset

## Prompt 2: "LIKE case sensitivity"
**User:** Our LIKE queries used to match "FOO" against "foo". After Postgres migration they don't.
**Expected:** Postgres LIKE is case-sensitive. Use ILIKE. Audit every LIKE.
**Rubric:** [ ] ILIKE recommended [ ] Audit advised

## Prompt 3: "JSON to JSONB"
**User:** We had JSON columns in MySQL. Should I keep JSON or use JSONB in Postgres?
**Expected:** JSONB. GIN indexable. @>. operators. Conversion migration shown.
**Rubric:** [ ] JSONB chosen [ ] Operator benefit [ ] GIN index
