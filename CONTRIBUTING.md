# Contributing to rails-skills

Thanks for considering a contribution. This guide is short and opinionated, like the skills themselves.

## Before you start

1. Read `CLAUDE.md` (the project context) and `PLAN.md` (the roadmap).
2. Check `PLAN.md` — your idea might already be scheduled for v0.2 or v0.3. If it is, that's the right place to contribute. If it isn't, open an issue *before* writing the skill to discuss scope.
3. v0.1 skills are maintainer-owned to set the quality bar. v0.2+ skills are open for community PRs.

## How to add a new skill

```bash
# 1. Copy the template
cp -r skills/_TEMPLATE skills/your-skill-name

# 2. Fill in SKILL.md per the template
# 3. Run the quality checklist in CLAUDE.md against it
# 4. Add a row to the table in README.md
# 5. Open a PR
```

## What we will reject

- Skills that bundle Ruby code meant to be `require`d. Skills are for AI agents, not Rails apps. Helper scripts in `scripts/` are fine if they're used by the *agent* (e.g. a detection script the AI runs and reads the output of).
- Skills under ~100 lines of body — too thin to be useful.
- Skills over 500 lines of body — push depth into `references/`.
- Skills without at least one before/after code example.
- Both-sides-everything skills. We hold opinions and explain them. We acknowledge the counter-position briefly. We don't write "it depends" essays.
- Skills targeting Rails versions below 5.2 unless they're explicit upgrade-path skills.

## What we'd love

- v0.2 skills from `PLAN.md`. Pick one and claim it on an issue first so we don't duplicate.
- Real before/after examples from your own codebase (sanitized).
- Reference files (`references/*.md`) deepening v0.1 skills.
- Demos and case studies for the README.

## Code of conduct

Be kind. Disagree on technical merit. The Rails community has been around since 2004 and we'd like rails-skills to feel like that, not like an AI hype thread.
