---
name: asset-pipeline-propshaft
description: Asset pipeline for Rails 8 — Propshaft as the new default (replacing Sprockets), Importmap-rails for JS without bundling, jsbundling-rails for esbuild/rollup/webpack, cssbundling-rails for Tailwind/Sass/PostCSS, the Sprockets-to-Propshaft migration, asset host for CDN, digest stamping, far-future expiry headers. Use when the user mentions Propshaft, Sprockets migration, importmap, jsbundling, cssbundling, asset_host, asset pipeline, .css.erb, manifest.js, or asks about Rails 8 assets.
---

# Asset Pipeline (Propshaft)

> Rails 8 ships Propshaft. It does two things: maintain a load path for assets, and digest-stamp filenames for cache-busting. That's it. Sprockets did much more (preprocessing, transpilation, concatenation). Most of that moved to dedicated bundlers (esbuild, vite, sass).

## The opinion

> **Greenfield Rails 8: Propshaft + Importmap (no Node) for simple apps. Propshaft + jsbundling-rails (esbuild) for richer apps. Propshaft + cssbundling-rails (Tailwind / Dart Sass) for Tailwind apps. Don't migrate an existing Sprockets app to Propshaft unless you audit for Sprockets-specific features (`.scss.erb`, manifest directives, asset processors) — those don't translate.**

## What Propshaft does NOT do

- **No preprocessing.** No `.scss.erb`. No ERB inside CSS / JS.
- **No transpilation.** No CoffeeScript, no Babel built-in.
- **No concatenation.** No `//= require` directives. Bundle with esbuild / vite if you need.
- **No source maps.** Bundlers handle.

What it does: serve `app/assets/`, stamp filenames with content digests, set Cache-Control headers.

## Decision matrix — JS bundler

| App | Pick |
|---|---|
| Rails 8 monolith, server-rendered, minor JS | Importmap-rails (no Node) |
| Mixed React/Vue islands | jsbundling-rails + esbuild |
| Heavy SPA mixed in | vite_ruby (HMR, TypeScript) |
| Legacy Webpacker | Shakapacker (community fork) — migrate later |

## Decision matrix — CSS

| App | Pick |
|---|---|
| Tailwind CSS | cssbundling-rails + Tailwind |
| Dart Sass | cssbundling-rails + Dart Sass |
| Vanilla CSS | Propshaft directly (no bundler) |
| Plain CSS via Sprockets (was sass-rails) | Migrate to Dart Sass via cssbundling-rails |

## Core patterns

### Pattern 1: Greenfield — Importmap + Propshaft

```bash
rails new myapp --asset-pipeline=propshaft --javascript=importmap
```

```ruby
# config/importmap.rb
pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
```

Browser fetches each module separately. No bundling. No Node required. Modern browsers handle the parallel fetches efficiently.

**Trade-off:** initial page load issues N small fetches instead of one bundle. With HTTP/2 + browser cache, this is usually fine.

### Pattern 2: Greenfield — jsbundling-rails + esbuild

```bash
rails new myapp --asset-pipeline=propshaft --javascript=esbuild
```

```json
// package.json (generated)
{
  "scripts": {
    "build": "esbuild app/javascript/*.* --bundle --sourcemap --outdir=app/assets/builds --public-path=/assets"
  }
}
```

```yaml
# Procfile.dev
web: bin/rails server
js: yarn build --watch
```

`bin/dev` starts both. Output goes to `app/assets/builds/`, Propshaft serves digest-stamped versions.

### Pattern 3: Tailwind via cssbundling-rails

```bash
rails new myapp --asset-pipeline=propshaft --javascript=importmap --css=tailwind
```

```json
// package.json
{
  "scripts": {
    "build:css": "tailwindcss -i ./app/assets/stylesheets/application.tailwind.css -o ./app/assets/builds/application.css --minify"
  }
}
```

`bin/dev` runs `yarn build:css --watch` alongside the server.

### Pattern 4: Migrating from Sprockets to Propshaft

**Audit first:**

```bash
# Find Sprockets-specific features
grep -rE "//= require|\\.scss\\.erb|\\.coffee|sprockets" app/
```

If you find any:

| Found | Migrate to |
|---|---|
| `//= require foo` | Use a bundler (jsbundling or vite) |
| `.scss.erb` (ERB in SCSS) | Move dynamic values to CSS variables; SCSS via cssbundling-rails |
| `.coffee` | Transpile to JS, then bundle with esbuild |
| `app/assets/javascripts/manifest.js` directives | Bundler config |
| `Sprockets.register_*` processors | No equivalent; either drop or run as a build step |

**Migration steps:**

1. Add Propshaft + bundlers to Gemfile alongside Sprockets.
2. Move asset compilation off Sprockets piece by piece.
3. Once nothing references Sprockets, remove the gem.
4. Test in staging — first cache flush often surfaces missing files.

For non-trivial apps: 2-5 days. Don't combine with the Rails version bump.

### Pattern 5: Asset host (CDN)

```ruby
# config/environments/production.rb
config.asset_host = "https://cdn.example.com"
```

Propshaft generates URLs like `https://cdn.example.com/assets/application-abc123.css`. Point CloudFront / Cloudflare / Fastly at the Rails origin; cache assets at the edge.

**Far-future expiry** is automatic — digest in the filename means a new content version = new URL = no stale cache.

### Pattern 6: Importmap pin from CDN

```ruby
# config/importmap.rb
pin "react", to: "https://ga.jspm.io/npm:react@18/index.js"
pin "react-dom", to: "https://ga.jspm.io/npm:react-dom@18/index.js"
```

CDN-hosted modules. Skip yarn entirely for these. Useful when you want one or two npm libraries without a bundler.

### Pattern 7: Vendoring importmap pins

```bash
bin/importmap pin react
# Downloads react to vendor/javascript/ and pins to it
```

When you want predictable behavior (CDN downtime resilience, deterministic builds), vendor the pinned modules.

### Pattern 8: Removing Sprockets entirely

```ruby
# Gemfile — remove
# gem "sprockets-rails"
# gem "sass-rails"
# gem "coffee-rails"

# config/application.rb — remove
# require "sprockets/railtie"

# Replace with
gem "propshaft"
```

```ruby
# config/manifest.js — DELETE if you used it
# config/assets.rb — DELETE
```

```ruby
# config/initializers/assets.rb (or config/application.rb)
config.assets.paths << Rails.root.join("app/assets/builds")  # if using bundlers
```

## Common mistakes to refuse

- Don't try to use `.scss.erb` with Propshaft. Move dynamic values to CSS variables.
- Don't migrate from Sprockets to Propshaft in the same PR as the Rails version bump.
- Don't disable digest stamping. The whole cache-bust mechanism depends on it.
- Don't put hashed file references in code — Rails' asset helpers (`asset_path`, `image_tag`) resolve them.
- Don't ship sourcemaps to production publicly. They reveal your unminified source.

## When NOT to use this skill

- Pre-Rails 7 app — Sprockets is still your default. Wait for v0.2 / v0.3 backport content.
- The user is asking about a specific bundler (esbuild config) — touch lightly, defer to bundler docs.

## See also

- `rails-upgrade-7-to-8` — when adopting Propshaft as part of upgrade
- `kamal-docker-production` — building assets at Docker build time
- Coming in v0.2: `react-with-rails` — jsbundling for React

## Sources

- [Propshaft README](https://github.com/rails/propshaft)
- [Importmap-rails](https://github.com/rails/importmap-rails)
- [jsbundling-rails](https://github.com/rails/jsbundling-rails)
- [cssbundling-rails](https://github.com/rails/cssbundling-rails)
- [vite_ruby (alternative)](https://vite-ruby.netlify.app/)
- [Shakapacker (Webpacker fork)](https://github.com/shakacode/shakapacker)
- [Rails 8 Propshaft launch notes](https://rubyonrails.org/2024/11/7/rails-8-no-paas-required)
