# Evals for `cdc-debezium-rails`

## Prompt 1: "Stream DB changes"
**User:** I want every change to the posts table streamed to Kafka.
**Expected:** Debezium + Postgres logical replication. REPLICA IDENTITY FULL. Publication / slot.
**Rubric:** [ ] Debezium [ ] wal_level=logical [ ] REPLICA IDENTITY [ ] Publication

## Prompt 2: "CDC for microservices"
**User:** Use CDC to sync data between services.
**Expected:** Push back — exposes schema. Domain events or outbox + CDC.
**Rubric:** [ ] Refused schema coupling [ ] Outbox alt

## Prompt 3: "Replication slot lag"
**User:** Postgres WAL is filling disk.
**Expected:** Check pg_replication_slots; restart connector or drop abandoned slot. Alert.
**Rubric:** [ ] Slot inspection [ ] Drop only abandoned

## Prompt 4: "Initial backfill"
**User:** How to populate search index for existing rows?
**Expected:** Debezium snapshot mode: initial / incremental snapshot.
**Rubric:** [ ] Snapshot mode [ ] Incremental option
