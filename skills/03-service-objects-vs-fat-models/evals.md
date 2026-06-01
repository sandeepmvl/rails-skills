# Evals for `service-objects-vs-fat-models`

## Prompt 1: Premature service extraction

**User prompt:**
> I want to refactor my PostsController#publish action into a service object.
>
> ```ruby
> def publish
>   @post = Post.find(params[:id])
>   @post.update(published_at: Time.current, status: "published")
>   redirect_to @post
> end
> ```

**Expected:**
- Refuses the service-object extraction.
- Recommends `Post#publish!` instance method instead.
- Explains: workflow is one model + one method, no external call, no multi-outcome branching.

**Rubric:**
- [ ] Refused premature extraction
- [ ] Suggested model method
- [ ] Explained the "earn it" trigger criteria

---

## Prompt 2: Multi-model checkout

**User prompt:**
> I'm building a checkout flow. The controller needs to: create an Order, decrement Product stock, charge Stripe, send a confirmation email. Where does this logic go?

**Expected:**
- Recommends a service object (e.g. `PlaceOrder`).
- Shows the structure with `Data.define(:success?, :order, :error)` Result.
- Shows the controller case-statement pattern matching the Result.
- Notes that the confirmation email should be enqueued via `deliver_later` in `after_commit` on Order — not synchronous in the service.

**Rubric:**
- [ ] Recommended service object
- [ ] Multi-model transactional shape correct
- [ ] Result type used for branching
- [ ] Email is async, not sync

---

## Prompt 3: Naming a service

**User prompt:**
> Should I call my checkout service `OrderService`, `OrderManager`, `CheckoutService`, or `Checkout`?

**Expected:**
- Recommends `PlaceOrder` (VerbNoun, no Service suffix).
- Explains why `OrderService` becomes a god class.
- Explains why `Manager` and `Handler` are vague.

**Rubric:**
- [ ] Recommended VerbNoun form
- [ ] Rejected Service / Manager / Handler suffixes
- [ ] Gave the "god class" reason

---

## Prompt 4: Should I use dry-monads?

**User prompt:**
> I want to use dry-monads in my new Rails project for Result types. Good idea?

**Expected:**
- Recommends `Data.define` for new projects unless team already uses dry-monads.
- Explains the cost: every dev must learn the monadic vocabulary.
- Acknowledges dry-monads is fine in teams that have chosen it.

**Rubric:**
- [ ] Did not auto-recommend dry-monads
- [ ] Recommended Data.define as default
- [ ] Acknowledged dry-monads has a place

---

## Prompt 5: Service that should be a job

**User prompt:**
> I extracted my Hubspot sync into `SyncToHubspot` service. The controller calls it inline but my response times went up by 800ms.

**Expected:**
- Identifies the issue: synchronous external call in the request path.
- Recommends extracting to a job (`SyncToHubspotJob.perform_later`).
- Notes the job can call the service: `SyncToHubspot.call(contact)`.

**Rubric:**
- [ ] Diagnosed sync-call-in-request issue
- [ ] Recommended background job
- [ ] Kept the service; wrapped it in a job (not replaced it)

---

## Prompt 6: When the user asks "should I always use service objects"

**User prompt:**
> Should I always put my business logic in service objects?

**Expected:**
- Refuses the always-extract rule.
- Restates the four trigger conditions for extraction.
- Defends fat models as the default.

**Rubric:**
- [ ] Did not endorse always-extracting
- [ ] Listed the four triggers
- [ ] Cited DHH/fat-models position
