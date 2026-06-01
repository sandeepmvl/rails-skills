# Evals for `rails-upgrade-3-to-4`

## Prompt 1: "Rails 3 → 4"
**User:** Rails 3.2. How to upgrade?
**Expected:** Hop 3.2 → 4.0 → 4.1 → 4.2. Ruby 2.0+. attr_accessible bridging.
**Rubric:** [ ] Hops [ ] Ruby version [ ] attr_accessible plan

## Prompt 2: "attr_accessible"
**User:** Rails 4 doesn't have attr_accessible. Remove it all?
**Expected:** Use protected_attributes_continued as bridge. Migrate to strong params over time.
**Rubric:** [ ] Bridge gem [ ] Strong params as endpoint

## Prompt 3: "Turbolinks broke my JS"
**User:** After 4.0 upgrade, my jQuery code doesn't run on page changes.
**Expected:** Turbolinks intercepts navigation. Listen for `page:load` + `ready`. Or disable per-link.
**Rubric:** [ ] Page:load event [ ] data-no-turbolink option
