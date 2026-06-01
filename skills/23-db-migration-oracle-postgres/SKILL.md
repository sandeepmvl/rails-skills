---
name: db-migration-oracle-postgres
description: Migrate a Ruby on Rails application from Oracle Database to PostgreSQL — schema differences (NUMBER to BIGINT/DECIMAL, VARCHAR2 to VARCHAR, CLOB/BLOB to TEXT/BYTEA, sequences, ROWID, hierarchical queries, PL/SQL packages), Oracle Enhanced adapter to pg gem, data migration via ora2pg, the dual-write cutover. Use when leaving Oracle for Postgres, the user mentions ora2pg, Oracle Enhanced adapter, NUMBER columns, VARCHAR2, sequences, ROWNUM, CONNECT BY, or asks how to escape Oracle.
---

# Oracle → Postgres Migration

> Oracle to Postgres is a license-cost play more than a feature-set play. Most things move cleanly via `ora2pg`. The big risks are PL/SQL business logic in the database (Postgres has PL/pgSQL; not a direct translation), hierarchical queries (`CONNECT BY` → `WITH RECURSIVE`), and Oracle-specific feature dependencies.

## The opinion

> **Use `ora2pg` for schema + data conversion. Audit every PL/SQL package, trigger, and view — these don't translate automatically. Dual-write cutover for non-trivial apps. Switch from `activerecord-oracle_enhanced-adapter` to `pg`. Expect 4-12 weeks for a non-trivial enterprise app.**

## Pre-migration audit

```bash
# What lives in Oracle that isn't ActiveRecord SQL?
sqlplus user/pass@db <<EOF
  SELECT object_type, COUNT(*) FROM user_objects GROUP BY object_type;
  SELECT name FROM user_source WHERE type = 'PACKAGE';
EOF
```

| Oracle feature | Postgres equivalent | Translation |
|---|---|---|
| `NUMBER` (precision varies) | `BIGINT`, `INTEGER`, `DECIMAL(p,s)` | Per-column decision based on usage |
| `VARCHAR2(n)` | `VARCHAR(n)` | Direct |
| `CLOB` / `BLOB` | `TEXT` / `BYTEA` | Direct |
| `DATE` (with time) | `TIMESTAMPTZ` | Watch timezone semantics |
| `SEQUENCE`s | Sequences (also true sequences in PG) | Direct |
| `ROWID` | `ctid` (ephemeral) or surrogate `id` | Usually means "stop relying on ROWID" |
| `ROWNUM` | `LIMIT` / `ROW_NUMBER() OVER (...)` | Direct rewrite |
| `CONNECT BY ... START WITH` | `WITH RECURSIVE` | Manual rewrite |
| PL/SQL packages | PL/pgSQL functions | Manual port — biggest risk |
| Triggers | Triggers | Mostly direct; syntax differs |
| Materialized views | Materialized views | Direct |
| `NVL(x, y)` | `COALESCE(x, y)` | Direct |
| `SYSDATE` | `NOW()` / `CURRENT_TIMESTAMP` | Direct |
| `DBMS_*` packages | None (rewrite to app code or PG extension) | Per-package decision |

## Core patterns

### Pattern 1: ora2pg for schema + data

```bash
# Install
brew install ora2pg

# Generate config
ora2pg --project_base /path/to/migration --init_project myapp

# Schema export
ora2pg -t TABLE -o schema.sql
ora2pg -t SEQUENCE -o sequences.sql
ora2pg -t INDEX -o indexes.sql
ora2pg -t FUNCTION -o functions.sql
ora2pg -t PACKAGE -o packages.sql  # AUDIT THIS BY HAND

# Data export
ora2pg -t COPY -o data.sql  # COPY format, faster than INSERT
```

Apply to Postgres:

```bash
psql myapp_postgres -f schema.sql
psql myapp_postgres -f sequences.sql
psql myapp_postgres -f data.sql
psql myapp_postgres -f indexes.sql  # indexes AFTER data for speed
```

### Pattern 2: PL/SQL → PL/pgSQL — manual port

```sql
-- Oracle PL/SQL package
CREATE OR REPLACE PACKAGE order_pkg AS
  FUNCTION calculate_total(p_order_id NUMBER) RETURN NUMBER;
END;

-- Postgres PL/pgSQL function
CREATE OR REPLACE FUNCTION calculate_total(p_order_id BIGINT) RETURNS NUMERIC AS $$
DECLARE
  v_total NUMERIC;
BEGIN
  SELECT SUM(price * quantity) INTO v_total
    FROM line_items WHERE order_id = p_order_id;
  RETURN COALESCE(v_total, 0);
END;
$$ LANGUAGE plpgsql;
```

**Better question:** does the logic NEED to be in the DB? Many Oracle apps push business logic into PL/SQL because Oracle made it cheap. In Rails, the same logic in Ruby is testable, debuggable, version-controlled. **Migrate logic to Ruby when you can.**

### Pattern 3: Hierarchical queries

```sql
-- Oracle CONNECT BY
SELECT employee_id, manager_id, LEVEL
  FROM employees
  START WITH manager_id IS NULL
  CONNECT BY PRIOR employee_id = manager_id;

-- Postgres WITH RECURSIVE
WITH RECURSIVE org AS (
  SELECT employee_id, manager_id, 1 AS level
    FROM employees WHERE manager_id IS NULL
  UNION ALL
  SELECT e.employee_id, e.manager_id, o.level + 1
    FROM employees e
    JOIN org o ON e.manager_id = o.employee_id
)
SELECT * FROM org;
```

### Pattern 4: Gem swap

```ruby
# Gemfile — before
gem "activerecord-oracle_enhanced-adapter"
gem "ruby-oci8"

# After
gem "pg"
```

```yaml
# config/database.yml
production:
  adapter: postgresql
  encoding: unicode
  database: myapp_production
  username: ...
  password: ...
  host: ...
```

### Pattern 5: Dual-write cutover

Same shape as Postgres → MySQL Pattern 2. Set Postgres as secondary, dual-write, verify, swap primary.

For Oracle specifically, the verification step is critical — Oracle's number handling (precision, scale) can produce subtly different results than Postgres' NUMERIC for arithmetic-heavy workloads.

## Common mistakes to refuse

- Don't try to port PL/SQL packages automatically. Read each one, decide: port to PL/pgSQL or migrate to Ruby.
- Don't run ora2pg in production with writes happening — data drift.
- Don't keep `ROWID`-dependent queries. Add a real PK if missing.
- Don't blindly trust ora2pg's casts for NUMBER — audit precision/scale per column.
- Don't migrate Oracle CDC streams (Streams / GoldenGate) directly — use Postgres logical replication or Debezium.

## See also

- `db-migration-postgres-mysql` — different pair
- `safe-migrations` — schema changes during cutover
- Coming in v0.3: `cdc-debezium-rails` — for Oracle-CDC users

## Sources

- [ora2pg docs](https://ora2pg.darold.net/)
- [Postgres recursive queries](https://www.postgresql.org/docs/current/queries-with.html)
- [activerecord-oracle_enhanced-adapter](https://github.com/rsim/oracle-enhanced)
- [pg gem](https://github.com/ged/ruby-pg)
- [PL/pgSQL reference](https://www.postgresql.org/docs/current/plpgsql.html)
- [Oracle to Postgres migration playbooks](https://wiki.postgresql.org/wiki/Oracle_to_Postgres_Conversion)
