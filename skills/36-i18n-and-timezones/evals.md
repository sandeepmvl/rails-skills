# Evals for `i18n-and-timezones`

## Prompt 1: "Localize the app"
**User:** Add French support.
**Expected:** locales/en.yml + fr.yml. rails-i18n gem. config.i18n.available_locales. Locale switching middleware.
**Rubric:** [ ] rails-i18n [ ] Locale files [ ] Per-request switching

## Prompt 2: "Time.now bug"
**User:** Reservation times look wrong on the production server.
**Expected:** Time.now uses server TZ. Use Time.current.
**Rubric:** [ ] Time.current [ ] Diagnosed TZ issue

## Prompt 3: "DST scheduling"
**User:** My recurring appointment app books at 2:30am on DST day and it doesn't exist.
**Expected:** Either refuse the slot, or store wall-clock intent and compute UTC per occurrence.
**Rubric:** [ ] DST aware [ ] Strategy offered

## Prompt 4: "+24.hours"
**User:** `Time.current + 24.hours` to get tomorrow.
**Expected:** Use 1.day or tomorrow. DST-aware.
**Rubric:** [ ] 1.day vs 24.hours
