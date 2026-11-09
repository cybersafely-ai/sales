# CyberSafely Sales Organization — project seed

A self-contained starting kit for the affiliate-driven sales organization (teacher + social-media affiliates) for **CyberSafely.ai**. Seeded 2026-11-09 from Giancarlo's private contract vault.

## Start here
- **`CLAUDE.md`** — the project brief and operating rules. Read it first.
- **`spec/tracking-and-payout-system.md`** — what to build (the decision/payout layer).
- **`reference/`** — background: the proposal, the UI mockup, company context, product claims.

## What's inside
```
CLAUDE.md                                   project brief + hard rules
README.md                                   this file
reference/affiliate-program-proposal.html   Oct 27 proposal (the approved direction)
reference/tracking-system-mockup.html       Nov 9 decision-layer UI mockup
reference/company-context.md                self-contained company/product/people/model
reference/approved-claims.md                product claims — UNAPPROVED
spec/tracking-and-payout-system.md          data model + build plan
```

## Provenance — copied, not moved
These files were **copied** so the parent vault keeps working until you split. The originals still live in the vault at:
- `Pilots/2026-10-27 Affiliate Program Proposal.html` → copied to `reference/affiliate-program-proposal.html`
- `Pilots/2026-11-09 Affiliate Tracking System Mockup.html` → copied to `reference/tracking-system-mockup.html`
- `Company/approved-claims.md` → copied to `reference/approved-claims.md`
- `AI Agents/ARCHITECTURE.md` (and `AI Agents/CLAUDE.md`) → condensed into `reference/company-context.md`

**When you break this off into its own repo:** move the whole `sales/` folder out, then in the parent vault delete the two `Pilots/` HTML files (now redundant). Leave `Company/approved-claims.md` and `AI Agents/*` in the vault — they're still used there.

## Heads-up (parent vault only)
The vault's Bash guard hook (`.claude/hooks/guard-private.sh`) matches `/Private/` **case-insensitively**, so it false-positives on the macOS `/private/tmp` scratchpad path and blocks *every* shell command. One-word fix: make that part of the regex case-sensitive (e.g. anchor it as `/Private/` with the `i` flag removed for that alternative, or match `CyberSafely/Private/`). Not carried into this project.

## First decisions (before building)
1. Web vs. in-app parent sign-up, and confirm billing = Stripe (decides the whole attribution approach).
2. Which affiliate platform to buy (Rewardful / FirstPromoter / Tolt / PartnerStack).
3. Reward model + amounts + budget cap — leadership. Everything in here is **unapproved**.
4. Keep CyberSafely.ai vs. Foundation separate; counts only, no PII; nothing outbound without review.
