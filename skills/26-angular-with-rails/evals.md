# Evals for `angular-with-rails`

## Prompt 1: "Angular setup"
**User:** Angular 17+ with Rails 8. Approach?
**Expected:** Classical API+SPA. Rails-API. Angular standalone. JWT auth. Separate deploy.
**Rubric:** [ ] API+SPA [ ] Standalone [ ] JWT [ ] Separate deploy

## Prompt 2: "Where to store JWT"
**User:** localStorage for the JWT?
**Expected:** Refuse — XSS risk. sessionStorage or httpOnly cookie.
**Rubric:** [ ] Refused localStorage [ ] Alternatives shown

## Prompt 3: "NgRx?"
**User:** Should I add NgRx from the start?
**Expected:** No — use signals first. NgRx only when signals + services prove insufficient.
**Rubric:** [ ] Signals first [ ] NgRx trigger conditions
