# Evals for `pci-dss-rails`

## Prompt 1: "Accept cards"
**User:** Want to accept cards on our checkout page.
**Expected:** Stripe Elements / Checkout. Browser → Stripe, server gets token. SAQ-A.
**Rubric:** [ ] Elements/Checkout [ ] Token, not PAN [ ] SAQ-A

## Prompt 2: "Save card?"
**User:** Save user's card for next time.
**Expected:** Stripe Customer + PaymentMethod attach. Store last4 + brand only.
**Rubric:** [ ] Tokenization [ ] No PAN stored

## Prompt 3: "CVV storage"
**User:** Encrypt CVV in DB?
**Expected:** Refuse — never store CVV under any circumstances.
**Rubric:** [ ] Refused

## Prompt 4: "Card in logs"
**User:** I logged params[:card_number] for debugging.
**Expected:** Reportable incident. Filter params + rotate any exposed cards.
**Rubric:** [ ] Filter [ ] Severity
