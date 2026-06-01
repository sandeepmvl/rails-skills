# Evals for `rubocop-and-code-quality`

## Prompt 1: "Set up RuboCop"
**User:** Add RuboCop to my Rails 8 app.
**Expected:** rubocop-rails-omakase as base. CI runs `rubocop --parallel`. Autocorrect workflow described.
**Rubric:** [ ] omakase preset [ ] CI integration [ ] autocorrect workflow

## Prompt 2: "Disable cop"
**User:** RuboCop is complaining about a 60-line method. How do I shut it up?
**Expected:** Push back — usually refactor. If legacy/external constraint, use surgical disable with reason. No `disable all`.
**Rubric:** [ ] Refused blanket disable [ ] Surgical w/ reason [ ] Refactor first

## Prompt 3: "Coverage threshold"
**User:** Want CI to fail if coverage drops.
**Expected:** SimpleCov + minimum_coverage line: 80, branch: 70. enable_coverage :branch. Don't chase 100%.
**Rubric:** [ ] SimpleCov [ ] Branch coverage [ ] Threshold

## Prompt 4: "Add Sorbet"
**User:** Should we add Sorbet for type safety?
**Expected:** Probably not for typical Rails app. Trade-off: RBS lighter; Sorbet for Stripe-scale only.
**Rubric:** [ ] Push back [ ] RBS alternative [ ] Carve-out for very-large codebases

## Prompt 5: "erb_lint?"
**User:** Should we lint our ERB templates?
**Expected:** Yes — ErbSafety catches html_safe/raw XSS sneakers. Setup + autocorrect command.
**Rubric:** [ ] erb_lint [ ] ErbSafety cop [ ] Autocorrect mode
