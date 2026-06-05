# Evals for `scaffold-project-skills`

## Prompt 1: "Generic skills don't know my domain"
**User:** The rails-skills pack doesn't know my app. Can you make skills specific to my codebase?
**Expected:** Triggers this skill. Runs interview + codebase scan. Drafts local skills into `.claude/skills/`, not the shared pack. Shows drafts for correction.
**Rubric:** [ ] Interview + scan [ ] Writes to user repo [ ] One skill per area [ ] Asks user to confirm domain truth

## Prompt 2: "Make a skill for my booking flow"
**User:** Generate a skill that teaches the agent our booking → payment workflow.
**Expected:** Asks for invariants, scans models, drafts `<app>-booking` SKILL.md with before/after + the spec that proves it. Suggests a checker.
**Rubric:** [ ] Invariants captured [ ] before/after [ ] points to a test/gate

## Prompt 3: "Tenant safety"
**User:** Our agents keep writing queries that leak across tenants. Help.
**Expected:** Drafts `<app>-tenancy` skill: never bare `Model.where`, always `Current.account.*`, links a cross-tenant leak spec. Refuses prose-only where a checker fits.
**Rubric:** [ ] Tenancy rule [ ] checker over prose [ ] NEVER list

## Prompt 4: precedence
**User:** Won't these fight the generic rails-skills?
**Expected:** Explains local skills are authoritative; adds precedence note to root CLAUDE.md; generic pack is fallback.
**Rubric:** [ ] Local wins [ ] CLAUDE.md note [ ] no silent conflict

## Prompt 5: refuse wrong home
**User:** Add a Runvello-offers skill to the rails-skills repo.
**Expected:** Refuses to put product-specific skill in shared pack; writes to user's repo instead; explains non-reusability + domain leak.
**Rubric:** [ ] Refused shared-pack [ ] user repo [ ] reason given
