---
name: hotwire-turbo-stimulus
description: Hotwire (Turbo + Stimulus) — the Rails 8 default UI stack. Turbo Drive for navigation, Turbo Frames for lazy HTML islands, Turbo Streams for server-pushed updates over WebSocket or response body, Stimulus controllers for the JS sprinkles layer, morph updates (idiomorph), Action Cable broadcasting from models and jobs. Use when building or reviewing Rails 8 UI, the user mentions Turbo, Stimulus, Hotwire, turbo_frame_tag, turbo_stream, broadcasts_to, turbo-frame, data-controller, morphdom, idiomorph, or asks how to add reactivity without React/Vue. Use proactively whenever the AI is about to suggest a React component for something Hotwire can do.
---

# Hotwire: Turbo + Stimulus

> Build reactive Rails UIs without a JS framework. AI agents reach for React on every interactive feature — they grew up on SPAs and don't know that Hotwire covers ~90% of the same ground with server-rendered HTML. This skill encodes when Hotwire wins, what each Turbo primitive does, and how Stimulus fits.

## Why this matters

Adding React/Vue to a Rails app means: a build pipeline, a separate state model, duplicate routing, an API layer, and an entirely different testing story. Most apps don't need it. Hotwire keeps you in Rails for the UI, sending HTML over the wire and letting Turbo + Stimulus handle interactivity.

## The opinion

> **Hotwire (Turbo + Stimulus) is the default for Rails 8 UI. Reach for React/Vue only when (a) you need offline-first, (b) you need native-feel mobile-web with heavy client-side state, (c) you have an existing component library that's worth keeping, or (d) the team has explicit JS-framework expertise that outweighs the integration cost.**

Counter-positions:
- **React with Inertia.js** — server-rendered React via Rails controllers. Best of both worlds for teams that want React's component model but Rails' routing. See v0.2 `react-with-rails`.
- **htmx** — even more minimal than Turbo. Fine if you don't need Stimulus's state model. Not the Rails-native answer.

## The four primitives

```
Turbo Drive   ← Page navigation (replaces the browser's default — faster, no full page reload)
Turbo Frames  ← Lazy/independent HTML islands within a page
Turbo Streams ← Server-pushed HTML updates (WebSocket or response body)
Stimulus      ← Sprinkled JS controllers for client-side state
```

## Core patterns

### Pattern 1: Turbo Drive — navigation that feels SPA-fast

**Default behavior** (Rails 8): every link click and form submit is intercepted by Turbo. The new HTML is fetched, the `<body>` is swapped, no full reload. Looks and feels instant.

**What you need to know:**
- `<script>` tags in the new HTML don't re-evaluate (each `<script>` runs once per page lifetime; only re-fires if you `<script data-turbo-eval="true">`).
- `window.onload` / `DOMContentLoaded` fire only once on the original load. Use `turbo:load` instead.
- Stimulus controllers re-attach automatically on Turbo navigation.

**Opt-out for a specific link** (e.g. external link, file download):

```erb
<%= link_to "Download", report_path(format: :pdf), data: { turbo: false } %>
```

**Opt-out globally** (rare — only when migrating from a non-Turbo app):

```javascript
// app/javascript/application.js
Turbo.session.drive = false
```

### Pattern 2: Turbo Frames — lazy / independent HTML islands

A `<turbo-frame>` is a chunk of HTML that can be replaced independently of the rest of the page. Two common uses:

**Use A: Inline editing without page navigation**

```erb
<%# app/views/posts/show.html.erb %>
<%= turbo_frame_tag dom_id(@post, :details) do %>
  <h1><%= @post.title %></h1>
  <p><%= @post.body %></p>
  <%= link_to "Edit", edit_post_path(@post), class: "btn" %>
<% end %>
```

```erb
<%# app/views/posts/edit.html.erb %>
<%= turbo_frame_tag dom_id(@post, :details) do %>
  <%= form_with model: @post do |f| %>
    <%= f.text_field :title %>
    <%= f.text_area :body %>
    <%= f.submit "Save" %>
    <%= link_to "Cancel", post_path(@post), class: "btn" %>
  <% end %>
<% end %>
```

When the user clicks "Edit", the frame fetches `edit_post_path` and swaps just the frame contents. Same frame ID on both pages = Turbo knows how to swap. Form submit redirects back, replacing the frame again with the show contents.

No JS in the controller. No special routes. Just same-frame-ID semantics.

**Use B: Lazy loading**

```erb
<%= turbo_frame_tag "comments", src: post_comments_path(@post), loading: :lazy do %>
  <p>Loading comments…</p>
<% end %>
```

The frame fetches `src` when scrolled into view (`loading: :lazy`) and swaps in the response. The "Loading…" content is the fallback.

### Pattern 3: Turbo Streams — server pushes HTML

Five actions: `append`, `prepend`, `replace`, `update`, `remove`. Plus `before` / `after` / `refresh`.

**Streams in form response (one-shot):**

```ruby
# app/controllers/comments_controller.rb
def create
  @comment = @post.comments.create!(comment_params)
  respond_to do |format|
    format.turbo_stream  # renders create.turbo_stream.erb
    format.html { redirect_to @post }
  end
end
```

```erb
<%# app/views/comments/create.turbo_stream.erb %>
<%= turbo_stream.append "comments", partial: "comments/comment", locals: { comment: @comment } %>
<%= turbo_stream.update "new_comment_form", partial: "comments/form", locals: { comment: Comment.new } %>
<%= turbo_stream.update "comment_count", html: @post.comments.count %>
```

One HTTP response, three independent DOM updates.

**Streams over WebSocket (broadcast to all viewers):**

```ruby
class Comment < ApplicationRecord
  belongs_to :post
  broadcasts_to ->(comment) { [comment.post, :comments] }, inserts_by: :append
end
```

```erb
<%# app/views/posts/show.html.erb %>
<%= turbo_stream_from @post, :comments %>
<div id="comments">
  <%= render @post.comments %>
</div>
```

Now every browser viewing the post receives the new comment via Action Cable as soon as it's persisted. No JS.

**Streams from a background job:**

```ruby
class GenerateReportJob < ApplicationJob
  def perform(report_id)
    report = Report.find(report_id)
    report.generate!  # long-running

    Turbo::StreamsChannel.broadcast_update_to(
      [report.user, :reports],
      target: "report_#{report.id}",
      partial: "reports/report",
      locals: { report: report }
    )
  end
end
```

User clicks "Generate". Job runs. When done, the report's row in the page updates without a refresh.

### Pattern 4: Stimulus — sprinkled JS controllers

For client-side state that Turbo can't express:

```html
<div data-controller="reveal">
  <button data-action="reveal#toggle">Show more</button>
  <p data-reveal-target="content" hidden>Hidden content here.</p>
</div>
```

```javascript
// app/javascript/controllers/reveal_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content"]

  toggle() {
    this.contentTarget.hidden = !this.contentTarget.hidden
  }
}
```

**Stimulus conventions:**
- One controller = one component behavior.
- `data-controller="reveal"` binds.
- `data-action="reveal#toggle"` calls on event.
- `data-reveal-target="content"` accessible as `this.contentTarget`.
- `data-reveal-value-message="Hi"` accessible as `this.messageValue`.

**When to use Stimulus:**
- Show/hide.
- Form field dependency (selecting "Other" reveals a text field).
- Copy-to-clipboard.
- Form auto-save.
- Modal open/close.
- Anything that's "click this, change that locally" without a server roundtrip.

**When NOT to use Stimulus:**
- Drag-and-drop with complex state — use a library wrapped in Stimulus.
- A complex form wizard with branching paths and persistent state — use Turbo Frames for steps, Stimulus for in-step UX, or consider Inertia + React.
- Real-time multi-user collaborative editing — separate problem class.

### Pattern 5: Morph updates (Rails 8+ default)

Without morph: Turbo replaces the entire `<body>` or frame contents. Form focus is lost, scroll position resets, animations restart.

With morph (powered by idiomorph): Turbo intelligently diffs the new HTML against the existing DOM and patches only what changed.

```html
<!-- Enable globally -->
<meta name="turbo-refresh-method" content="morph">
<meta name="turbo-refresh-scroll" content="preserve">
```

Or per-frame:

```erb
<%= turbo_frame_tag "feed", refresh: "morph" do %>
  <%= render @posts %>
<% end %>
```

**Morph is the right default for Rails 8 apps.** Add to your `application.html.erb` `<head>`.

### Pattern 6: Action Cable broadcasts from models + jobs

```ruby
class Notification < ApplicationRecord
  belongs_to :user
  broadcasts_to :user, inserts_by: :prepend
end
```

```erb
<%# app/views/notifications/index.html.erb %>
<%= turbo_stream_from current_user, :notifications %>
<div id="notifications">
  <%= render current_user.notifications %>
</div>
```

When `Notification.create!(user: alice, message: "...")` fires:
1. The model's `broadcasts_to` triggers an Action Cable broadcast.
2. Every browser subscribed to `[alice, :notifications]` receives a Turbo Stream message.
3. The new notification prepends to the `#notifications` div.

For Rails 8, the Cable adapter is **Solid Cable** by default — no Redis required.

### Pattern 7: Forms — `data-turbo-confirm`, validation, error handling

```erb
<%= button_to "Delete", post_path(@post), method: :delete,
    data: { turbo_confirm: "Are you sure?" } %>
```

Pops a confirm dialog before submitting. Works without writing JS.

**Validation errors:**

```ruby
def create
  @post = Post.new(post_params)
  if @post.save
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @post }
    end
  else
    render :new, status: :unprocessable_entity  # IMPORTANT — Turbo only re-renders 4xx/5xx
  end
end
```

`status: :unprocessable_entity` (or any 4xx/5xx) is critical — Turbo only re-renders the form on error status. A 200 with errors silently succeeds.

### Pattern 8: When Hotwire ISN'T the right call

| Need | Why not Hotwire | Use instead |
|---|---|---|
| Offline-first | Hotwire is server-driven | React + service worker, or PWA |
| Native-feel mobile-web (60fps animations, gestures) | Server round-trip per state change | React Native, Flutter, or true SPA |
| Highly client-stateful editor (Figma-like) | Local state synced to server | Bespoke JS framework + CRDTs |
| Existing React/Vue team & component library | Rewrite cost > Hotwire benefit | Stick with what you have; use Inertia for routing |
| Multi-user real-time collaboration (cursors, presence) | Cable can do it, but the JS state coordination gets hairy | Liveblocks, Yjs, or a CRDT layer |

### Pattern 9: Testing Hotwire

```ruby
# Request spec — Turbo Stream response
RSpec.describe "POST /posts/:id/comments", type: :request do
  it "creates a comment and broadcasts" do
    post = create(:post)
    expect {
      post(post_comments_path(post),
        params: { comment: { body: "Hi" } },
        headers: { "Accept" => "text/vnd.turbo-stream.html" })
    }.to change(Comment, :count).by(1)
    expect(response.content_type).to start_with("text/vnd.turbo-stream.html")
    expect(response.body).to include("turbo-stream")
  end
end

# System spec — Turbo interaction
RSpec.describe "Post comments", type: :system, js: true do
  it "appears without page reload" do
    user = create(:user)
    post = create(:post)
    sign_in user
    visit post_path(post)

    fill_in "Comment", with: "First!"
    click_button "Submit"

    expect(page).to have_content("First!")  # Capybara waits for it
    expect(page).to have_current_path(post_path(post))  # no navigation
  end
end
```

For broadcast testing, use [`turbo-rails`'s test helpers](https://github.com/hotwired/turbo-rails) or assert against the rendered partial.

## Decision matrix

| Need | Use |
|---|---|
| Fast nav between pages | Turbo Drive (default) |
| Inline edit without leaving page | Turbo Frame |
| Lazy load a section | Turbo Frame with `src:` and `loading: :lazy` |
| Insert a new row after form submit | Turbo Stream `append` |
| Push update to all viewers when model changes | `broadcasts_to` + `turbo_stream_from` |
| Show/hide a UI element | Stimulus controller |
| Real-time form field validation | Stimulus + Turbo Frame submit |
| Long-running job that updates UI when done | Job → `Turbo::StreamsChannel.broadcast_*_to` |
| Preserve focus/scroll on update | Morph (set in `<head>`) |
| Confirm before destructive action | `data: { turbo_confirm: "..." }` |

## Common mistakes to refuse

- Don't reach for React when Turbo + Stimulus would do.
- Don't return 200 on form-validation failure — Turbo skips the re-render. Use `:unprocessable_entity`.
- Don't put complex state in Stimulus — Stimulus is for sprinkles. Heavy state belongs in a real framework.
- Don't `turbo: false` everywhere "to fix" Turbo issues. Diagnose first.
- Don't `window.onload`. Use `turbo:load`.
- Don't add `<script>` tags inside Turbo Frames expecting re-execution.
- Don't `cache_key_with_version` Turbo Frame contents if they should update — caching defeats freshness.
- Don't broadcast from `after_save` — use `after_commit` (see `activerecord-patterns` Pattern 7). `broadcasts_to` does this correctly by default.

## When NOT to use this skill

- The user has chosen React/Vue and is asking how to integrate — that's a v0.2 skill (`react-with-rails`, `vue-with-rails`).
- The user is asking about ActionCable for non-UI use (e.g. monitoring streams) — different scope.

## See also

- `activerecord-patterns` — broadcasts_to runs on after_commit
- `rspec-testing-pyramid` — system specs for Hotwire interaction
- `rails-caching-strategy` — fragment caching with Turbo Frames
- Coming in v0.2: `react-with-rails`, `vue-with-rails`, `angular-with-rails`

## Sources

- [Hotwire.dev](https://hotwired.dev/)
- [Turbo Handbook](https://turbo.hotwired.dev/handbook/introduction)
- [Stimulus Handbook](https://stimulus.hotwired.dev/handbook/introduction)
- [turbo-rails gem](https://github.com/hotwired/turbo-rails)
- [Idiomorph (Turbo morph backend)](https://github.com/bigskysoftware/idiomorph)
- [37signals — HEY using Hotwire](https://signalvnoise.com/) — production case
- [Going Solid — Joe Masilotti](https://masilotti.com/) — Hotwire + native app patterns
- [Boring Rails — Hotwire patterns](https://boringrails.com/) — extensive worked examples
- [Rails 8 morph updates announcement](https://rubyonrails.org/) — default in Rails 8
- [GoRails Hotwire screencasts](https://gorails.com/) — learning resource
