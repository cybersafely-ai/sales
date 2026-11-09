---
date: 2026-11-09
type: spec
status: approved
source: "1a. CyberSafely-District-Leave-Behind-Final-v2-9-1-2026.pdf; 2. TEACHERS_CyberSafely-Teacher-Leave-Behind-v1.0.pdf"
---
# Spec: Commission model — the revenue-share engine

The authoritative money model for the backend, extracted from the two finalized leave-behind PDFs (District v2 dated 2026-09-01; Teacher v1.0). These percentages and the price are **approved** (leadership direction, 2026-11-09) and govern the payout engine. They supersede the "all amounts unapproved" placeholder in CLAUDE.md §3 for *this* commission structure.

> Still unapproved and config-gated: any amount **not** printed in these PDFs (e.g. the separate pilot "flat $20 per activated family" creator model in CLAUDE.md §3). Rates live in a `commission_rate` table, not hardcoded, so leadership can version them.

## 1. Constants

| Key | Value | Source |
|---|---|---|
| `subscription_price` | **$150.00 / student / year** | Both PDFs |
| `billing_cycle` | annual, auto-renewing | "every year those families stay enrolled" |
| `currency` | USD | — |

## 2. The split — applied to every paid subscription, every renewal

Each role earns a fixed percentage of the subscription amount, recurring on **every annual renewal**, for as long as the subscription stays active.

| Role | Rate | Per $150 sub | Payable while |
|---|---|---|---|
| `school` | 20% | $30.00 | subscription active |
| `principal` | 2% | $3.00 | subscription active |
| `agent` | 2% | $3.00 | subscription active |
| `teacher` | 5% | $7.50 | subscription active |
| **total paid out** | **29%** | **$43.50** | — |
| `company_retained` | 71% | $106.50 | — |

- **school** — the school the subscription is attributed to. The 20% fundraiser share. Paid to the school's **payee party** (`school.payee_party_id`), since every accrual in the ledger is to a party.
- **principal** — the principal of that school.
- **agent** — "whoever introduced you to CyberSafely.ai." The **upline** of the teacher (see §4). May be another teacher, a sales partner, or empty.
- **teacher** — the educator who brought in the family/classroom. This is the same role as the existing "Sales Partnership Program" 5% earner; the teacher channel and that program are unified by this split.

A role with no assigned party on a given subscription earns nothing; its share is **retained by the company** (not redistributed). So `company_retained = 71% + (unassigned role rates)`.

## 3. Calculation

Per paid subscription-period (initial or renewal):

```
base = subscription_amount                      # $150 default, from the actual Stripe charge
for role in [school, principal, agent, teacher]:
    party = resolve_party(subscription, role)    # may be null
    if party is not null:
        accrue(party, role, base * rate[role], period)
```

Guardrails (carried from CLAUDE.md §3 / spec/tracking-and-payout-system.md):
- Accrue on **paid**, pay on **activation** (child added + keyboard enabled) past the **30-day hold** (refund window).
- **Claw back** the full role accrual if the underlying charge is refunded.
- No self-referrals. Monthly payout runs. Giancarlo drafts the run → **Torino approves** → pay. No automatic money movement.
- Counts only in all reporting; **no parent/child/family PII** ever (see §6).

## 4. Referral graph (the recursive Agent chain)

The Teacher PDF: *"If you introduce another teacher to CyberSafely.ai, you become their Agent — earning 2% on their pilot, on top of your own 5%."*

So **agent is not a flat field** — it is resolved from an **upline edge** on the party who holds the `teacher` role for that subscription:

```
teacher_of(subscription) = T
agent_of(subscription)   = upline(T)      # the party who recruited T; may be null
```

- A party can be the `teacher` on their own subscriptions **and** the `agent` on their recruits' subscriptions, simultaneously — two independent accrual streams.
- The chain is **one hop for payout** (teacher earns 5% own + 2% on each direct recruit). It is **not** unlimited multi-level: only the direct upline earns the 2% agent share. Deeper ancestors earn nothing on that subscription (no printed basis for more).
- Guard against cycles: `upline` must be acyclic; a party cannot be their own upline (also blocks self-referral).

Worked check (Teacher PDF, both at 50%, school-wide): own classroom 5% = $9,375 + one colleague's classroom as agent 2% = $3,750 → **$13,125**. ✓ Matches schema math.

## 5. Scaling / projection math (for the modeling UI, illustrative)

Linear in paying students. `paying = students × participation_rate`; `total_raised = paying × $150`; each role = `total_raised × rate`. Standard participation tiers shown in collateral: **25 / 50 / 75 / 100%** (50% is the highlighted default). These feed an *estimator* view only — flag outputs as "estimates, not promises," never as earned/owed.

## 6. PII rule (hard)

Parties in the payout engine are **affiliates/staff** (teacher, principal, agent, school point-of-contact) — their identity is in scope because we pay them. **Subscribers (parents/children) are never identified.** A subscription is referenced by an opaque `id` + its attributed `school_id` + role assignments + Stripe charge id. No parent name, child name, email, or device data in any table, log, or view. Reporting is counts and dollar rollups only.

## 7. Open questions (do not block schema)

- **Attribution overlap:** if a *creator/social* affiliate (CLAUDE.md flat model) brings a family whose child's school is also enrolled, does the school still earn 20%? (CLAUDE.md §7 open Q.) Schema supports both by allowing any role to be null per subscription; policy TBD.
- **Agent on principal/school:** PDFs define agent only as the teacher's upline. Assume agent share is **0 / retained** when a subscription has a school+principal but no teacher (e.g. principal-led direct enrollment) unless leadership says the introducer still earns 2%.
- **Creator flat model** ($20/activation + free sub) stays a **separate reward model**, not part of this split — gate behind config, mark unapproved.
