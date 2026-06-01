# Evals for `devise-pundit-rodauth`

## Prompt 1: "Auth for a new Rails 8 SaaS"

**User prompt:**
> I'm starting a B2B SaaS in Rails 8. Need user signup, login, password reset, email confirmation. What auth stack?

**Expected:**
- Devise + Pundit.
- Devise modules: `:database_authenticatable, :registerable, :recoverable, :rememberable, :validatable, :confirmable, :lockable, :trackable`.
- Pundit policy structure noted.
- Defaults locked in: 12-char password min, confirmable required, lockable after 10 attempts.

**Rubric:**
- [ ] Devise + Pundit
- [ ] Confirmable enabled
- [ ] Lockable + password length set
- [ ] Did not suggest rolling-your-own

---

## Prompt 2: "MFA / WebAuthn needed"

**User prompt:**
> Same app, but compliance says we need MFA with WebAuthn / passkeys. Devise still right?

**Expected:**
- Switches to Rodauth.
- Lists Rodauth's MFA features (otp, webauthn, recovery_codes).
- Notes Devise can be patched (devise-two-factor, devise-passwordless) but it's cleaner with Rodauth.
- Mentions migration is non-trivial — 2-3 sprints.

**Rubric:**
- [ ] Rodauth recommended
- [ ] Features named
- [ ] Migration cost surfaced

---

## Prompt 3: "API auth"

**User prompt:**
> Rails-API app for our mobile client. What auth?

**Expected:**
- devise-jwt OR rodauth-rails JWT.
- Short-lived (15 min) tokens + refresh.
- Denylist revocation strategy.
- Never store secrets in JWT payload.

**Rubric:**
- [ ] devise-jwt or rodauth-rails-jwt
- [ ] Short expiry mentioned
- [ ] Denylist strategy noted

---

## Prompt 4: "Pundit smell"

**User prompt:**
> My PostsController#index does `Post.all`. Is that a problem?

**Expected:**
- Yes — leaks unauthorized records.
- Recommends `policy_scope(Post)`.
- Shows the `Scope` class structure in the policy.
- Recommends `verify_policy_scoped` after_action to catch future regressions.

**Rubric:**
- [ ] Identified the leak
- [ ] policy_scope recommended
- [ ] verify_policy_scoped mentioned

---

## Prompt 5: "CanCanCan or Pundit?"

**User prompt:**
> CanCanCan or Pundit for authorization?

**Expected:**
- Recommends Pundit.
- Reasons: plain Ruby objects, one policy per model, easier to scale.
- Acknowledges CanCanCan is fine for small apps with centralized rules.

**Rubric:**
- [ ] Pundit recommended
- [ ] Reasoning given
- [ ] CanCanCan acknowledged as legitimate

---

## Prompt 6: "Password hashing"

**User prompt:**
> Should I store password hashes with bcrypt or something faster?

**Expected:**
- bcrypt (Devise default).
- Tuned cost factor (`stretches: 12`).
- Adds `pepper` from credentials.
- Refuses MD5/SHA1.

**Rubric:**
- [ ] bcrypt recommended
- [ ] Cost factor set
- [ ] Pepper added
- [ ] Weak hash algorithms refused
