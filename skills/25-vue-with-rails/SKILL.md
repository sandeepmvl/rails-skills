---
name: vue-with-rails
description: Integrate Vue with a Ruby on Rails app — Inertia.js as the default (server-rendered routing), classical API + SPA when Inertia doesn't fit, vite_ruby with @vitejs/plugin-vue, Vue 3 Composition API, hydration patterns, when Vue earns the integration cost. Use when integrating Vue into Rails, the user mentions Inertia Vue adapter, Vue Router, Pinia, vite_ruby + Vue, or asks "should I use Vue with Rails".
---

# Vue with Rails

> Same playbook as React: Inertia.js for most cases, classical API + SPA when justified. Vue 3 + Composition API is the current default.

## The opinion

> **Inertia.js with the Vue adapter for most Rails + Vue apps. Classical API + SPA only when you have specific reasons. Vue 3, Composition API, vite_ruby. Don't add Vue to a Hotwire app unless you have a concrete need.**

## Decision matrix — same as React

See `react-with-rails`. The Inertia-vs-API+SPA decision is framework-agnostic.

## Core patterns

### Pattern 1: Inertia.js + Vue 3

```ruby
# Gemfile
gem "inertia_rails"
```

```bash
yarn add @inertiajs/vue3 vue@^3
```

```javascript
// app/frontend/entrypoints/application.js
import { createApp, h } from "vue"
import { createInertiaApp } from "@inertiajs/vue3"

createInertiaApp({
  resolve: name => {
    const pages = import.meta.glob("../Pages/**/*.vue", { eager: true })
    return pages[`../Pages/${name}.vue`]
  },
  setup({ el, App, props, plugin }) {
    createApp({ render: () => h(App, props) })
      .use(plugin)
      .mount(el)
  }
})
```

```vue
<!-- app/frontend/Pages/Posts/Index.vue -->
<script setup>
import { Link } from "@inertiajs/vue3"
defineProps({ posts: Array })
</script>

<template>
  <Link v-for="post in posts" :key="post.id" :href="`/posts/${post.id}`">
    {{ post.title }}
  </Link>
</template>
```

```ruby
# Controller — same as React Inertia
class PostsController < ApplicationController
  def index
    render inertia: "Posts/Index", props: { posts: Post.all.as_json }
  end
end
```

### Pattern 2: vite_ruby + Vue plugin

```bash
gem "vite_rails"
bin/vite install
yarn add @vitejs/plugin-vue
```

```javascript
// vite.config.ts
import { defineConfig } from "vite"
import RubyPlugin from "vite-plugin-ruby"
import vue from "@vitejs/plugin-vue"

export default defineConfig({
  plugins: [RubyPlugin(), vue()]
})
```

HMR works out of the box.

### Pattern 3: Pinia for client state (when needed)

For client-side state beyond what Inertia props give you:

```javascript
// app/frontend/stores/cart.js
import { defineStore } from "pinia"

export const useCartStore = defineStore("cart", {
  state: () => ({ items: [] }),
  actions: {
    add(item) { this.items.push(item) }
  }
})
```

Use sparingly. Most page state belongs on the server; Pinia is for genuinely client-only state (UI mode, undo stack).

### Pattern 4: Vue islands in a Hotwire app

```javascript
// app/javascript/controllers/calendar_controller.js
import { Controller } from "@hotwired/stimulus"
import { createApp } from "vue"
import Calendar from "../components/Calendar.vue"

export default class extends Controller {
  static values = { events: Array }

  connect() {
    this.app = createApp(Calendar, { events: this.eventsValue }).mount(this.element)
  }

  disconnect() {
    this.app?.unmount()
  }
}
```

Same pattern as React — one Vue component mounted by Stimulus.

## Common mistakes to refuse

- Don't pick Vue 2 in 2026. End of life.
- Don't use Options API for new code. Composition API.
- Don't bring Vue Router into an Inertia app — Rails routes are the router.
- Don't ship Vue 3 + jQuery in the same component.

## See also

- `react-with-rails` — same playbook, different framework
- `hotwire-turbo-stimulus` — when to skip Vue entirely
- `rails-api-design` — for classical API + SPA

## Sources

- [Inertia Vue adapter](https://inertiajs.com/client-side-setup#vue)
- [Vue 3 docs](https://vuejs.org/)
- [vite_ruby + Vue](https://vite-ruby.netlify.app/)
- [Pinia](https://pinia.vuejs.org/)
