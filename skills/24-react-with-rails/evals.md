# Evals for `react-with-rails`

## Prompt 1: "React with Rails"
**User:** I want to use React with my Rails app. What's the setup?
**Expected:** Inertia.js as default. vite_ruby or jsbundling-rails. Mention classical API+SPA when justified.
**Rubric:** [ ] Inertia recommended [ ] Bundler covered [ ] Trade-off

## Prompt 2: "Tiny interactivity"
**User:** Just need a date picker. Add React?
**Expected:** No. Stimulus + library. React overkill.
**Rubric:** [ ] Refused React [ ] Stimulus path

## Prompt 3: "Separate frontend"
**User:** Should I split my SPA and API into separate repos?
**Expected:** Only if multi-client, separate teams, separate deploy cadence. Otherwise Inertia.
**Rubric:** [ ] Triggers for split [ ] Inertia as default
