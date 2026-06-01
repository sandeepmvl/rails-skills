---
name: pci-dss-rails
description: PCI-DSS compliance for Rails apps handling card data — the "don't touch PAN" rule, tokenization with Stripe / Braintree / Adyen, why hosted fields + Stripe Elements minimize scope to SAQ-A, the 12 PCI requirements, what counts as "cardholder data," logging hygiene to keep cards out of logs. Use when the user mentions PCI, PCI-DSS, PAN, cardholder data, credit card, tokenization, hosted fields, Stripe Elements, SAQ-A vs SAQ-D, payment compliance, or asks "can we just accept cards directly in our Rails form." The answer is almost always no — this skill explains why and how to do it right.
---

# PCI-DSS for Rails

> PCI-DSS is the card brands' security standard. If your app touches Primary Account Numbers (PAN), the standard applies. The cheapest path to compliance: don't touch PAN. Use Stripe Elements / Braintree Hosted Fields. The card data never enters your servers. This skill is short by design — the long version is "delegate to a PCI Level 1 provider."

## The opinion

> **NEVER store, transmit, or process PAN (the long card number) on your servers. Use Stripe Elements, Braintree Hosted Fields, or Adyen Drop-In — the iframe approach. Card data goes browser → payment processor, you get a token. This keeps you at SAQ-A scope (the lightest PCI questionnaire). Anything else (SAQ-A-EP, SAQ-D) blows up your compliance scope. NEVER log card numbers anywhere.**

## What is PCI-DSS?

The Payment Card Industry Data Security Standard, v4.0. 12 requirements, ~300 controls. Annual audit for high-volume merchants; self-assessment questionnaires (SAQ) for smaller ones.

| SAQ | Who | Scope |
|---|---|---|
| **SAQ-A** | E-commerce, fully outsourced to provider | Lightest — confirm provider compliance, no card data on your servers |
| **SAQ-A-EP** | E-commerce, partial outsourcing (e.g., you redirect through your server) | Bigger — your servers are in scope |
| **SAQ-D** | You store / process / transmit PAN | Massive — full 300+ controls, annual audit |

You want SAQ-A. Period.

## Pattern 1: Stripe Elements (the right way)

Use the **client-confirmation flow** — the server creates a PaymentIntent up front, sends its `client_secret` to the browser, and the browser confirms via Stripe.js (which handles 3DS2/SCA in a Stripe-hosted iframe).

```ruby
# app/controllers/checkouts_controller.rb — create the intent before rendering.
class CheckoutsController < ApplicationController
  def new
    @intent = Stripe::PaymentIntent.create(
      amount: 1000,
      currency: "usd",
      automatic_payment_methods: { enabled: true }
    )
  end
end
```

```erb
<!-- app/views/checkouts/new.html.erb -->
<form id="payment-form" data-client-secret="<%= @intent.client_secret %>">
  <div id="payment-element"><!-- Payment Element injects here --></div>
  <div id="card-errors" role="alert"></div>
  <button type="submit">Pay</button>
</form>

<script src="https://js.stripe.com/v3/"></script>
<script>
  const stripe = Stripe('<%= ENV["STRIPE_PUBLISHABLE_KEY"] %>')
  const clientSecret = document.querySelector('#payment-form').dataset.clientSecret
  const elements = stripe.elements({ clientSecret })
  elements.create('payment').mount('#payment-element')

  document.querySelector('#payment-form').addEventListener('submit', async (e) => {
    e.preventDefault()

    const { error } = await stripe.confirmPayment({
      elements,
      confirmParams: { return_url: window.location.origin + '/checkouts/complete' }
    })

    if (error) {
      document.querySelector('#card-errors').textContent = error.message
    }
  })
</script>
```

```ruby
# app/controllers/checkouts_controller.rb — confirm + reconcile in the return handler.
def complete
  intent = Stripe::PaymentIntent.retrieve(params[:payment_intent])
  # intent.status: "succeeded" | "requires_action" | "requires_payment_method" | ...
end
```

**Why client-confirm:** Stripe.js handles the 3DS2 challenge for EU/UK SCA-required cards in a Stripe-hosted iframe. The legacy `confirm: true` server-side variant bypasses this and gets EU cards declined.

**What just happened:**
- Card data went from browser to Stripe (via the Payment Element).
- 3DS2 challenge ran in a Stripe-hosted iframe if required.
- Your server only ever saw the `PaymentIntent` ID and `client_secret`.
- You're SAQ-A scope.

## Pattern 2: Stripe Checkout (even simpler)

```ruby
# Redirect to Stripe's hosted page; they handle EVERYTHING
session = Stripe::Checkout::Session.create(
  payment_method_types: ["card"],
  line_items: [{ price: "price_xxx", quantity: 1 }],
  mode: "payment",
  success_url: success_checkout_url,
  cancel_url: cancel_checkout_url
)
redirect_to session.url, allow_other_host: true
```

Card data: browser → Stripe (hosted page) → your callback URL. SAQ-A.

Even simpler than Elements. Use when you don't need custom checkout UI.

## Pattern 3: Never log PAN

```ruby
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += %i[
  card_number card cvv cvc expiry pan
  credit_card cc_number
]
```

In Sentry (`rails-security-baseline`):

```ruby
Sentry.init do |config|
  config.before_send = lambda do |event, _hint|
    scrub_card_data!(event)
    event
  end
end
```

Audit your logs for accidental card leakage. A single `Rails.logger.info(params)` with a card number is a reportable incident.

## Pattern 4: Tokenization for saved cards

If a user wants to save a card for later:

```ruby
customer = Stripe::Customer.create(email: user.email)
payment_method = Stripe::PaymentMethod.attach(params[:payment_method_id], customer: customer.id)

# Store: customer.id, payment_method.id, payment_method.card.last4, payment_method.card.brand
# DO NOT store: full PAN, CVV, full expiry
user.update!(
  stripe_customer_id: customer.id,
  default_payment_method_id: payment_method.id,
  card_last4: payment_method.card.last4,
  card_brand: payment_method.card.brand
)
```

`last4` and brand are not "cardholder data" for storage rules. Full PAN is.

## Pattern 5: CVV — NEVER stored

Period. Not encrypted. Not hashed. Not logged. Not even briefly. Even Stripe's saved-card tokens don't include CVV — every charge requires a fresh authentication or 3DS.

If your code touches a CVV: that code lives in the browser → Stripe iframe, never on your server.

## Pattern 6: The 12 PCI-DSS requirements (high level)

For SAQ-A merchants, simplified:
1. Firewall / network segmentation — your hosting provider's job.
2. No default passwords — use ENV / credentials.
3. Protect stored cardholder data — NOT APPLICABLE (you don't store it).
4. Encrypt transmission — TLS everywhere, HSTS. See `rails-security-baseline`.
5. Anti-malware — your hosting provider's job for shared infra.
6. Secure systems and apps — patch Ruby / Rails / OS regularly.
7. Restrict access by need-to-know — RBAC, Pundit.
8. Identify and authenticate access — strong auth, MFA for admin.
9. Restrict physical access — your hosting provider's job.
10. Log and monitor all access — see `observability-rails-advanced`.
11. Test security — penetration testing annually.
12. Security policy — written, reviewed annually.

For SAQ-A: requirements 3, 4, 5, 9 are largely your provider's responsibility.

## Pattern 7: Webhooks from Stripe

See `stripe-webhook-integration`. Stripe webhooks don't carry full PAN — just `last4`, `brand`, status, IDs. Safe to log + persist with normal patterns.

## Pattern 8: International cards / Strong Customer Authentication

EU PSD2 + UK FCA require Strong Customer Authentication (SCA / 3DS2). Stripe handles via `automatic_payment_methods` + `confirm: true` flow:

```ruby
intent = Stripe::PaymentIntent.create(
  payment_method: params[:payment_method_id],
  amount: 1000,
  currency: "eur",
  confirm: true,
  return_url: confirm_payment_url,
  automatic_payment_methods: { enabled: true }
)

if intent.status == "requires_action"
  # Front-end uses Stripe.js to handle the 3DS challenge
end
```

3DS challenges happen in Stripe-hosted iframes. You don't touch them.

## Common mistakes to refuse

- Don't accept card data in a Rails form `<input>`. Use Elements / Hosted Fields.
- Don't proxy card data through your server. SAQ-A-EP scope explodes.
- Don't store CVV. Ever.
- Don't store full PAN. Use tokens.
- Don't log unfiltered params with card fields.
- Don't email card numbers to support.
- Don't share Stripe secret keys outside ENV / credentials.
- Don't roll your own PCI scope reduction. Use a payment processor.

## When PCI-DSS doesn't apply

- You don't take card payments. Apple Pay / Google Pay via PaymentRequest API still uses tokenized backend (you DO need to think about it).
- You use Apple Pay / Google Pay exclusively via a payment processor — same SAQ-A path.
- You accept ACH / bank transfer only. Different rules (NACHA), not PCI.

## See also

- `stripe-webhook-integration` — handling Stripe events
- `rails-security-baseline` — TLS, HSTS, secret management
- `observability-baseline` — log filtering
- `devise-pundit-rodauth` — auth for admin / privileged access

## Sources

- [PCI-DSS v4.0 Standard](https://www.pcisecuritystandards.org/document_library/)
- [Stripe Elements](https://stripe.com/docs/payments/elements)
- [Stripe Checkout](https://stripe.com/docs/payments/checkout)
- [Stripe PCI guide](https://stripe.com/docs/security/guide)
- [Braintree Hosted Fields](https://developers.braintreepayments.com/guides/hosted-fields/overview/javascript/v3)
- [SAQ A guidance](https://www.pcisecuritystandards.org/document_library?category=saqs#results)
- [Strong Customer Authentication / 3DS2](https://stripe.com/guides/strong-customer-authentication)
