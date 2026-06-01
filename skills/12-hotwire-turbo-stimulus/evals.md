# Evals for `hotwire-turbo-stimulus`

## Prompt 1: "Inline edit a post title"

**User prompt:**
> I want to let users edit a post title inline on the show page without going to a separate /edit page.

**Expected:**
- Turbo Frame approach.
- Same `dom_id(@post, :title)` frame on show and edit pages.
- Click "Edit" → frame fetches edit, swaps. Submit → frame fetches show, swaps back.
- No React, no JS controller needed.

**Rubric:**
- [ ] Turbo Frame approach
- [ ] Same frame ID
- [ ] No React

---

## Prompt 2: "Real-time notification feed"

**User prompt:**
> Users should see new notifications appear without refresh.

**Expected:**
- `Notification` model with `broadcasts_to :user, inserts_by: :prepend`.
- View has `turbo_stream_from current_user, :notifications`.
- Uses Solid Cable (Rails 8 default).
- Mentions notification model uses after_commit (broadcasts_to does this by default).

**Rubric:**
- [ ] broadcasts_to declared
- [ ] turbo_stream_from in view
- [ ] Solid Cable mentioned

---

## Prompt 3: "Show/hide a form field based on a select"

**User prompt:**
> When the user selects "Other" from a dropdown, show a text field for "specify".

**Expected:**
- Stimulus controller.
- `data-action="change->reveal#toggle"` on the select.
- `data-reveal-target="other"` on the text field.
- No server round-trip.

**Rubric:**
- [ ] Stimulus controller
- [ ] Action + target wired
- [ ] Local-only

---

## Prompt 4: "Add a row to the table after form submit"

**User prompt:**
> User submits a new comment form. The new comment should append to the list without a full page reload.

**Expected:**
- Turbo Stream response.
- `turbo_stream.append "comments", partial: ...` in `create.turbo_stream.erb`.
- Also updates the comment count or new-comment form.
- Controller returns turbo_stream format.

**Rubric:**
- [ ] Turbo Stream append
- [ ] turbo_stream.erb template
- [ ] format.turbo_stream in controller

---

## Prompt 5: "Should I use React for this?"

**User prompt:**
> I want to add a feature where users can drag-and-drop items in a list. Use React?

**Expected:**
- Ask: how complex is the state?
- For simple reorder with persistence: Stimulus + sortablejs (or similar).
- For complex (drag across containers, multi-select, undo/redo): React might be justified.
- Recommends starting with Stimulus and graduating only if needed.

**Rubric:**
- [ ] Did not auto-recommend React
- [ ] Stimulus-first approach
- [ ] Honest about when React earns it

---

## Prompt 6: "Form errors don't show after Turbo submit"

**User prompt:**
> When the form has validation errors, the page reloads but the errors aren't shown.

**Expected:**
- Identifies the missing `status: :unprocessable_entity` on the error render.
- Explains: Turbo only re-renders on 4xx/5xx.
- Returns the form-with-errors with status: :unprocessable_entity.

**Rubric:**
- [ ] Diagnosed the status code issue
- [ ] Fixed with :unprocessable_entity
- [ ] Explained Turbo's behavior
