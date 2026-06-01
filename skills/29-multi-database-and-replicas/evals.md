# Evals for `multi-database-and-replicas`

## Prompt 1: "Add a read replica"
**User:** Reads are slow. Add a replica?
**Expected:** Configure primary + primary_replica in database.yml. Use connects_to. Enable automatic role switching. Monitor lag.
**Rubric:** [ ] connects_to [ ] Auto role switching [ ] Lag monitoring

## Prompt 2: "Replica lag bug"
**User:** I create a record then immediately read it; the read shows old data.
**Expected:** Replica lag. Either ensure DatabaseSelector middleware is active (delay), or wrap read in connected_to(role: :writing).
**Rubric:** [ ] Diagnosed lag [ ] DatabaseSelector explained [ ] Manual override option

## Prompt 3: "Should I shard?"
**User:** Should I shard the DB?
**Expected:** Probably not yet. Replica first. Sharding is a last-resort scale-out.
**Rubric:** [ ] Replica-first
