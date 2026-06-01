# How to use this bootstrap with Claude Code

You now have everything you need to build `rails-skills` with Claude Code as your pair programmer. Here's exactly how to start.

## Step 1: Drop these files into your repo

```bash
cd <your-rails-skills-repo>

# Copy everything from this bootstrap package into your repo root.
# File list:
#   CLAUDE.md             → Claude Code reads this automatically
#   PLAN.md               → the live roadmap
#   README.md             → public-facing, edit your-handle in install commands
#   CONTRIBUTING.md       → PR guidelines
#   LAUNCH.md             → launch checklist
#   HOW_TO_USE.md         → this file (you can delete after reading)
#   skills/00-rails-project-discovery/SKILL.md   → orchestrator, already drafted
#   skills/_TEMPLATE/SKILL.md                    → clone for every new skill

git add .
git commit -m "Bootstrap: project context, plan, orchestrator skill, README"
```

## Step 2: Open Claude Code in the repo

```bash
cd <your-rails-skills-repo>
claude
```

Claude Code reads `CLAUDE.md` automatically. It now knows the project's principles, conventions, quality bar, and roadmap.

## Step 3: Start the first work session

The orchestrator is already drafted. Your first session should polish it and then move to skill #2.

Paste this exact prompt to start:

> Read CLAUDE.md and PLAN.md. The orchestrator skill at skills/00-rails-project-discovery/SKILL.md is drafted but unreviewed. Walk me through it section by section and tell me:
> 1. What's missing
> 2. What's redundant
> 3. Whether the routing table covers the realistic decision space
> 4. Whether the description in the frontmatter is "pushy" enough to trigger reliably
> Then propose edits as a diff. Don't apply them yet — show me first.

After you're happy with the orchestrator, move to skill #2:

> The orchestrator is done. Next is `activerecord-patterns` per PLAN.md skill #2. Following the conventions in CLAUDE.md and the template in skills/_TEMPLATE/SKILL.md, draft skills/activerecord-patterns/SKILL.md. Show me a draft before creating the file. Each pattern needs a real before/after Rails example — invent realistic ones if you have to.

Repeat this loop for skills #3 through #12.

## Step 4: After each skill is drafted

Before committing, run the quality checklist from `CLAUDE.md` against the new skill. Ask Claude Code:

> Run the v0.1 quality checklist from CLAUDE.md against the skill we just drafted. Report each item as pass/fail with a one-sentence reason.

Fix anything that fails, then commit:

```bash
git add skills/<skill-name>
git commit -m "Add <skill-name> skill"
```

## Step 5: Test each skill before declaring it done

Open a separate Rails project (or a scratch directory with the relevant Rails files). Load only that one skill in Claude Code or Cursor, and try the test prompts from the skill's `evals.md`. Does the output look like senior-Rails-dev output? If not, the skill needs more work.

## Step 6: When all 12 v0.1 skills ship

Open `LAUNCH.md` and follow it from T-minus 7 days. Don't skip steps. The launch sequence is what turns 12 good skills into a repo people actually star.

## Pacing

Realistic timing for a Rails dev with a day job:

- **Orchestrator polish:** 1 evening
- **Each of skills 2–12:** 4–8 hours, split across 2 sessions (draft + revise after testing)
- **Total v0.1:** ~80–120 hours of focused work, spread over 4–6 weeks
- **Launch:** 1 prep weekend + 1 launch week

If you do one skill per weekend, you're shipping in 12 weeks. If you do two per week (one weeknight + one weekend), you're shipping in 6 weeks.

## When to come back for help

Ping me (Claude) again when:

- You're stuck on the scope of a specific skill — I'll help narrow it
- A skill's draft is over 500 lines and you need help splitting into `references/`
- You want a review pass on a finished skill before committing
- You're ready to write the launch posts (HN title, RubyWeekly pitch, X thread)
- After day 7 of launch, you want to debrief on what worked and plan v0.2

Good luck. Ship it.
