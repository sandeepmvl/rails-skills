# Evals for `actiontext-richtext`

## Prompt 1: "Add WYSIWYG"
**User:** Add a rich text editor for blog posts.
**Expected:** Action Text + Trix. has_rich_text. rich_text_area form helper. ActiveStorage for embedded images.
**Rubric:** [ ] Action Text [ ] has_rich_text [ ] Trix as editor

## Prompt 2: "Search rich text"
**User:** I want to search the rich text body.
**Expected:** to_plain_text in a separate searchable field. Index that, not HTML.
**Rubric:** [ ] to_plain_text [ ] Did not index HTML

## Prompt 3: "TinyMCE instead?"
**User:** Should I use TinyMCE? Trix doesn't have tables.
**Expected:** Trade-off: TinyMCE has more features but larger attack surface + license. Only switch if Trix is genuinely insufficient.
**Rubric:** [ ] Trade-off [ ] Trix-first
