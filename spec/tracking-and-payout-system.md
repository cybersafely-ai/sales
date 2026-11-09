---
date: 2026-11-09
type: spec
status: draft
---
# Spec: Affiliate tracking & payout — the decision layer

What to build. The attribution and payouts are **bought** (platform + Stripe); this spec covers the **decision layer** we own: the view that shows revenue per affiliate and drives payout approval. Working visual: `../reference/tracking-system-mockup.html`.

## 1. Scope

**In scope:** per-affiliate funnel + revenue, payout calculation and approval queue, rollup KPIs, affiliate roster/pipeline — **counts only, no PII**.
**Out of scope (bought):** link/code/QR generation, click tracking, the affiliate-facing portal, W-9/1099 collection, the actual money movement.

## 2. Data sources

| Source | Gives us | Mode |
|---|---|---|
| Affiliate platform (Rewardful / FirstPromoter / …) | affiliate roster, codes, clicks, sign-ups, platform's paid events | read (API / export) |
| **Stripe** | source of truth for paid + subscription value (ARR), refunds | read (webhook / API) |
| App backend | **activation** event (child added + keyboard enabled) per referred account | read |
| HubSpot | affiliate as a contact; parent record's "referral source" property | read / configure |

The affiliate **code** is the join key, saved on the customer record. Credit rule: **last affiliate before sign-up** gets the attribution.

## 3. Entities (counts only)

```
Affiliate
  id, name/handle, type [teacher|creator|ambassador|community],
  code, link, qr, status [onboarding|live|on_hold|paused],
  pipeline_stage [cold|contacted|engaged|live|active],
  reward_model [flat|revshare|tier], joined_at

AffiliateStats (rolling / per-period, per affiliate)
  clicks, signups, paid, activated, retained_90d (nullable → "not yet measurable"),
  arr_attributed            # = activated families × their annual subscription (Stripe)

Payout (per affiliate per run)
  period, activated_in_period, gross_due, in_hold, clawbacks, net_due,
  status [pending|approved|paid|held], approved_by, paid_at
```

No child, parent, or family identifiers anywhere. Reference families by count only.

## 4. Payout calculation

```
gross_due   = activated_families_past_hold × reward_per_activation      # flat model
            | sum(subscription_value × revshare_pct)                     # revshare model
net_due     = gross_due − clawbacks(refunds in window)
in_hold     = rewards for activations still inside the 30-day refund window
```

Rules enforced in code: pay on activation not sign-up · 30-day hold before payable · monthly runs · clawback on refund · exclude self-referrals. Every amount/percentage is **config, set by leadership, currently unapproved**.

## 5. Views

1. **KPI row** — active affiliates, activated families, ARR attributed, payout owed (+ on hold), **cost per activated family**.
2. **Attribution funnel** (all affiliates) — clicks → sign-ups → paid → activated → retained-90d.
3. **Per-affiliate table** — code, clicks, sign-ups, activated, revenue (ARR), payout due, status; sorted by revenue.
4. **Payout run** — approval queue: Giancarlo drafts, **Torino approves**; held rewards shown separately.
5. **Guardrails panel** — the standing payout rules, visible on the screen.

## 6. Build order

1. **Decide web vs. in-app sign-up** (blocks attribution approach — see CLAUDE.md §2) and confirm billing = Stripe.
2. Stand up the bought platform in a sandbox; connect Stripe test mode; confirm clicks→signup→paid flow.
3. Wire the **activation** event from the app backend to the affiliate record.
4. Build the decision layer read-only over those sources (start with a static export, then API). Ship the KPI row + per-affiliate table first.
5. Add the payout calculation + approval queue. Keep it draft-and-approve; no automatic money movement.
6. Add pipeline/roster management (recruit → onboard affiliates), reusing the Lead Manager "Affiliates list" idea.

## 7. Open questions

- Web vs. in-app sign-up; billing system (Stripe?).
- Which affiliate platform (Rewardful / FirstPromoter / Tolt / PartnerStack) — pricing to quote.
- Reward model + amounts + budget cap (leadership).
- School credit: if a parent signs up through a creator, does their child's school still earn its 20%?
- Does the existing Sales Partnership Program (5% commission) stay separate or merge?
- Approved claims (blocks the creator/affiliate kit).
