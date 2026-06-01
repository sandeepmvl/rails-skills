# Evals for `feature-flagging`

## Prompt 1: "Gradual rollout"
**User:** Want to roll out new dashboard to 10% of users.
**Expected:** Flipper enable_percentage_of_actors. flipper_id on user. Bump percentage over time.
**Rubric:** [ ] Percentage actor [ ] flipper_id [ ] Gradual plan

## Prompt 2: "Flag for permissions"
**User:** Use a flag for admin-only features?
**Expected:** No — that's Pundit. Flags are for runtime feature gating, not authz.
**Rubric:** [ ] Refused flag-as-authz [ ] Pundit pointed to

## Prompt 3: "Old flags"
**User:** I have 30 feature flags from 2024 still in the codebase.
**Expected:** Audit each. Remove fully-rolled-out flags + their code paths. Calendar reminder for new flags.
**Rubric:** [ ] Cleanup recommended [ ] Process for future
