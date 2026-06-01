# Evals for `rails-upgrade-5-to-6`

## Prompt 1: "Rails 5 → 6"
**User:** Rails 5.2 to 6.1. Plan?
**Expected:** Hop 5.2 → 6.0 → 6.1. Zeitwerk transition first.
**Rubric:** [ ] Hop sequence [ ] Zeitwerk transition [ ] Dual-boot

## Prompt 2: "Zeitwerk errors"
**User:** Zeitwerk says `expected OAuth, got Oauth`. Fix?
**Expected:** Add inflection: `Rails.autoloaders.main.inflector.inflect("oauth" => "OAuth")`.
**Rubric:** [ ] Inflection added [ ] Did not rename class

## Prompt 3: "Webpacker mandatory?"
**User:** Rails 6 says Webpacker is default. Do I need it?
**Expected:** No — Sprockets continues. Assess JS needs first. Consider waiting for Rails 7 importmap.
**Rubric:** [ ] Not mandatory [ ] Sprockets stays [ ] Rails 7 path acknowledged
