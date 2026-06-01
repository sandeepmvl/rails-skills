---
name: redis-streams-rails
description: Redis Streams (XADD / XREADGROUP / consumer groups) in Rails as a lightweight Kafka — when it fits, the redis-rb client, MAXLEN cap, consumer group semantics, PEL (pending entries list) handling, claiming abandoned entries, when to graduate to Kafka. Use when the user mentions Redis Streams, XADD, XREADGROUP, consumer groups in Redis, "lightweight Kafka", and you already have Redis in the stack and don't want another broker.
---

# Redis Streams

> Redis Streams is the "I already have Redis, give me Kafka-ish semantics without a new operational dependency" option. Good up to medium throughput, single-region, and short retention. Outgrows the pattern at high throughput / long retention — that's Kafka territory.

## The opinion

> **Use Redis Streams when you already run Redis (you almost certainly do) and you need pub/sub-with-history + consumer groups, but don't yet justify Kafka's operational cost. Cap streams with MAXLEN. Use consumer groups with manual acknowledgement. Periodically claim entries idle for > N minutes (PEL handling). Plan to migrate to Kafka if throughput exceeds ~10k events/sec sustained or you need cross-region replication.**

## Why Redis Streams over plain pub/sub

| Feature | Redis pub/sub | Redis Streams |
|---|---|---|
| Persistence | None (drop on publish if no subscriber) | Disk + AOF |
| Replay | None | Yes (read from any offset) |
| Consumer groups | No | Yes |
| Acknowledgement | No | Yes (XACK) |
| Pending tracking | No | Yes (XPENDING) |
| Memory growth | None | Bounded with MAXLEN |

If you need anything beyond fire-and-forget broadcasts: Streams, not pub/sub.

## Setup

```ruby
# Gemfile
gem "redis", "~> 5.0"
gem "connection_pool"  # for thread-safe sharing
```

```ruby
# config/initializers/redis.rb
REDIS_STREAMS = ConnectionPool.new(size: 10, timeout: 5) do
  Redis.new(url: ENV.fetch("REDIS_STREAMS_URL"))
end
```

## Pattern 1: Producing (XADD)

```ruby
class EventPublisher
  STREAM = "orders.events"
  MAX_LEN = 1_000_000  # approximate cap

  def self.publish(event_type:, payload:)
    REDIS_STREAMS.with do |redis|
      redis.xadd(
        STREAM,
        {
          event_type: event_type,
          payload: payload.to_json,
          published_at: Time.current.iso8601
        },
        maxlen: MAX_LEN,
        approximate: true  # ~ trim — Redis trims when convenient, much faster
      )
    end
  end
end

EventPublisher.publish(
  event_type: "order.placed",
  payload: { order_id: 42, account_id: 7, total_cents: 12_500 }
)
```

`approximate: true` enables the `~` flag — Redis trims when convenient, much faster than exact trimming. Omit it (or set to false) for a hard cap.

Always use the outbox pattern in production (see `kafka-rails`) — write to DB + outbox row in one transaction, separate flusher does `XADD`.

## Pattern 2: Creating a consumer group

```ruby
# One-time setup — typically in a migration or boot init.
REDIS_STREAMS.with do |redis|
  redis.xgroup(:create, "orders.events", "order_processor", "$", mkstream: true)
rescue Redis::CommandError => e
  raise unless e.message.start_with?("BUSYGROUP")  # group already exists; safe to ignore
end
```

- `"$"` means "start consuming from now" (skip existing history).
- `"0"` would mean "from the start of the stream."
- `mkstream: true` creates the stream if it doesn't exist yet.

## Pattern 3: Consuming with a consumer group

```ruby
class StreamConsumer
  GROUP = "order_processor"
  STREAM = "orders.events"

  def initialize(consumer_name: SecureRandom.uuid)
    @consumer_name = consumer_name
  end

  def run
    REDIS_STREAMS.with do |redis|
      loop do
        result = redis.xreadgroup(
          GROUP, @consumer_name,
          STREAM, ">",                  # ">" = only new entries (since last delivery)
          count: 10,
          block: 5000                   # block up to 5s waiting for entries
        )
        next if result.empty?

        entries = result[STREAM]
        entries.each do |id, fields|
          process(id, fields)
          redis.xack(STREAM, GROUP, id)
        end
      end
    end
  end

  private

  def process(id, fields)
    payload = JSON.parse(fields["payload"], symbolize_names: true)

    # Idempotency
    return if ProcessedEvent.exists?(stream_id: id)

    ApplicationRecord.transaction do
      ProcessedEvent.create!(stream_id: id)
      # business logic
    end
  rescue StandardError => e
    Rails.error.report(e, context: { stream_id: id, fields: fields })
    raise  # leave in PEL for retry / claim
  end
end

# Run multiple consumer processes — each gets a subset of entries
StreamConsumer.new.run
```

## Pattern 4: Handling abandoned entries (XAUTOCLAIM)

If a consumer crashes after reading but before XACK, the entry sits in the Pending Entries List (PEL). Reclaim entries idle for > N minutes:

```ruby
class StreamReaper
  IDLE_MS = 5 * 60 * 1000  # 5 minutes

  def reap
    REDIS_STREAMS.with do |redis|
      next_id = "0"
      loop do
        result = redis.xautoclaim(
          STREAM, GROUP, "reaper", IDLE_MS, next_id,
          count: 100
        )
        cursor, claimed = result
        break if claimed.empty?

        claimed.each do |id, fields|
          process(id, fields)
          redis.xack(STREAM, GROUP, id)
        end

        next_id = cursor
        break if next_id == "0-0"
      end
    end
  end
end
```

Run XAUTOCLAIM in a recurring job (Solid Queue, every minute). Without it, crashed consumers leak entries.

## Pattern 5: Monitoring PEL depth

```ruby
REDIS_STREAMS.with do |redis|
  pending = redis.xpending(STREAM, GROUP)
  # => [count, smallest_id, largest_id, [[consumer, count], ...]]
  pending_count = pending[0]
end
```

Push `pending_count` to Prometheus / DataDog. Alert if it exceeds threshold — means consumers are crashing or stuck.

## Pattern 6: Stream length management

```ruby
# Trim to a fixed length (exact)
REDIS_STREAMS.with { |redis| redis.xtrim(STREAM, maxlen: 1_000_000) }

# Trim to entries newer than a min-id
REDIS_STREAMS.with do |redis|
  cutoff = "#{(Time.current - 24.hours).to_i * 1000}-0"  # ms-since-epoch + sequence
  redis.xtrim(STREAM, minid: cutoff)
end
```

Always cap streams. Redis memory growth is the #1 production issue.

## Pattern 7: Migration to Kafka

Signs you've outgrown Streams:

- Pending list backs up regularly → throughput too high.
- You need cross-region replication.
- You need > 1 week retention with multiple consumer groups (memory cost is high).
- You need schema evolution discipline.

Migration path:
1. Dual-write to both Streams and Kafka.
2. Move consumers one at a time off Streams onto Kafka.
3. Decommission Streams when all consumers are migrated.

## Common mistakes to refuse

- Don't run streams without MAXLEN. OOM in production is a matter of when, not if.
- Don't use plain Redis pub/sub when you need persistence — use Streams.
- Don't forget to XACK after processing. PEL grows unbounded.
- Don't skip the reaper. Idle pending entries never recover otherwise.
- Don't use Streams as a long-term archive. Cap and offload to S3 / data warehouse.

## When NOT to use Redis Streams

- Long retention (months / years). Use Kafka.
- > 50k events/sec sustained. Redis becomes the bottleneck.
- Complex routing (one publisher, 10+ topologies). RabbitMQ's exchanges are simpler.
- Cross-region multi-master. Redis replication is async; Streams ordering is per-master.

## See also

- `kafka-rails` — when you outgrow Streams
- `rabbitmq-rails` — when routing flexibility matters more than retention
- `solid-queue-and-sidekiq` — for in-app jobs
- `rails-caching-strategy` — Redis is already in the stack

## Sources

- [Redis Streams introduction](https://redis.io/docs/data-types/streams-tutorial/)
- [Redis XADD](https://redis.io/commands/xadd/)
- [Redis XREADGROUP](https://redis.io/commands/xreadgroup/)
- [Redis XAUTOCLAIM](https://redis.io/commands/xautoclaim/)
- [redis-rb client](https://github.com/redis/redis-rb)
- [Antirez on Streams design](http://antirez.com/news/114)
