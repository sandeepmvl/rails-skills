---
name: rails-api-design
description: Design REST APIs in Ruby on Rails — URL versioning over Accept-header, jsonapi-serializer / alba / blueprinter, pagy pagination, JWT auth for stateless / session cookies for first-party SPAs, rack-attack rate limiting, structured error responses, OpenAPI/Swagger via rswag, CORS configuration. Use when building or reviewing a Rails::API app, adding JSON endpoints to a monolith, the user mentions API versioning, serializers, JSON serialization, JWT, rack-attack, rate limits, pagination, OpenAPI, Swagger, rswag, REST API design, CORS, or asks how to structure /api/v1 routes.
---

# Rails API Design

> Build a JSON API that ages well. AI agents generate Rails APIs by reflex: `respond_to :json`, `to_json`, no versioning, no rate limiting, no consistent error shape. This skill encodes the choices senior Rails API authors make when the API has to live for years.

## Why this matters

A REST API is a contract. Once clients depend on it, every change is a coordination cost. Get the foundations right at the start — versioning strategy, serialization layer, pagination, error format — or pay for it later in deprecation pain.

## The opinion

> **URL versioning (`/api/v1`). jsonapi-serializer for JSON:API; alba for plain JSON. pagy for pagination (faster than kaminari). JWT for stateless third-party / mobile clients; session cookies for first-party SPAs on the same domain. rack-attack for rate limiting + brute-force. Structured errors per RFC 9457 (problem-details) or JSON:API errors. rswag for OpenAPI generation from request specs.**

Counter-positions:
- **GraphQL** over REST: legitimate for highly-relational read APIs with many client variants. We default to REST because the tooling is broader and the operational burden is lower. If you have GraphQL needs, use `graphql-ruby`.
- **Accept-header versioning** (`Accept: application/vnd.myapp+json; version=2`): cleaner in theory; in practice harder to debug, caches awkwardly, and devs hate it. URL versioning wins on operational ergonomics.
- **active_model_serializers** (AMS): widely used historically. We default to `jsonapi-serializer` (formerly Fast JSONAPI) or `alba` because both are 10–50× faster.

## Core patterns

### Pattern 1: URL versioning

**Route structure:**

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :posts, only: %i[index show create update destroy] do
        resources :comments, only: %i[index create]
      end
      resource :session, only: %i[create destroy]
    end
  end
end
```

**Controller structure:**

```ruby
# app/controllers/api/v1/base_controller.rb
class Api::V1::BaseController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate_user!
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity
  rescue_from Pundit::NotAuthorizedError, with: :forbidden

  private

  def authenticate_user!
    authenticate_or_request_with_http_token do |token, _options|
      @current_user = User.find_by(api_token: token)
    end
  end

  def current_user
    @current_user
  end

  def not_found(error)
    render json: { errors: [{ status: "404", title: "Not Found", detail: error.message }] },
      status: :not_found
  end

  def unprocessable_entity(error)
    render json: { errors: error.record.errors.map { |e| { status: "422", title: "Validation Failed", detail: "#{e.attribute} #{e.message}", source: { pointer: "/data/attributes/#{e.attribute}" } } } },
      status: :unprocessable_entity
  end

  def forbidden(_error)
    render json: { errors: [{ status: "403", title: "Forbidden" }] }, status: :forbidden
  end
end

class Api::V1::PostsController < Api::V1::BaseController
  def index
    posts = policy_scope(Post).includes(:author).order(created_at: :desc)
    pagy_obj, paginated = pagy(posts, limit: 25)
    render json: PostSerializer.new(paginated, meta: pagination_meta(pagy_obj)).serializable_hash
  end
end
```

**Why URL over Accept-header:**

| Concern | URL `/api/v1` | Accept-header `application/vnd.app+json; v=1` |
|---|---|---|
| Debuggability | curl shows the version in the URL | requires correct header to see anything |
| Caching | CDNs cache cleanly per URL | Vary: Accept gives correct but harder cache behavior |
| Tooling | Postman / Insomnia / browsers handle as-is | every tool needs custom headers |
| Versioning is a routing concern | natural | feels like a content-negotiation concern (it isn't) |

When you ship v2, you ship `/api/v2` alongside `/api/v1` and deprecate v1 on a schedule. Routes file says everything.

### Pattern 2: Serialization

**Before** (AI default — `to_json` with `:include` / `:only` everywhere):

```ruby
def show
  render json: @post.to_json(
    only: %i[id title body created_at],
    include: { author: { only: %i[id name] }, comments: { only: %i[id body] } }
  )
end
```

Problems: hard to test, the same shape repeats across actions, no clear versioning hook, can't add computed attributes without bloating the model.

**After (jsonapi-serializer, JSON:API spec):**

```ruby
# Gemfile: gem "jsonapi-serializer"

class Api::V1::PostSerializer
  include JSONAPI::Serializer

  set_type :post
  attributes :title, :body, :created_at, :status

  belongs_to :author, serializer: Api::V1::AuthorSerializer
  has_many :comments, serializer: Api::V1::CommentSerializer

  attribute :excerpt do |post|
    post.body.truncate(140)
  end

  link :self do |post|
    Rails.application.routes.url_helpers.api_v1_post_url(post)
  end
end

# In controller:
render json: Api::V1::PostSerializer.new(@post, include: %i[author comments]).serializable_hash
```

Output:
```json
{
  "data": {
    "id": "42",
    "type": "post",
    "attributes": { "title": "...", "body": "...", "excerpt": "...", "created_at": "..." },
    "relationships": {
      "author": { "data": { "id": "7", "type": "author" } },
      "comments": { "data": [{ "id": "1", "type": "comment" }, ...] }
    },
    "links": { "self": "..." }
  },
  "included": [...]
}
```

**Alternative: alba — for non-JSON:API plain shape:**

```ruby
# Gemfile: gem "alba"

class Api::V1::PostResource
  include Alba::Resource

  attributes :id, :title, :body, :created_at
  attribute :excerpt do |post|
    post.body.truncate(140)
  end

  one :author, resource: Api::V1::AuthorResource
  many :comments, resource: Api::V1::CommentResource
end

render json: Api::V1::PostResource.new(@post, params: { include: %i[author comments] }).serialize
```

Output:
```json
{"id":42,"title":"...","body":"...","excerpt":"...","author":{"id":7,"name":"..."},"comments":[...]}
```

**Pick one and stick to it:** JSON:API is right when clients are diverse (mobile + 3rd-party + first-party SPA) and the spec gives them a shared contract. Plain JSON via alba is right when you control all the clients and the spec ceremony costs more than it saves.

### Pattern 3: Pagination — pagy (NOT kaminari)

**Before** (kaminari — slow):

```yaml
# Gemfile: gem "kaminari"
posts = Post.page(params[:page]).per(25)
```

Kaminari is fine functionally but ~40× slower than pagy on large tables (issues a separate COUNT(*) that pagy can avoid).

**After (pagy 9+):**

```ruby
# Gemfile: gem "pagy", "~> 9.0"
include Pagy::Backend  # in ApplicationController or base API controller

def index
  posts = Post.includes(:author).order(created_at: :desc)
  pagy_obj, paginated_posts = pagy(posts, limit: 25)
  render json: PostSerializer.new(paginated_posts).serializable_hash.merge(
    meta: pagination_meta(pagy_obj)
  )
end

private

def pagination_meta(pagy)
  {
    current_page: pagy.page,
    per_page: pagy.limit,   # Pagy 9 renamed from .items to .limit
    total_pages: pagy.pages,
    total_count: pagy.count
  }
end
```

**For cursor-based pagination** (feeds, infinite scroll, time-series): use `pagy-cursor` or `keyset_pagination`. Cursor pagination doesn't drift when rows are inserted between page fetches.

### Pattern 4: Authentication — JWT vs session cookies

**Decision matrix:**

| Client | Use | Why |
|---|---|---|
| First-party SPA on same origin as Rails | Session cookies | Browser handles them; CSRF tokens cover protection; no token expiry management |
| Mobile app | JWT (bearer) | No cookie jar; explicit refresh flow |
| Third-party API consumer | API keys or OAuth2 | Tokens are credentials they manage |
| Service-to-service | mTLS or API keys | Cookies/JWT don't fit |

**JWT pattern with `devise-jwt`:**

```ruby
# Gemfile
gem "devise"
gem "devise-jwt"

# config/initializers/devise.rb
Devise.setup do |config|
  config.jwt do |jwt|
    jwt.secret = Rails.application.credentials.devise_jwt_secret_key
    jwt.dispatch_requests = [["POST", %r{^/api/v1/session$}]]
    jwt.revocation_requests = [["DELETE", %r{^/api/v1/session$}]]
    jwt.expiration_time = 15.minutes.to_i
  end
end

class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Denylist
  devise :database_authenticatable, :jwt_authenticatable, jwt_revocation_strategy: self
end
```

**Why short-lived JWTs + refresh tokens (NOT long-lived JWTs):**

- A leaked JWT is a credential. If it's valid for 30 days, the attacker has 30 days.
- Short expiry (5–15 min) + refresh token (rotated on use, stored server-side and revocable) bounds the damage.
- Never put secrets in the JWT payload — anyone with the token can decode it (base64).

See `rails-security-baseline` for the full JWT checklist.

### Pattern 5: Rate limiting + brute-force — rack-attack

```ruby
# Gemfile: gem "rack-attack"

# config/initializers/rack_attack.rb
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new  # use Redis in prod

# General API rate limit per IP
Rack::Attack.throttle("api/ip", limit: 300, period: 1.minute) do |req|
  req.ip if req.path.start_with?("/api/")
end

# Login brute-force protection
Rack::Attack.throttle("login/ip", limit: 5, period: 20.seconds) do |req|
  req.ip if req.path == "/api/v1/session" && req.post?
end

# Login brute-force per email (slow down email enumeration)
Rack::Attack.throttle("login/email", limit: 5, period: 20.seconds) do |req|
  if req.path == "/api/v1/session" && req.post?
    req.params.dig("session", "email").presence
  end
end

# Customize the throttled response
Rack::Attack.throttled_responder = lambda do |req|
  match_data = req.env["rack.attack.match_data"]
  now = match_data[:epoch_time]
  headers = {
    "Content-Type" => "application/json",
    "RateLimit-Limit" => match_data[:limit].to_s,
    "RateLimit-Remaining" => "0",
    "RateLimit-Reset" => (now + (match_data[:period] - now % match_data[:period])).to_s
  }
  [429, headers, [{ errors: [{ status: "429", title: "Too Many Requests" }] }.to_json]]
end
```

**Why per-IP AND per-email throttling on login:**

Per-IP alone misses distributed brute-force (botnet from 1000 IPs). Per-email alone misses credential stuffing from one IP across many emails. Both together cover both vectors.

### Pattern 6: Structured error responses

**Pick one:** JSON:API errors (if you use jsonapi-serializer) OR RFC 9457 problem-details (if you use plain JSON). Don't mix.

**JSON:API errors:**

```json
{
  "errors": [
    {
      "status": "422",
      "code": "validation_failed",
      "title": "Validation Failed",
      "detail": "Email has already been taken",
      "source": { "pointer": "/data/attributes/email" }
    }
  ]
}
```

**RFC 9457 problem-details:**

```json
{
  "type": "https://api.example.com/problems/validation-failed",
  "title": "Validation Failed",
  "status": 422,
  "detail": "Email has already been taken",
  "instance": "/api/v1/users/42",
  "errors": [
    { "field": "email", "message": "has already been taken" }
  ]
}
```

Either way: stable structure across every error type. Clients should be able to write one error handler and know what to expect.

### Pattern 7: CORS

For APIs serving browser-based clients on different origins:

```yaml
# Gemfile: gem "rack-cors"

# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("CORS_ORIGINS", "").split(",")
    # NEVER use `origins "*"` if you allow credentials or sensitive endpoints

    resource "/api/*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      credentials: false,  # true only if you really need browser cookies cross-origin
      max_age: 600
  end
end
```

**Anti-pattern:** `origins "*"` in production. Even for read-only APIs, it's a credential leak waiting to happen the first time someone adds an authenticated endpoint without updating CORS.

### Pattern 8: OpenAPI from request specs — rswag

```ruby
# Gemfile
gem "rswag", group: :development
gem "rswag-specs", group: %i[development test]   # needs to load in spec/

# spec/integration/api/v1/posts_spec.rb
require "swagger_helper"

RSpec.describe "Api::V1::Posts", type: :request do
  path "/api/v1/posts" do
    get "List posts" do
      tags "Posts"
      produces "application/json"
      parameter name: :page, in: :query, type: :integer, required: false
      parameter name: :per_page, in: :query, type: :integer, required: false

      response "200", "returns posts" do
        let(:page) { 1 }
        run_test! do |response|
          expect(JSON.parse(response.body)["data"]).to be_an(Array)
        end
      end
    end
  end
end
```

```bash
bin/rails rswag:specs:swaggerize
# Generates swagger/v1/swagger.yaml
# Served at /api-docs in dev (Swagger UI)
```

**Why:** the spec is the doc. No manual OpenAPI YAML drift.

### Pattern 9: Versioning when you ship v2

Default to separate controllers per version (`api/v1/posts_controller.rb`, `api/v2/posts_controller.rb`) — maximum freedom, minor duplication. When v2 is mostly v1, share via a concern.

Sunset old versions on a published schedule. Set Deprecation + Sunset headers on every v1 response:

```ruby
before_action :deprecation_notice  # in Api::V1::BaseController

def deprecation_notice
  response.set_header("Deprecation", "true")
  response.set_header("Sunset", "Wed, 31 Dec 2026 23:59:59 GMT")
  response.set_header("Link", '<https://docs.example.com/api/v2>; rel="successor-version"')
end
```

## Decision matrix

| Concern | Default |
|---|---|
| Versioning | URL `/api/v{n}` |
| Serializer | `jsonapi-serializer` for JSON:API; `alba` for plain JSON |
| Pagination | `pagy` (with `pagy-cursor` for feeds) |
| Auth (first-party SPA, same origin) | Session cookies |
| Auth (mobile, third-party) | JWT (short-lived) + refresh tokens |
| Rate limiting | `rack-attack` per-IP + per-credential |
| Errors | JSON:API errors OR RFC 9457 — not both |
| CORS | `rack-cors` with explicit origins list, never `*` |
| OpenAPI | `rswag` from request specs |
| Async work | Background job (`solid-queue-and-sidekiq`) |

## Common mistakes to refuse

- Don't use `*` in CORS `origins` for any endpoint that's not strictly public.
- Don't store secrets in JWT payloads — payloads are base64, not encrypted.
- Don't issue 30-day JWTs — short-lived + refresh.
- Don't use kaminari on a large table — pagy is the right answer.
- Don't `to_json` directly — use a serializer.
- Don't mix `Accept`-header and URL versioning. Pick one.
- Don't ship without a rate limit. Even a generous one.
- Don't respond differently to "email exists" vs "wrong password" on login — credential stuffing oracle.

## When NOT to use this skill

- The user is building a tiny internal API where the trade-offs don't matter — link the relevant single section.
- The user is building a GraphQL API — different paradigm, different skill (not in v0.1).

## See also

- `rails-security-baseline` — CSRF for SPAs, JWT secrets, secure headers
- `solid-queue-and-sidekiq` — async work
- `n-plus-one-killer` — API endpoints are where N+1s hurt most
- Coming in v0.2: `stripe-webhook-integration`, `webhook-handling`, `external-api-integration`

## Bundled assets

- [`assets/base-api-controller-template.rb`](assets/base-api-controller-template.rb) — drop-in `Api::V1::BaseController` with auth, error handling, pagination

## Sources

- [JSON:API spec](https://jsonapi.org/format/) — error structure, relationships, pagination links
- [RFC 9457 — Problem Details for HTTP APIs](https://www.rfc-editor.org/rfc/rfc9457)
- [jsonapi-serializer README](https://github.com/jsonapi-serializer/jsonapi-serializer)
- [alba README](https://github.com/okuramasafumi/alba) — fast plain JSON serializer
- [pagy README](https://github.com/ddnexus/pagy) — performance benchmarks
- [devise-jwt README](https://github.com/waiting-for-dev/devise-jwt)
- [rack-attack README](https://github.com/rack/rack-attack)
- [rack-cors README](https://github.com/cyu/rack-cors)
- [rswag README](https://github.com/rswag/rswag)
- [OWASP API Security Top 10](https://owasp.org/API-Security/) — what to defend against
