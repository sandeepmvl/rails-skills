# Evals for `vue-with-rails`

## Prompt 1: "Vue setup"
**User:** Set up Vue 3 with my Rails 8 app.
**Expected:** Inertia.js Vue adapter. vite_ruby. Composition API.
**Rubric:** [ ] Inertia adapter [ ] Vite [ ] Composition API

## Prompt 2: "Options API"
**User:** I learned Vue 2 Options API. Continue using it?
**Expected:** Vue 2 EOL. Use Vue 3 Composition API for new code.
**Rubric:** [ ] Vue 2 EOL flagged [ ] Composition API recommended

## Prompt 3: "Pinia"
**User:** Do I need Pinia?
**Expected:** Only for client-only state. Most state belongs server-side via Inertia props.
**Rubric:** [ ] Conservative recommendation [ ] Inertia props as default
