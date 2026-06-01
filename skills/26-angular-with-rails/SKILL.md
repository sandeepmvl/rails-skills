---
name: angular-with-rails
description: Integrate Angular with a Ruby on Rails app — classical API + SPA as the default (Angular's full-framework model doesn't fit Inertia well), standalone-components Angular 17+, NgRx vs signals, JWT auth flow, CORS configuration, deploying Angular separately from Rails. Use when integrating Angular into Rails, the user mentions Angular CLI, NgRx, standalone components, Angular signals, or asks "how do I use Angular with Rails".
---

# Angular with Rails

> Angular doesn't fit Inertia's "props from server" model the way React and Vue do. Use classical API + SPA: Rails-API serves JSON, Angular lives in its own folder/repo as a true SPA.

## The opinion

> **Classical API + SPA for Angular. Rails-API mode. Angular 17+ with standalone components. Signals or NgRx for state. JWT auth (short-lived + refresh). Deploy Angular and Rails separately. Inertia has an Angular adapter but the ecosystem is thin — don't pick it for new work.**

## Setup

```
backend/        Rails-API
frontend/       Angular SPA
```

```ruby
# backend/Gemfile
gem "rails", "~> 8.0"
# (Use Rails-API mode: rails new backend --api)
```

```bash
# frontend/
ng new myapp-frontend --standalone --routing --style=scss
```

## Core patterns

### Pattern 1: API design for Angular

Standard REST + JSON. See `rails-api-design`. JSON:API serializers or alba.

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :posts, only: %i[index show create update destroy]
    resource :session, only: %i[create destroy]
  end
end
```

### Pattern 2: JWT auth flow (Angular service)

```typescript
// frontend/src/app/auth/auth.service.ts
import { Injectable } from "@angular/core"
import { HttpClient } from "@angular/common/http"
import { tap } from "rxjs"

@Injectable({ providedIn: "root" })
export class AuthService {
  constructor(private http: HttpClient) {}

  login(email: string, password: string) {
    return this.http.post<{ access_token: string, refresh_token: string }>(
      "/api/v1/session",
      { email, password }
    ).pipe(
      tap(res => {
        sessionStorage.setItem("access_token", res.access_token)
        // refresh_token: store httpOnly cookie if possible; otherwise sessionStorage
        sessionStorage.setItem("refresh_token", res.refresh_token)
      })
    )
  }

  refresh() {
    const refreshToken = sessionStorage.getItem("refresh_token")
    return this.http.post<{ access_token: string, refresh_token: string }>(
      "/api/v1/session/refresh", { refresh_token: refreshToken }
    ).pipe(tap(res => {
      sessionStorage.setItem("access_token", res.access_token)
      sessionStorage.setItem("refresh_token", res.refresh_token)
    }))
  }
}
```

```typescript
// frontend/src/app/auth/auth.interceptor.ts
import { HttpInterceptorFn } from "@angular/common/http"

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const token = sessionStorage.getItem("access_token")
  const authReq = token ? req.clone({ setHeaders: { Authorization: `Bearer ${token}` } }) : req
  return next(authReq)
}
```

Register interceptor in `app.config.ts` via `provideHttpClient(withInterceptors([authInterceptor]))`.

### Pattern 3: Standalone components (Angular 17+)

```typescript
// frontend/src/app/app.config.ts — register HttpClient provider once for the app
import { ApplicationConfig } from "@angular/core"
import { provideHttpClient, withFetch } from "@angular/common/http"

export const appConfig: ApplicationConfig = {
  providers: [provideHttpClient(withFetch())]
}
```

```typescript
// frontend/src/app/posts/post-list.component.ts
import { Component, inject, signal } from "@angular/core"
import { HttpClient } from "@angular/common/http"

@Component({
  selector: "app-post-list",
  standalone: true,
  template: `
    <ul>
      @for (post of posts(); track post.id) {
        <li>{{ post.title }}</li>
      }
    </ul>
  `
})
export class PostListComponent {
  private http = inject(HttpClient)
  posts = signal<{id: number; title: string}[]>([])

  constructor() {
    this.http.get<any>("/api/v1/posts").subscribe(res => this.posts.set(res.data))
  }
}
```

**Why `provideHttpClient` in app.config:** standalone components require explicit HTTP provider registration. Forgetting it raises `NullInjectorError: HttpClient` at runtime.

**Why standalone:** less boilerplate, no NgModules, faster compilation. Default in Angular 17+.

### Pattern 4: State management — signals vs NgRx

**Default: signals** (Angular 17+ built-in).

```typescript
const count = signal(0)
count.set(count() + 1)
```

**NgRx** for: complex app-wide state, time-travel debugging needs, multiple components reacting to the same actions. Heavy lifecycle. Use only when signals + services aren't enough.

### Pattern 5: CORS

```ruby
# backend/config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("CORS_ORIGINS", "https://myapp.example.com").split(",")
    resource "/api/*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      credentials: false
  end
end
```

Bearer-token auth → `credentials: false`. Cookie-based auth → `credentials: true` + match origin exactly.

### Pattern 6: Deployment

- **Backend:** Kamal (see `kamal-docker-production`).
- **Frontend:** built statically (`ng build`), served by CDN (CloudFront, Cloudflare Pages, Vercel) or a static host (Render, Netlify).
- **Separate domains:** `api.example.com` (Rails) + `app.example.com` (Angular). CORS configured.
- **Or same domain:** static frontend served from `/`, API at `/api/*`. Configure Kamal Proxy / nginx to route.

## Common mistakes to refuse

- Don't try to put Angular inside `app/javascript/` of a Rails monolith. It's not a sprinkles framework — it's a full SPA.
- Don't store JWT in localStorage (XSS-vulnerable). sessionStorage or httpOnly cookie.
- Don't use NgRx for simple state. Signals are enough.
- Don't use `*ngIf` / `*ngFor` in Angular 17+ — use `@if` / `@for` block syntax. `@for` requires a `track` expression (`@for (item of items; track item.id)`) — omitting it is a compile error.

## See also

- `react-with-rails` — different framework, similar API+SPA setup
- `rails-api-design` — auth, versioning, CORS
- `rails-security-baseline` — JWT best practices

## Sources

- [Angular docs (standalone)](https://angular.dev/)
- [NgRx](https://ngrx.io/) (counter-position)
- [Angular signals](https://angular.dev/guide/signals)
- [Inertia Angular adapter](https://github.com/inertiajs) — exists but thin ecosystem
- [Rails API guide](https://guides.rubyonrails.org/api_app.html)
