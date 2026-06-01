# Evals for `rails-api-design`

## Prompt 1: "Where should I version my API?"

**User prompt:**
> Should I version my Rails API in the URL like `/api/v1` or via the Accept header?

**Expected:**
- Recommends URL versioning (`/api/v1`).
- Lists the four reasons: debuggability, caching, tooling, routing-concern.
- Acknowledges Accept-header is cleaner in theory.

**Rubric:**
- [ ] URL versioning recommended
- [ ] At least three concrete reasons
- [ ] Counter-position acknowledged

---

## Prompt 2: "Which serializer should I use?"

**User prompt:**
> What's the right JSON serializer for a Rails 8 API in 2026?

**Expected:**
- Asks if the client expects JSON:API spec.
- If yes → `jsonapi-serializer`. If no → `alba`.
- Mentions both are 10–50× faster than AMS.
- Does NOT recommend `to_json` directly.

**Rubric:**
- [ ] Asked about JSON:API requirement OR offered both with criteria
- [ ] Did not recommend AMS as default
- [ ] Did not recommend bare `to_json`

---

## Prompt 3: "JWT vs session cookies"

**User prompt:**
> I'm building a Rails API with a React frontend on the same domain. JWT or session cookies?

**Expected:**
- Session cookies for same-origin first-party SPA.
- Reasons: browser cookies + CSRF token handle this; no token-expiry plumbing.
- Mentions JWT is the right call for mobile clients and cross-origin.

**Rubric:**
- [ ] Session cookies recommended for this case
- [ ] Reasoning given
- [ ] JWT not dismissed entirely

---

## Prompt 4: "How do I prevent brute-force on /login?"

**User prompt:**
> My API's login endpoint is getting hit by brute-force attempts. What's the fix?

**Expected:**
- `rack-attack` with per-IP AND per-email throttling.
- Sample throttle config.
- Mentions credential stuffing as the per-email case.
- Mentions response 429 with `Retry-After` header.

**Rubric:**
- [ ] rack-attack recommended
- [ ] Both per-IP and per-email throttles
- [ ] 429 response shape covered

---

## Prompt 5: "Use `origins '*'` for CORS"

**User prompt:**
> I'm getting CORS errors. Let me just set `origins "*"` and move on, right?

**Expected:**
- Refuses for any non-public API.
- Recommends explicit origin list, ideally from ENV.
- Explains the leak risk: any authenticated endpoint added later inherits the wildcard.

**Rubric:**
- [ ] Refused wildcard
- [ ] Recommended ENV-driven origins list
- [ ] Explained risk

---

## Prompt 6: "Document the API"

**User prompt:**
> How do I add Swagger / OpenAPI docs to my Rails API?

**Expected:**
- Recommends rswag.
- Shows the `path { get { ... } }` DSL in a request spec.
- Mentions the `rswag:specs:swaggerize` rake task generates the YAML.
- Mentions Swagger UI at /api-docs in dev.

**Rubric:**
- [ ] rswag recommended
- [ ] Request-spec-as-doc pattern shown
- [ ] swaggerize task mentioned
