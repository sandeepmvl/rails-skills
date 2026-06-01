# Evals for `db-migration-postgres-mysql`

## Prompt 1: "Move to MySQL"
**User:** We have to move from Postgres to MySQL for compliance. Plan?
**Expected:** Audit Postgres-specific features. Dual-write cutover. pgloader for bulk. Trilogy or mysql2 gem.
**Rubric:** [ ] Audit step [ ] Dual-write [ ] pgloader [ ] Gem swap

## Prompt 2: "JSONB queries"
**User:** I use `metadata @> '{"tier":"pro"}'` everywhere. What's the MySQL equivalent?
**Expected:** JSON_CONTAINS in MySQL 8.
**Rubric:** [ ] MySQL function shown

## Prompt 3: "Array columns"
**User:** I have `tag_ids :integer, array: true` on Post. MySQL won't support it.
**Expected:** Join table (post_tags). has_many :tags, through.
**Rubric:** [ ] Join table [ ] Did not suggest serialized text

## Prompt 4: "Why not migrate?"
**User:** Should I just migrate to MySQL because hosting is cheaper?
**Expected:** Honestly: Postgres is the Rails default for a reason. Feature loss is real. Only do it if forced.
**Rubric:** [ ] Honest pushback [ ] Forced-by-constraint framing
