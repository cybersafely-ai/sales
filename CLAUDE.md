# CLAUDE.md: CyberSafely Sales Organization

This project builds the **sales organization** for **CyberSafely.ai** — an affiliate-driven acquisition system that turns two kinds of partners into tracked, paid-on-results channels that drive parent subscriptions and activations.

> **This folder is being broken off into its own project.** It was seeded from Giancarlo's private CyberSafely contract vault on 2026-11-09. It is self-contained: everything needed to understand and start building the system is in `reference/` and `spec/`. Nothing here depends on the parent vault. See `README.md` for the split checklist.

Owner: **Giancarlo Zaccardelli**. Company sponsor / approver: **Torino Fitzgerald**.

---

## 1. What the sales organization is

A partner program that reaches families through people they already trust, instead of only through principals forwarding a message. Two affiliate channels, one engine:

| Channel | Who | Why |
|---|---|---|
| **Teacher / educator affiliates** | Individual teachers, counselors, therapists, online-safety educators | Credible voices with parent audiences; extends the existing school referral-code model to individuals. |
| **Social-media affiliates** | Parent-focused creators (5k–50k followers), parent-community leaders, customer-parent ambassadors | Parents buy on recommendations from creators they follow; reaches any state, any time of year. |

**One engine for both:** every affiliate gets a unique **code + link + QR**. A parent clicks or types the code → signs up → pays → **activates** (child added, keyboard enabled). The affiliate is **paid on activation** (not sign-up), and we track **revenue generated per affiliate** so payouts and scaling decisions are grounded in real money.

This grew out of contract **Outcome 04 (social)** and the Oct 27 **Parent Affiliate Program** proposal (`reference/affiliate-program-proposal.html`). It is **distinct from** the private contract-deliverable agent system in the parent vault.

---

## 2. The system to build (framework: buy the rails, own the reporting)

Three layers. Do **not** build attribution or payouts from scratch.

| Layer | Job | Build vs buy |
|---|---|---|
| **Attribution + payouts** | Generate link/code/QR, track click→signup→paid, run the affiliate portal, collect W-9s, issue 1099s, pay monthly | **Buy** — Rewardful / FirstPromoter / Tolt / PartnerStack, connected to Stripe by webhook |
| **Revenue truth** | "This family pays $X/yr, activated, still here at 90 days" — the real number, not the platform's guess | **Stripe + HubSpot** — billing event is the source of truth; affiliate code saved on the customer record |
| **Decision layer** (the thing we build) | Per-affiliate funnel, revenue attributed, cost-per-activated-family, payout-approval queue — **counts only** | **Build** — the "Affiliates" view, modeled in `reference/tracking-system-mockup.html`; spec in `spec/tracking-and-payout-system.md` |

**The one engineering question that decides the build:** does a parent sign up and pay on the **website** or **inside the app**? Web = the simple path above. App-store install = the referral link is lost in the store, and we need mobile attribution (Branch / AppsFlyer, deferred deep links) or a required in-app referral-code field. Also confirm the billing system (Stripe assumed).

---

## 3. Reward & payout model (ALL AMOUNTS UNAPPROVED)

Leadership sets every amount and percentage. Nothing below is approved.

- **Pilot model:** flat reward per **activated** family (illustrative: $20) + a free subscription for the creator's own family. Offer top performers a recurring **revenue-share** (model B) after 60 days.
- **Payout rules (apply to every model):** pay on activation, never sign-up · hold 30 days (refund window) · pay monthly · **claw back on refunds** · no self-referrals · no brand-name search-ad bidding · no coupon-site listings.
- **Flow:** link → click (attribution saved) → sign-up (code pre-filled) → paid → activation → reward approved after hold → paid.

---

## 4. Hard rules (carried from the parent vault — do not relax)

1. **Entities are separate.** **CyberSafely.ai** (for-profit; runs and **pays** the program) ≠ **CyberSafely Foundation** (nonprofit, cybersafelyfoundation.org). Never conflate them. The Foundation is not part of this program.
2. **No parent, child or customer PII** anywhere — notes, prompts, dashboards, logs. Counts, rates, school-level totals, record IDs or initials only. Affiliates see **their own counts only**, never a family's data.
3. **Nothing goes out automatically.** Affiliate agreements, creator kits, outreach, posts, HubSpot/Notion writes, and payouts are **drafted and reviewed**; Giancarlo (and the right owner) sends. Payouts: Giancarlo drafts the run, **Torino approves**.
4. **Approved claims only.** Use `reference/approved-claims.md`. It is currently marked **UNAPPROVED** — until that banner is removed, flag **every** product claim as "needs approval." This blocks the creator kit.
5. **FTC disclosure.** Every affiliate post must disclose paid/affiliate relationship (e.g. `#ad`); written into the affiliate agreement.
6. **Honest metrics.** Immature or unavailable measures are **"not yet measurable"**, never 0% or "achieved." 90-day retention is not measurable until the first cohort ages (~March 2027). Keep **submitted** distinct from **verified**.
7. **Pricing:** $150/year per student; schools earn 20% of each subscription every year. Never quote numbers beyond the Partner Guide; never negotiate terms.

> **Relationship to the existing Sales Partnership Program (5% sales commission):** that is a separate, existing program for sales partners. This affiliate system serves parent-facing creators and educators. Keep them distinct in tracking and payouts unless leadership explicitly merges them.

---

## 5. Decision-layer data model (what to build first)

The reporting/payout view needs, per affiliate (counts only):

- **Identity:** name/handle, type (teacher | creator | ambassador | community), unique **code**, link, QR, status (Onboarding | Live | On hold | Paused), pipeline stage (Cold → Contacted → Engaged → Live → Active).
- **Funnel:** clicks → sign-ups → paid → **activated** → retained-90d (the last is "not yet measurable" early).
- **Revenue:** ARR attributed = activated families × their annual subscription (from Stripe).
- **Payout:** reward model applied, amount in hold, amount due this run, lifetime paid.
- **Rollups:** active affiliates, activated families, revenue attributed, payout owed, **cost per activated family** (reward + platform ÷ activated) — the number that decides whether to scale.

Full spec: `spec/tracking-and-payout-system.md`. Working visual: `reference/tracking-system-mockup.html`.

---

## 6. Folder map

```
sales/
├── CLAUDE.md                                  ← this file (project brief + rules)
├── README.md                                  ← what this is, split checklist, provenance
├── reference/
│   ├── affiliate-program-proposal.html        ← the approved-direction proposal (Oct 27)
│   ├── tracking-system-mockup.html            ← the decision-layer UI mockup (Nov 9)
│   ├── company-context.md                     ← self-contained company/product/people/model
│   └── approved-claims.md                     ← product claims (UNAPPROVED) for outbound copy
└── spec/
    └── tracking-and-payout-system.md          ← data model + build plan for the decision layer
```

When real work starts, add `src/` (or the chosen stack), `docs/`, and drafts. Keep outbound drafts reviewed before they leave.

---

## 7. Conventions

- **Style:** short, plain, scannable; lead with the action.
- **Frontmatter** on markdown notes you create: `date`, `type` (brief | spec | draft | decision | metric), `status` (draft | submitted | approved | verified).
- **Counts only** in every artifact, including mockups and sample data — label sample numbers clearly as illustrative.
- **Link, don't copy** authoritative records where they exist; cite the source.
- Before writing outbound copy, re-read rule #4 and run the draft past a claims/entity/PII/pricing check.
