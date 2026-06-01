# Evals for `redis-streams-rails`

## Prompt 1: "Light Kafka"
**User:** I want event streaming but don't want another broker. We already have Redis.
**Expected:** Redis Streams. Consumer groups. XADD + MAXLEN. XACK. Limits called out.
**Rubric:** [ ] Redis Streams [ ] MAXLEN [ ] Consumer groups

## Prompt 2: "Lost messages on crash"
**User:** Consumer crashed; entries stuck.
**Expected:** PEL + XAUTOCLAIM reaper recurring job.
**Rubric:** [ ] PEL handling [ ] Reaper

## Prompt 3: "Pub/sub vs streams"
**User:** Should I use Redis pub/sub or Streams for events?
**Expected:** Streams — pub/sub has no persistence / consumer groups.
**Rubric:** [ ] Streams over pub/sub

## Prompt 4: "Outgrow point"
**User:** When do I switch to Kafka?
**Expected:** > 50k/sec, long retention, cross-region, schema discipline.
**Rubric:** [ ] Migration triggers
