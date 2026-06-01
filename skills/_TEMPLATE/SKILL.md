---
name: skill-name-in-kebab-case
description: One sentence on WHAT this skill does AND WHEN it should trigger. Be specific and a little pushy — name the exact user phrases or contexts that should activate it. Example: "Detect and prevent N+1 queries in Ruby on Rails ActiveRecord code. Use whenever the user mentions slow queries, performance issues, Bullet gem, eager loading, N+1, includes/preload/eager_load, or asks why a Rails endpoint is slow. Also use proactively when reviewing any Rails controller action that iterates over a collection and accesses associations."
---

# Skill Title (Human-Readable)

> One-paragraph summary: what problem this solves, who it's for, and the headline opinion. Keep it under 4 sentences.

## Why this matters

Briefly: what does the AI agent get wrong about this topic when no skill is loaded? What does a senior Rails dev wish the agent knew? This is the rationale section — keep it punchy.

## The opinion (if there is one)

State the recommended approach in one sentence. State the counter-position in one sentence. Give the rationale in 2–3 sentences. Example:

> **Use Solid Queue by default in Rails 8+. Use Sidekiq when you have existing Sidekiq investment, need its advanced features (rate limiting, batches), or are not yet on Rails 7.1+.** Solid Queue is database-backed and ships with Rails 8, eliminating Redis as a deployment dependency. Sidekiq remains faster for high-throughput cases and has a richer ecosystem.

## Core patterns

Organize as a sequence of named patterns, each with:
- Name and one-sentence summary
- Before (what the AI agent would naively generate)
- After (what you actually want)
- Why

### Pattern 1: \[Name]

**Before** (typical AI-generated, problematic):
```ruby
# Annotate why this is wrong
```

**After** (Rails-conventional):
```ruby
# Annotate why this is right
```

**Why:** \[2–3 sentences of rationale]

### Pattern 2: \[Name]

\[Same shape]

## Decision matrix (if the skill involves trade-offs)

Use a table for "when to use X vs Y":

| Situation | Use this | Avoid this | Why |
|---|---|---|---|
| | | | |

## Common mistakes to refuse

A bulleted list of things the AI agent should NOT do, with one-line reasons:

- Don't \[X], because \[Y].
- Don't \[X], because \[Y].

## When NOT to use this skill

- One-line cases where this skill doesn't apply or another skill is better

## See also

- `other-skill-in-this-pack` — when it relates
- Coming in v0.2: `future-skill` — for cases this skill doesn't cover yet

---

## Reference files

(Optional — only include if you have `references/` subfiles)

For deeper guidance, the AI should consult:

- `references/<topic>.md` — when \[specific condition]
- `references/<topic>.md` — when \[specific condition]

## Test prompts

(Move to `evals.md` when ready)

1. \[Realistic user prompt that should trigger this skill]
2. \[Another]
3. \[Another]
