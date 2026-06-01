# Evals for `rails-upgrade-6-to-7`

## Prompt 1: "Rails 6 → 7"
**User:** We're on Rails 6.0. Want to get to 7.1.
**Expected:** Hop 6.0 → 6.1 → 7.0 → 7.1. Dual-boot. Webpacker migration as separate project.
**Rubric:** [ ] Hop sequence [ ] Dual-boot [ ] Webpacker deferred

## Prompt 2: "Webpacker"
**User:** What do I do about Webpacker?
**Expected:** Decide importmap vs jsbundling based on app. Migrate separately. Shakapacker as legacy escape hatch.
**Rubric:** [ ] Decision matrix [ ] Shakapacker mentioned [ ] Separate project

## Prompt 3: "Hotwire"
**User:** Do I have to rewrite all my jQuery to use Hotwire?
**Expected:** No. Adopt incrementally — new pages get Turbo, old keep jQuery.
**Rubric:** [ ] Incremental adoption [ ] Did not require rewrite
