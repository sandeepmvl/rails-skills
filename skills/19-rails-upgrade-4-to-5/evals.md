# Evals for `rails-upgrade-4-to-5`

## Prompt 1: "Rails 4 → 5"
**User:** Rails 4.2. Want 5.2.
**Expected:** Hop 4.2 → 5.0 → 5.1 → 5.2. ApplicationRecord. Strong params audit.
**Rubric:** [ ] Hops [ ] ApplicationRecord [ ] Params audit

## Prompt 2: "ForbiddenAttributesError"
**User:** After 5.0 upgrade, getting ForbiddenAttributesError on Model.create(params[:user]).
**Expected:** Must use strong params. params.require(:user).permit(...).
**Rubric:** [ ] permit fix [ ] Strong params required

## Prompt 3: "belongs_to nil"
**User:** Post.create fails because author is nil. Worked in Rails 4.
**Expected:** belongs_to is required by default in 5+. Either fix data or `optional: true`.
**Rubric:** [ ] belongs_to required change [ ] optional: true offered
