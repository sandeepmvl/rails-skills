---
name: scaffold-project-skills
description: Generate project-specific Claude Skills for THIS Rails app — interview the codebase (domain models, workflows, multi-tenancy, auth, test + verification loop, branch rules, deploy) and emit starter SKILL.md files under the user's own .claude/skills/ that encode their product's conventions. Use when the user says "create skills for my app", "make project-specific skills", "scaffold local skills", "the generic rails-skills don't know my domain", "teach the agent my codebase conventions", "generate a skill for my <feature>", or wants the agent to learn their app's tenant rules / domain workflows / test gates rather than generic Rails advice.
---

# Scaffold Project-Specific Skills

> The generic `rails-skills` pack teaches an agent how senior Rails devs write Rails. It cannot know *your* product — your tenant isolation rules, your booking/payment workflow, your test-and-verify loop. This skill closes that gap: it interviews your app and generates **local, project-specific skills** that live in your repo and become the source of truth. Use the generic pack as the baseline; use the skills this generates as the authority.

## Why this matters

A general Rails pack steers toward generic "best practice." But your hard parts are domain-specific: which models are tenant-scoped, what a valid Offer looks like, how a draft gets accepted, what your team's verification loop actually is (e.g. inspect → implement → Playwright, not RSpec-first). When those rules live only in people's heads, every AI agent re-derives them — and gets them subtly wrong.

The fix is **local skills**: small, product-aware `SKILL.md` files in your own `.claude/skills/` that encode the conventions that matter to *your* launch. This skill scaffolds them from an interview + a codebase scan, so you start from a real draft instead of a blank file.

## The opinion

> **Keep project-specific skills in your own repo as the source of truth; let the generic pack be the fallback. Generate them from the actual codebase, not a wish-list. One skill per bounded product area (tenancy, a domain workflow, your verification loop) — small and high-signal beats one giant "conventions" file. Encode rules an agent can act on, and prefer a checker (test, lint, gate) over prose wherever a rule can exit 0/1.**

Counter-position: some teams put everything in a single root `CLAUDE.md`. That works for a while, but as one file grows, per-rule attention tends to degrade — the agent honors the top and bottom more reliably than the middle. Splitting into description-gated skills (so only the relevant rules load per task) is more dependable than relying on one long instruction file, regardless of its exact length.

## The interview

Ask these in groups. Skip anything already answered or obvious from the codebase. If the user says "just scan and draft", infer from the repo and present drafts for correction.

### Group 1: Domain (always ask)
1. **What does the app do, in one sentence?** (the ubiquitous language)
2. **Top 3–5 domain concepts that an agent keeps getting wrong?** (e.g. "an Offer must have ≥1 service and a published page")
3. **Which models are tenant-scoped / how is tenancy enforced?** (row-level `account_id`, schema-per-tenant, `acts_as_tenant`, etc.)

### Group 2: Workflows
4. **Name the 2–3 critical workflows** an agent must not break (booking, payment, draft acceptance, provider sync…).
5. **For each: the invariants** — what must always be true before/after?

### Group 3: Process + verification
6. **Your real test loop?** (RSpec / Minitest / system specs / Playwright / manual QA — and when each applies)
7. **What gates a merge?** (green CI, specific checks, branch rules, required reviewer)
8. **When is a failing-test-first required vs optional?** (e.g. required for bug fixes, optional for UI polish)

### Group 4: Guardrails
9. **Things an agent must NEVER do in this repo?** (touch billing without a flag, write to prod, skip tenant scoping…)
10. **Deploy + branch discipline?** (PR-only to main, Kamal, env specifics)

## Codebase scan (run alongside the interview)

Run from the Rails app root. Each command is guarded so a missing path is silent, not an error.

```bash
# Domain models + associations
grep -rl "belongs_to\|has_many" app/models 2>/dev/null | head

# Tenancy signals
grep -rn "acts_as_tenant\|default_scope\|account_id\|tenant_id\|Current\." app/models app/controllers 2>/dev/null | head -30

# Test + verification stack
ls spec test 2>/dev/null; grep -rn "RSpec\|Minitest\|playwright\|capybara" Gemfile Gemfile.lock package.json 2>/dev/null | head

# Existing conventions already written down
ls .claude/skills 2>/dev/null; sed -n '1,40p' CLAUDE.md 2>/dev/null

# Auth + authorization
grep -rl "devise\|pundit\|rodauth\|authorize\|policy" app Gemfile 2>/dev/null | head
```

Use the scan to ground the interview answers in reality — if the user says "everything is tenant-scoped" but `Payout` has no `account_id`, surface that.

## What it generates

Write each skill to the user's **own** repo (default `.claude/skills/<name>/SKILL.md`), NOT into the rails-skills pack. One skill per bounded area. Typical output set:

| Generated skill | Encodes |
|---|---|
| `<app>-tenancy` | how tenant scoping works, which models, the never-skip rule, how to test it |
| `<app>-<workflow>` (one per critical flow) | the steps, invariants, failure modes, the spec that proves it |
| `<app>-verification-loop` | the team's real test/verify process (e.g. inspect → implement → Playwright), what gates a merge |
| `<app>-guardrails` | the NEVER list, branch discipline, deploy rules |
| `<app>-domain-glossary` | the ubiquitous language so the agent uses the right words |

## Generated skill shape

**Before** (what an agent writes with no local skill — generic, wrong for the app):

```ruby
# Agent "helpfully" adds a global query, unaware of tenancy
def index
  @offers = Offer.where(published: true).order(created_at: :desc)
end
```

**After** (what the generated `<app>-tenancy` skill makes the agent write):

```ruby
# Generated skill states: every read is tenant-scoped through Current.account; never Offer.where(...) at top level.
# Preconditions (the generated skill names these): Current.account set in ApplicationController via
# ActiveSupport::CurrentAttributes; Account has_many :offers; Offer defines `published` and `recent` scopes.
def index
  @offers = Current.account.offers.published.recent
end
```

The generated `SKILL.md` itself follows the same 2-field frontmatter + before/after format as this pack:

```markdown
---
name: runvello-tenancy
description: Tenant isolation rules for Runvello. Use whenever generating or reviewing any query, controller, or job that touches account-scoped data (Offers, Bookings, Providers, Payouts). Trigger on any top-level Model.where, new controller action, or background job.
---

# Runvello Tenancy

> Every account-scoped read/write goes through `Current.account`. A bare `Offer.where(...)` is a tenant-leak bug because it queries across every account's rows.

Preconditions: `Current.account` is set per-request in `ApplicationController` (ActiveSupport::CurrentAttributes); account-scoped models are associated off `Account` (`has_many :offers`, `:bookings`, …).

## Never
- Never query an account-scoped model at the class top level. Use the association: `Current.account.bookings` (collection), `Current.account.offers.find_by(slug:)` (single record) — never `Booking.where(...)` or `Offer.find_by(...)`.
- Never trust `params[:account_id]` — derive tenant from the authenticated session.

## How to verify
- `bin/rails test test/tenancy/` (or `bundle exec rspec spec/tenancy/`) — cross-tenant leak tests must stay green. Match your team's test framework.
```

## Workflow

1. Run the interview + codebase scan.
2. Draft one `SKILL.md` per bounded area into `.claude/skills/` (or the tool's local skills dir).
3. **Show each draft to the user for correction** — they own the domain truth, you only drafted it.
4. Add a one-line precedence note to the app's root `CLAUDE.md`: *"Local skills in `.claude/skills/` are authoritative. The generic rails-skills pack is a fallback; project skills win on conflict."*
5. Suggest a checker for any rule that can be one (a tenancy leak spec, a RuboCop cop, a CI gate) and link it from the skill.

## Common mistakes to refuse

- Don't write project-specific skills into the shared `rails-skills` repo — they belong in the user's app repo. They're not reusable and would leak private domain logic.
- Don't generate from assumptions — scan the codebase and confirm with the user. A skill that states a wrong invariant is worse than no skill.
- Don't produce one giant `conventions.md` — split by product area so skills stay description-gated and load only when relevant.
- Don't encode as prose what a checker can enforce. If "no cross-tenant query" can be a spec, write the spec and have the skill point to it.
- Don't impose this pack's RSpec/test-first lean — generate the verification skill from the team's *actual* loop (Minitest, Playwright, manual QA — whatever they really run).
- Don't let generated skills silently contradict the root `CLAUDE.md` — set the precedence note so local skills clearly win.

## When NOT to use this skill

- Greenfield app with no domain yet — install the generic pack first; scaffold local skills once real workflows exist.
- The user wants a *generic* Rails skill (testing, migrations) — that's the rest of this pack, not this generator.

## See also

- `rails-project-discovery` — routes to generic skills; run this after, to add the project-aware layer
- `_TEMPLATE/SKILL.md` — the shape every generated skill follows
- `CLAUDE.md` (project root) — where to record the local-skills-win precedence rule

## Sources

- [Anthropic Agent Skills documentation](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview) — skill format, description-gated discovery, progressive disclosure
- `_TEMPLATE/SKILL.md` + `CLAUDE.md` in this repo — the authoring conventions every generated skill follows
