# Evals for `form-objects-query-objects-presenters`

## Prompt 1: "Signup creates 3 models"
**User:** Signup form creates User + Account + Subscription. Where does the logic go?
**Expected:** Form object with ActiveModel::Model. transaction wrapping the creates. ActiveModel validations.
**Rubric:** [ ] Form object [ ] ActiveModel::Model [ ] Transaction

## Prompt 2: "Filter / sort users"
**User:** Users index has 6 filters and 4 sort options. Where?
**Expected:** Query object. Methods per filter. Composes with policy_scope.
**Rubric:** [ ] Query object [ ] Composable

## Prompt 3: "View formatting bloat"
**User:** My user view has 80 lines of "if admin then red else if..." formatting.
**Expected:** Presenter / decorator. Wrap model. Methods for each display rule.
**Rubric:** [ ] Presenter [ ] Pulls logic from view

## Prompt 4: "Single-model form"
**User:** PostsController#create — should I use a form object?
**Expected:** No. Plain model. Form objects are for multi-model or non-AR fields.
**Rubric:** [ ] Refused over-extraction
