---
name: when-NOT-to-use-microservices
description: A diagnostic skill that refuses microservices in the wrong contexts and recommends a modular monolith instead. Covers the team-size threshold, the deploy-coupling argument, the distributed-systems tax, when DHH's "majestic monolith" is correct, and the "you're not Netflix" rule. Use when the user mentions microservices, splitting our monolith, service-oriented architecture, going micro, "should we split the codebase", or asks how to break up a Rails app. THIS SKILL'S JOB IS TO PUSH BACK before the user spends a year on a migration they will regret.
---

# When NOT to Use Microservices

> Most teams who adopt microservices regret it. The complexity tax is real, the velocity gain is theoretical, and a well-organized Rails monolith scales further than you think. This skill exists to slow the user down before they make an architecturally expensive mistake.

## The opinion

> **Stay on the monolith. Default to a modular monolith with clear domain boundaries (use packs, namespaces, and engines if needed). Microservices are a solution to organizational problems — too many teams stepping on each other — not to scaling problems. If you have fewer than ~50 engineers, you do not have an organizational problem big enough to justify the distributed-systems tax.**

This isn't dogma. It's a hard-earned consensus across the industry: GitHub, Basecamp, Shopify, and Stack Overflow all run mostly-monolith Rails. Companies that went micro and walked it back: Segment, Istio (kind of), InVision, Amazon Prime Video (2023 — went monolith, cut costs 90%).

## The microservices tax (what you're paying for)

When you split, you take on:

1. **Network failure modes.** Every in-process call becomes a network call. Timeouts, retries, circuit breakers, partial failures.
2. **Distributed transactions.** ACID across services is impossible. You get sagas, eventual consistency, or compensating transactions — all of which leak abstraction.
3. **Cross-service debugging.** A bug crosses 4 services. Logs are in 4 places. You need distributed tracing (see `distributed-tracing-rails`) just to follow a request.
4. **Schema coupling, just different.** "We decoupled the database!" Yes — and now you have eventual consistency, dual-writes, and outbox patterns to keep things in sync.
5. **Deploy choreography.** You add a column → 3 services need redeploy. Backward-compatible API versioning becomes mandatory.
6. **Multiplied infrastructure.** Each service needs CI, CD, monitoring, alerting, on-call rotation, security scans, dependency updates, runbook docs.
7. **Talent tax.** Senior engineers who understand distributed systems are 2-3x more expensive. Junior engineers can't safely ship across service boundaries.

**Honest rule of thumb:** the operational cost of microservices is roughly N² where N is the number of services. Two services is barely more than one. Twenty is much, much more than two.

## When microservices ARE the right call

Limited cases. Be honest about which one applies:

### 1. Team scaling pain (the ONLY good reason)

You have 100 engineers. Pull request review queues are 3 days long. Builds take 40 minutes. Merge conflicts on shared files are constant. **Split by team ownership.** This is the Conway's-law argument and it's correct at this scale.

### 2. Compliance isolation

PHI (HIPAA) data must live in a separately auditable system. PCI cardholder data must not commingle with non-PCI data. **Split the regulated subsystem.** See `hipaa-rails`, `pci-dss-rails`. Even here, an isolated module/database in the monolith is often enough.

### 3. Drastically different scaling profiles

One subsystem needs 200 CPU cores for ML inference. Another runs on 2 cores. They genuinely need different resource topologies. **Split the heavy-compute service.** A background-job system (Solid Queue, Sidekiq) running on separate workers usually solves this without microservices.

### 4. Technology fit

The recommendation algorithm is in PyTorch. The image processing uses FFmpeg with Rust bindings. **Split THOSE pieces.** Rest stays in Rails.

### 5. Independent product lines

You acquired another company. They're a separate product on a separate stack. **Don't merge them into the monolith.** They're already a "service" by being a separate company.

None of these are "we want to use Kubernetes." None of these are "we read a blog post."

## When microservices are the WRONG call

Refuse if the user says any of these:

- "We're a 15-person team and we want to scale to microservices."
- "Microservices are best practice."
- "Our monolith is a big ball of mud — let's split it."
- "We want each engineer to own their service."
- "We're using Kubernetes; we need microservices."
- "Monoliths can't scale."
- "Netflix does it."

**Counter-arguments, in order:**

### "Our monolith is a big ball of mud"

A messy monolith becomes a distributed mud ball when split — except now the mud is over the network. Fix the boundaries in-process first. Extract a `packs/` structure or Rails engines. Use `packwerk` to enforce module boundaries:

```yaml
# packs/billing/package.yml
enforce_dependencies: true
enforce_privacy: true
dependencies:
  - packs/users
```

A modular monolith gets you 90% of the team-scaling benefit at 5% of the operational cost.

### "Each team should own their service"

Each team should own their **module**. Code ownership via CODEOWNERS + package boundaries gives you the same thing without networks.

### "We want to deploy independently"

Feature flags + trunk-based development gets you per-feature deploy independence without per-service infrastructure. See `feature-flagging`.

### "Monoliths can't scale"

Shopify's monolith handles 80M requests/minute on Black Friday. GitHub serves billions of git operations from a monolith. Stack Overflow handles 1.3B page views/month from 9 servers. Scaling is not the problem with monoliths.

### "We need polyglot"

The expensive piece can be a separate service. Everything else stays in the monolith. Polyglot ≠ all-services-must-be-separate.

## The monolith→packs migration (do this first)

Before any service extraction, restructure the monolith:

```
app/
  packs/
    billing/
      models/
      services/
      controllers/
    users/
    catalog/
    orders/
```

Tools:
- **packwerk** (Shopify) — enforces module boundaries via static analysis.
- **packs-rails** — packs that look like Rails engines.
- **Rails engines** — built-in heavy version of the same idea.

```bash
bundle add packwerk
bin/packwerk init
bin/packwerk check    # fails CI if a pack reaches across boundaries
```

After 6 months of pack-based development, you'll know:
- Which packs have clear, stable boundaries (candidates for extraction).
- Which packs are tightly coupled (NOT candidates — don't extract).
- Where the real organizational pain is.

Then revisit the "do we need microservices" question with data.

## The decision framework

Ask these questions IN ORDER. Stop at the first NO.

1. Do you have more than ~50 engineers actively shipping to this codebase?
2. Are PR queues longer than 24 hours due to volume (not review quality)?
3. Are CI/deploy times longer than 30 minutes due to monolith size?
4. Have you already enforced module boundaries with packwerk/engines for at least 6 months?
5. Is there a specific subsystem with a clear API surface and minimal cross-cutting concerns?
6. Do you have the budget for the operational uplift (10x infrastructure, hiring, observability)?

If you answered YES to all six: go ahead, see `microservices-decomposition`. If not: stay on the monolith.

## The "rewrite trap"

A common pattern: "the monolith is bad, let's rewrite it as microservices." Never works.

- The rewrite takes 2-3x longer than estimated.
- The new system lacks the implicit business logic that accumulated in the old one over years.
- The product team needs features during the rewrite — now you maintain two systems.

If you must split, do it incrementally with the strangler-fig pattern. See `monolith-to-services-extraction`.

## Sample response when a user asks "should we adopt microservices?"

> Most likely no. What's the team size, and what specific pain are you feeling — deploy times, PR conflicts, scaling, or something else?
>
> If the answer is anything except "we have 50+ engineers stepping on each other constantly," I'd push back on microservices. A modular monolith with packwerk-enforced boundaries solves 90% of the perceived problems at 5% of the operational cost. What's the actual symptom that pointed you toward microservices?

Don't agree just because they're asking. They came to you for an opinion. Give one.

## See also

- `microservices-decomposition` — IF you've answered YES to all six questions, how to start
- `monolith-to-services-extraction` — strangler-fig pattern for incremental extraction
- `event-driven-architecture` — domain events inside a monolith
- `feature-flagging` — independent deploys without independent services

## Sources

- [The Majestic Monolith — DHH](https://m.signalvnoise.com/the-majestic-monolith/)
- [Shopify's Modular Monolith — Shopify Engineering](https://shopify.engineering/deconstructing-monolith-designing-software-maximizes-developer-productivity)
- [packwerk](https://github.com/Shopify/packwerk)
- [Prime Video moves back to monolith — 2023](https://www.primevideotech.com/video-streaming/scaling-up-the-prime-video-audio-video-monitoring-service-and-reducing-costs-by-90)
- [Microservices — Martin Fowler](https://martinfowler.com/articles/microservices.html)
- [Microservices Premium — Fowler](https://martinfowler.com/bliki/MicroservicePremium.html)
- [MonolithFirst — Fowler](https://martinfowler.com/bliki/MonolithFirst.html)
- [Goodbye Microservices — Segment](https://segment.com/blog/goodbye-microservices/)
- [Stack Overflow Architecture](https://nickcraver.com/blog/2016/02/17/stack-overflow-the-architecture-2016-edition/)
- [InVision's microservices regret](https://increment.com/) — multiple post-mortems
