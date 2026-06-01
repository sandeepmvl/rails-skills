# Evals for `kamal-docker-production`

## Prompt 1: "Alpine for the Ruby base?"

**User prompt:**
> Should I base my Dockerfile on `ruby:3.3-alpine` for the smaller image?

**Expected:**
- Refuses alpine for Rails.
- Reasons: musl libc breaks subtly with nokogiri, pg, sassc, libvips.
- Recommends `ruby:3.3-slim` (debian).
- Mentions the ~50MB difference isn't worth the debugging.

**Rubric:**
- [ ] Refused alpine
- [ ] Cited specific native gems that break
- [ ] Recommended slim

---

## Prompt 2: "Single-stage Dockerfile"

**User prompt:**
> My Dockerfile is one stage. Image is 1.2GB. Help.

**Expected:**
- Multi-stage: build (with build-essential, dev libs) + runtime (slim).
- Copies bundle path and app code from build stage to runtime.
- Strips test/dev gems via `BUNDLE_WITHOUT`.
- Saves ~400MB typical.

**Rubric:**
- [ ] Multi-stage proposed
- [ ] Build vs runtime separation explained
- [ ] BUNDLE_WITHOUT mentioned

---

## Prompt 3: "Where do I put secrets?"

**User prompt:**
> I need to pass STRIPE_SECRET_KEY to the production container. Where?

**Expected:**
- Rails credentials (`credentials.yml.enc`) OR Kamal `env.secret` (from `.kamal/secrets`).
- Refuses placing in Dockerfile.
- Refuses placing in `env.clear`.
- Explains why each location is right for which kind of secret.

**Rubric:**
- [ ] Suggested credentials or Kamal env.secret
- [ ] Rejected Dockerfile / env.clear
- [ ] Explained per-layer

---

## Prompt 4: "Migrations on container boot"

**User prompt:**
> I'm running `rails db:migrate` in my docker-entrypoint script. Tests pass but deploys are flaky.

**Expected:**
- Identifies race: multiple containers run migrate on rolling deploy → advisory-lock contention.
- Recommends moving migrate to Kamal `deploy.hooks.pre-deploy` or a dedicated `migrate` role.
- `db:prepare` is fine for first-time boot but not for migrations on rolling deploy.

**Rubric:**
- [ ] Diagnosed race
- [ ] Moved to deploy hook
- [ ] Did not just say "add a lock"

---

## Prompt 5: "Health check"

**User prompt:**
> Kamal Proxy isn't routing traffic to my new deploy. What's the health check?

**Expected:**
- `/up` (Rails 8 built-in).
- 200 from `/up` = container is ready.
- For deeper checks, add a separate `/health` endpoint.
- Kamal Proxy's `healthcheck.path: /up` in deploy.yml.

**Rubric:**
- [ ] /up mentioned
- [ ] Built-in route confirmed
- [ ] Deeper health endpoint distinguished

---

## Prompt 6: "Logs disappear on redeploy"

**User prompt:**
> I'm tailing `/rails/log/production.log` and the file empties on every deploy.

**Expected:**
- Files inside containers vanish on redeploy.
- Recommends `RAILS_LOG_TO_STDOUT=1` (already in Rails 8 Dockerfile).
- Ship stdout to a durable backend: AWS CloudWatch, Loki, Datadog.
- Mentions docker logging driver or sidecar.

**Rubric:**
- [ ] Explained ephemeral container files
- [ ] STDOUT recommended
- [ ] Durable-backend strategy mentioned
