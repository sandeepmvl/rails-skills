---
name: react-with-rails
description: Integrate React with a Ruby on Rails app — Inertia.js as the default (server-rendered routing, no separate API), classical API + SPA when Inertia doesn't fit, jsbundling-rails with esbuild, vite_ruby as a faster alternative, hydration vs full SPA, when React earns the integration cost. Use when integrating React into Rails, the user mentions Inertia, React Router, SPA, jsbundling-rails, vite_ruby, hydration, server-side rendering, or asks "should I use React with Rails".
---

# React with Rails

> Two viable paths: Inertia.js (Rails controllers render React components, no separate API) or classical API + SPA (Rails-API serves JSON; React lives in its own repo or its own folder). Pick wrong and you pay for years.

## The opinion

> **Inertia.js for most React + Rails apps. Classical API + SPA only when you have an explicit reason (multi-platform clients, separate deployment cadence, separate teams). Use `jsbundling-rails` with esbuild or `vite_rails`. Don't add React to a Hotwire app unless you have a concrete need React solves and Turbo doesn't.**

Counter-position: React + GraphQL + Apollo + bespoke routing is mature and has its place. For most Rails + React teams in 2026, Inertia is the right default.

## Decision matrix

| Need | Use |
|---|---|
| One web client, server-rendered routing, want React's component model | **Inertia.js** |
| Native mobile client + web SPA + third-party API consumers | Classical API + separate React SPA |
| Heavy real-time + multi-user state | React + dedicated state layer (Liveblocks, Yjs); Rails as API |
| Sprinkles of interactivity on a Rails monolith | Don't. Use Hotwire. |

## Core patterns

### Pattern 1: Inertia.js (recommended default)

```ruby
# Gemfile
gem "inertia_rails"

# config/initializers/inertia_rails.rb (optional)
InertiaRails.configure do |config|
  config.version = ViteRuby.digest  # auto-bust cache on JS bundle change
end
```

```ruby
# Controller
class PostsController < ApplicationController
  def index
    posts = Post.includes(:author).order(created_at: :desc).limit(20)
    render inertia: "Posts/Index", props: {
      posts: posts.as_json(only: %i[id title status], include: { author: { only: %i[id name] } })
    }
  end

  def show
    post = Post.find(params[:id])
    render inertia: "Posts/Show", props: { post: post.as_json }
  end
end
```

```jsx
// app/frontend/Pages/Posts/Index.jsx
import { Link } from "@inertiajs/react"

export default function Index({ posts }) {
  return (
    <div>
      {posts.map(post => (
        <Link key={post.id} href={`/posts/${post.id}`}>{post.title}</Link>
      ))}
    </div>
  )
}
```

**Why Inertia wins:**
- Rails routing stays in Rails.
- No separate API to maintain.
- Components hydrate from server-rendered props.
- Auth = Rails session cookies (no JWT machinery).
- Page transitions look SPA-fast (Inertia handles).

### Pattern 2: jsbundling-rails (esbuild) — the bundler

```bash
bin/rails javascript:install:esbuild
```

```json
// package.json — generated
{
  "scripts": {
    "build": "esbuild app/javascript/*.* --bundle --sourcemap --outdir=app/assets/builds --public-path=/assets"
  }
}
```

```yaml
# Procfile.dev (foreman)
web: bin/rails server
js: yarn build --watch
css: yarn build:css --watch  # if cssbundling-rails
```

`bin/dev` starts everything. Hot-reload via Turbo Drive's auto-refresh + esbuild's watch.

### Pattern 3: vite_ruby — the faster bundler

```ruby
# Gemfile
gem "vite_rails"

# bin/vite install
```

```json
// vite.config.ts
import { defineConfig } from "vite"
import RubyPlugin from "vite-plugin-ruby"
import react from "@vitejs/plugin-react"

export default defineConfig({
  plugins: [RubyPlugin(), react()]
})
```

**Why vite_ruby over jsbundling-rails:**
- HMR (Hot Module Replacement) — React component edits without losing state.
- Faster builds for medium-large apps.
- First-class TypeScript.
- More plugin ecosystem.

Most Rails + React teams default to vite_ruby in 2026.

### Pattern 4: Classical API + SPA — when Inertia doesn't fit

```
backend/        # Rails-API, served at /api/v1
frontend/       # React SPA, separate repo/folder, served by CDN
```

**Setup is straightforward, complexity is operational:**
- Auth via JWT (see `rails-api-design` + `rails-security-baseline`).
- API versioning (`/api/v1`).
- CORS configured for the SPA's origin.
- Separate deploys: deploying API ≠ deploying SPA.
- Different testing stories (RSpec + Cypress / Playwright).

**Use this when:**
- Multiple clients (mobile + web + third party).
- SPA team is separate from Rails team.
- Different deploy cadence required.
- Heavy client-side state that doesn't fit Inertia's "props from server" model.

### Pattern 5: React + Stimulus interop (for monolith Rails + React islands)

For a Hotwire app with one heavy React component (a calendar, a chart):

```jsx
// app/javascript/components/Calendar.jsx
import { createRoot } from "react-dom/client"

export function mountCalendar(element, props) {
  const root = createRoot(element)
  root.render(<Calendar {...props} />)
  return root
}
```

```javascript
// app/javascript/controllers/calendar_controller.js
import { Controller } from "@hotwired/stimulus"
import { mountCalendar } from "../components/Calendar"

export default class extends Controller {
  static values = { events: Array }

  connect() {
    this.root = mountCalendar(this.element, { events: this.eventsValue })
  }

  disconnect() {
    this.root?.unmount()
  }
}
```

```erb
<div data-controller="calendar" data-calendar-events-value="<%= @events.to_json %>"></div>
```

One React component, mounted by a Stimulus controller, in an otherwise-Hotwire app. Best of both.

## Common mistakes to refuse

- Don't add React to a Hotwire app for sprinkles of interactivity. Use Stimulus.
- Don't reach for Webpacker in 2026 — vite_ruby or jsbundling-rails.
- Don't classical-API + SPA for a single web client. Inertia is simpler.
- Don't share auth between Rails session and React via localStorage — use proper JWT flow if API+SPA.
- Don't render React server-side and then re-hydrate on the client unless you've measured a real win (Inertia's PageRefresh is enough for most).

## See also

- `hotwire-turbo-stimulus` — when to NOT use React
- `rails-api-design` — for classical API + SPA
- `vue-with-rails`, `angular-with-rails` — sister skills

## Sources

- [Inertia.js docs](https://inertiajs.com/) + [inertia_rails gem](https://github.com/inertiajs/inertia-rails)
- [vite_ruby](https://vite-ruby.netlify.app/)
- [jsbundling-rails](https://github.com/rails/jsbundling-rails)
- [React docs](https://react.dev/)
- [Boring Rails — Inertia patterns](https://boringrails.com/)
- [DHH on Hotwire vs React](https://hotwired.dev/) (counter-position background)
