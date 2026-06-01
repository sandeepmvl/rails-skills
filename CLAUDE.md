# rails-skills — Project Context for Claude Code

You are helping build `rails-skills`: a production-grade pack of Claude Skills for Ruby on Rails developers. When installed, these skills make AI coding agents (Claude Code, Cursor, Codex, Gemini CLI, Windsurf, Antigravity) actually understand Rails conventions and stop generating un-Rails-like code.

## Read these first, in order

1. This file — principles, conventions, quality bar
2. `PLAN.md` — what we're building, in what order, and what we are NOT building
3. `skills/_TEMPLATE/SKILL.md` — the skill template every new skill clones from
4. `skills/00-rails-project-discovery/SKILL.md` — the orchestrator skill (read to understand how skills route to each other)

## What this repo is

A monorepo of independent Claude Skills, each in its own directory under `skills/`. Every skill follows the Anthropic Skills open standard (released December 2025). Skills are portable across Claude Code, Claude.ai, the Claude API, OpenAI Codex, Cursor, Gemini CLI, Antigravity, and Windsurf.

## The canonical SKILL.md format (don't deviate)

```
skill-name/
├── SKILL.md          (required — YAML frontmatter + markdown body)
├── references/       (optional — deeper docs loaded only when needed)
├── scripts/          (optional — executable helpers, e.g. detection scripts)
└── assets/           (optional — code templates, config files)
```

YAML frontmatter is exactly two fields:

```yaml
---
name: skill-name-in-kebab-case
description: One sentence on what it does AND when it should trigger. Be pushy about triggering — Claude tends to undertrigger skills. Example phrasings the user might say go here.
---
```

Body rules:
- **Under 500 lines.** If you're approaching it, push detail into `references/*.md` and link to it.
- **Imperative voice** ("Use `find_by` when..." not "You should consider using `find_by`").
- **Explain *why*, not just *what*.** Senior Rails devs ignore rules without rationale.
- **Examples in before/after form** wherever possible. AI agents learn from examples better than from rules.
- **Reference files have a TOC** if over ~300 lines.

## Project principles (non-negotiable)

1. **Quality per skill > skill count.** Twelve excellent skills beat fifty mediocre ones. Don't pad.
2. **Rails 8 is the default target.** Earlier-version guidance lives in dedicated upgrade skills, not scattered through every skill.
3. **Opinions over options.** Where the Rails community disagrees (service objects, REST vs GraphQL, etc.), state our position clearly with rationale. Mention the counter-position briefly. Don't both-sides everything.
4. **DHH-leaning by default.** Majestic monolith, fat models, server-rendered + Hotwire, Solid Queue over Sidekiq for greenfield. But cover the alternatives in their own skills — many real codebases use them.
5. **No magic claims.** Don't promise "automatically upgrades everything" or "handles infinite scale." Be honest: a skill can guide and accelerate, not replace human judgment on architectural decisions.
6. **Every skill has a before/after example.** No exceptions. AI agents learn faster from worked examples than abstract rules.
7. **Cite Rails edge guides and authoritative gems by version.** "As of Rails 8.0..." not "modern Rails."

## How to add a new skill

1. Copy `skills/_TEMPLATE/` to `skills/<skill-name>/`.
2. Fill in the YAML frontmatter. The description is the most important line in the file — it determines whether the skill ever triggers.
3. Write the body. Stay under 500 lines. Push depth into `references/`.
4. Add at least one before/after code example.
5. Add the skill to the table in `README.md` and to `PLAN.md`'s "Shipped" section.
6. Run the test prompts in `skills/<skill-name>/evals.md` mentally — would a Rails dev get useful, conventional output?

## Quality bar — a skill is ready to ship when

- [ ] Frontmatter description would make Claude/Cursor pick it up for relevant prompts (be pushy — include trigger phrases users would actually say)
- [ ] Body is under 500 lines
- [ ] At least one realistic before/after Rails example
- [ ] Cites specific Rails version, gem versions where relevant
- [ ] States the *why* behind each recommendation
- [ ] Counter-position acknowledged where the community disagrees
- [ ] Linked from README skills table
- [ ] Three test prompts written that a Rails dev would actually type, and the skill produces good output on them

## Current phase

See `PLAN.md` for the live phase status. We are shipping **v0.1** first — twelve focused skills covering the most-felt Rails-with-AI pain points. Don't start v0.2 skills until v0.1 is shipped and launched.

## What this project is NOT

- Not a gem. Don't generate Ruby code that gets `require`d into Rails apps. Skills are markdown + optional helper scripts, consumed by AI agents, not by Rails itself.
- Not a replacement for the Rails Guides. Skills assume the reader knows basic Rails and target the gaps where AI agents go wrong.
- Not a curated awesome-list. We write skills; we don't aggregate links.
- Not a Cursor-only or Claude-only project. Every skill must work across the Skills open standard.
