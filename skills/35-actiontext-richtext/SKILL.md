---
name: actiontext-richtext
description: Action Text (rich text) in Rails 8 — Trix editor integration, has_rich_text on models, Active Storage for embedded attachments, the safe-list of HTML tags, custom embeds via attachable mixin, server-side sanitization, XSS prevention, search indexing of plain text. Use when the user mentions Action Text, Trix, rich text editor, has_rich_text, WYSIWYG, formatted text content, embedded images, or asks how to add a rich text editor to Rails.
---

# ActionText (Rich Text)

> Add rich text editing to Rails models. Trix editor + ActionText + ActiveStorage handle the editor, storage, and embedded attachments. Default Rails 8 has decent defaults — the gotchas are around sanitization, search indexing, and custom embeds.

## The opinion

> **`has_rich_text :body` on the model. Trix is the default editor — fine for most cases. Sanitize on output (Rails does by default). Index the plain-text representation, not the HTML. For custom embeds (mentions, polls), use ActionText's attachable mixin. Don't migrate to TinyMCE/CKEditor unless you have a specific need — Trix's smaller surface area is a security win.**

Counter-positions:
- **TinyMCE / CKEditor / Tiptap** — more powerful editors. Larger XSS attack surface, separate licensing. Pick only if Trix is genuinely insufficient.

## Setup

```bash
bin/rails action_text:install
bin/rails db:migrate
```

Creates `action_text_rich_texts` and `active_storage_blobs/attachments` tables.

## Core patterns

### Pattern 1: Model + form

```ruby
class Post < ApplicationRecord
  has_rich_text :body
end
```

```erb
<%= form.label :body %>
<%= form.rich_text_area :body %>
```

```erb
<!-- View -->
<%= @post.body %>  <!-- Renders the rendered Trix HTML, sanitized -->
```

### Pattern 2: Sanitization (the default + custom)

Rails sanitizes ActionText output by default. The allowed tags include common formatting (`<strong>`, `<em>`, `<h1-6>`, `<a>`, `<img>`, etc.) — see `Rails::Html::SafeListSanitizer` for the exact list.

To restrict further:

```ruby
# config/initializers/action_text.rb
ActionText::ContentHelper.allowed_tags -= %w[h1 h2]
```

To allow more (carefully):

```ruby
ActionText::ContentHelper.allowed_tags += %w[mark]
```

**Anti-pattern:** allowing `<script>` (even by mistake). The default safe-list excludes it; never add.

### Pattern 3: Embedded attachments

Trix supports drag-and-drop image upload. ActionText wires it to ActiveStorage automatically.

```ruby
# Variant configured on the attachment association (Rails 7.1+):
class Post < ApplicationRecord
  has_rich_text :body
end

# config/application.rb — variant pipeline (libvips by default in Rails 7+)
# Rails.application.config.active_storage.variant_processor = :vips
```

For the editor preview specifically, ActionText resizes embedded images automatically; you don't need to declare a variant unless you want a non-default size for `<%= image_tag attachment.representation(resize_to_limit: [800, 800]) %>` in your views.

The HTML stored includes `<action-text-attachment>` tags pointing at the blob.

### Pattern 4: Custom attachables (mentions, polls)

Beyond images:

```ruby
class User < ApplicationRecord
  include ActionText::Attachable

  # Define how the user renders inside rich text
  def to_trix_content_attachment_partial_path
    "users/mention"
  end
end
```

```erb
<!-- app/views/users/_mention.html.erb -->
<a href="<%= user_path(user) %>" class="mention">@<%= user.username %></a>
```

```ruby
# In Trix client-side JS, you'd implement an @-completion that calls:
post.body.body.attachables.append(User.find(id))
```

This pattern is how Basecamp's hey.com handles inline mentions and pinned messages — see signal-v-noise blog posts.

### Pattern 5: Plain-text indexing (search)

Rich-text HTML stored in `body` is hard to search. ActionText auto-stores a plain-text version:

```ruby
post.body.to_plain_text  # "Hello, world!"
```

For search:

```ruby
class Post < ApplicationRecord
  has_rich_text :body

  # If using pg_search:
  include PgSearch::Model
  multisearchable against: [:title, :body_plain]

  def body_plain
    body.to_plain_text
  end
end
```

See `rails-search` for full search patterns.

### Pattern 6: Testing

```ruby
RSpec.describe Post, type: :model do
  it "stores rich text body" do
    post = create(:post, body: "<strong>Hello</strong>")
    expect(post.body.to_plain_text).to eq("Hello")
    expect(post.body.to_s).to include("<strong>")
  end

  it "sanitizes script tags" do
    post = create(:post, body: "<script>alert(1)</script>Hello")
    expect(post.body.to_s).not_to include("<script>")
    expect(post.body.to_plain_text).to include("Hello")
  end
end
```

```ruby
# System spec — Trix interaction
RSpec.describe "Editing a post", type: :system, js: true do
  it "allows rich text input" do
    sign_in user
    visit edit_post_path(post)
    fill_in_rich_text_area "post_body", with: "Hello world"
    click_button "Update"
    expect(page).to have_content("Hello world")
  end
end
```

`fill_in_rich_text_area` is ActionText's Capybara helper (loaded by `action_text/system_test_helper`).

### Pattern 7: Migrating off serialize text columns

```ruby
# Old: posts.body :text — plain or HTML stored raw
# New: ActionText

# Migration — assign the legacy column value to the has_rich_text `:body` setter.
# Read the legacy raw column via the table BEFORE has_rich_text was wired up.
class MigratePostBodyToActionText < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    legacy_rows = ActiveRecord::Base.connection.select_all("SELECT id, legacy_body FROM posts WHERE legacy_body IS NOT NULL")
    legacy_rows.each do |row|
      post = Post.find(row["id"])
      post.update!(body: row["legacy_body"])  # routes to ActionText via has_rich_text
    end
  end
end
```

For non-trivial migrations, do this in a background job, not a migration. See `safe-migrations`.

## Common mistakes to refuse

- Don't allow `<script>` in the safe-list. XSS.
- Don't accept user-provided CSS / HTML attributes (`style`, `onclick`) — Rails strips them by default; don't override.
- Don't search against HTML — search against plain text via `to_plain_text`.
- Don't store rich text in the same `text` column as your old plain text. Migrate.
- Don't switch to TinyMCE / CKEditor without a justification — Trix's smaller surface is a security win.

## When NOT to use this skill

- The user needs Markdown (not WYSIWYG) — use a separate Markdown gem (kramdown, commonmarker).
- The user needs collaborative editing — out of scope; use Liveblocks / Yjs.

## See also

- `activestorage-uploads` — for the embedded attachment storage
- `rails-search` — indexing the plain-text body
- `rails-security-baseline` — XSS / sanitization

## Sources

- [Rails Guides — Action Text Overview](https://guides.rubyonrails.org/action_text_overview.html)
- [Trix editor](https://trix-editor.org/)
- [ActionText API](https://api.rubyonrails.org/classes/ActionText.html)
- [Sanitization safe-list](https://api.rubyonrails.org/classes/Rails/Html/SafeListSanitizer.html)
- [DHH on Trix](https://signalvnoise.com/) — design rationale
- [pg_search](https://github.com/Casecommons/pg_search)
- [TinyMCE Rails (counter-position)](https://github.com/spohlenz/tinymce-rails)
