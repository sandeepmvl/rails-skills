# Evals for `asset-pipeline-propshaft`

## Prompt 1: "Pick asset pipeline"
**User:** Greenfield Rails 8 monolith. Importmap or jsbundling?
**Expected:** Importmap if minor JS. jsbundling for React/Vue islands. vite_ruby for richer SPAs.
**Rubric:** [ ] Decision matrix [ ] Trade-offs

## Prompt 2: "Migrate Sprockets → Propshaft"
**User:** I'm on Sprockets. Should I migrate?
**Expected:** Audit first. .scss.erb / processors don't translate. Separate from Rails version bump. 2-5 days for non-trivial.
**Rubric:** [ ] Audit step [ ] Separate project [ ] Honest about cost

## Prompt 3: "ERB in CSS"
**User:** My current SCSS has `<%= asset_path('icon.svg') %>` in it. How in Propshaft?
**Expected:** Propshaft doesn't preprocess. Use CSS variables, or use cssbundling-rails with a build step.
**Rubric:** [ ] No .scss.erb under Propshaft [ ] Alternative shown
