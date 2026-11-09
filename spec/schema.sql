-- CyberSafely Sales — commission engine schema (readable overview)
-- SOURCE OF TRUTH is supabase/migrations/*.sql (validated, deployable).
-- This file is a human-readable sketch; it omits RLS. See the migrations for:
--   * school.payee_party_id (the school's 20% is paid to a payee PARTY, not the school row)
--   * RLS policies, auth/staff model, and the payout-approval trigger (migration 0002)
-- Postgres / Supabase dialect. Encodes spec/commission-model.md.
-- Rule: NO parent/child/subscriber PII. Parties = affiliates/staff we pay only.
-- All money in integer cents. All rates versioned in a table, never hardcoded.

-- ============================================================
-- 1. Reference: schools and the parties we pay
-- ============================================================

create table school (
    id            uuid primary key default gen_random_uuid(),
    name          text not null,
    external_ref  text,                       -- district/MO-directory id if any
    created_at    timestamptz not null default now()
);

-- A party is anyone who can earn a share: teacher, principal, agent, school POC.
-- Subscribers are NOT parties and are never stored here.
create type party_role as enum ('school', 'principal', 'agent', 'teacher');

create table party (
    id            uuid primary key default gen_random_uuid(),
    display_name  text not null,
    kind          text not null,              -- 'teacher' | 'principal' | 'sales_partner' | 'creator' | 'school_poc'
    email         text,                       -- affiliate contact (payee), not a subscriber
    school_id     uuid references school(id), -- home school, if applicable
    -- recursive referral upline: who recruited this party. Enables the 2% agent chain.
    upline_id     uuid references party(id),
    status        text not null default 'onboarding', -- onboarding|live|on_hold|paused
    code          text unique,                -- affiliate code / link join key
    created_at    timestamptz not null default now(),
    constraint no_self_upline check (upline_id is null or upline_id <> id)
);
-- NOTE: cycle prevention beyond the self check is enforced in app code (acyclic upline).

create index on party (upline_id);
create index on party (school_id);

-- ============================================================
-- 2. Versioned commission rates (approved; editable by leadership)
-- ============================================================

create table commission_rate (
    id             uuid primary key default gen_random_uuid(),
    role           party_role not null,
    rate_bps       integer not null,          -- basis points: 2000 = 20%, 500 = 5%, 200 = 2%
    effective_from date not null,
    effective_to   date,                      -- null = current
    approved_by    text,                       -- e.g. 'Torino Fitzgerald'
    source         text,                       -- citing PDF/decision
    created_at     timestamptz not null default now()
);

-- Seed: approved split from the leave-behind PDFs (2026-09-01 / Teacher v1.0)
insert into commission_rate (role, rate_bps, effective_from, approved_by, source) values
  ('school',    2000, '2026-09-01', 'leadership', 'District/Teacher leave-behind'),
  ('principal',  200, '2026-09-01', 'leadership', 'Teacher leave-behind v1.0'),
  ('agent',      200, '2026-09-01', 'leadership', 'Teacher leave-behind v1.0'),
  ('teacher',    500, '2026-09-01', 'leadership', 'Teacher leave-behind v1.0');

-- ============================================================
-- 3. Subscriptions (attributed, NO subscriber PII)
-- ============================================================

create table subscription (
    id                uuid primary key default gen_random_uuid(),
    school_id         uuid references school(id),   -- school the 20% is attributed to
    teacher_id        uuid references party(id),    -- the 5% earner; agent is derived from teacher's upline
    principal_id      uuid references party(id),    -- the 2% principal
    reward_model      text not null default 'split',-- 'split' (this model) | 'flat_creator' (unapproved, separate)
    amount_cents      integer not null default 15000, -- $150.00 actual charge
    stripe_customer   text,                          -- opaque Stripe id, not a name
    status            text not null default 'pending', -- pending|paid|active|churned|refunded
    activated_at      timestamptz,                   -- child added + keyboard enabled
    started_at        timestamptz not null default now()
    -- intentionally NO parent/child name, email, or device columns.
);
create index on subscription (school_id);
create index on subscription (teacher_id);

-- Each billing period (initial + renewals). One paid charge = one row.
create table subscription_period (
    id               uuid primary key default gen_random_uuid(),
    subscription_id  uuid not null references subscription(id),
    period_start     date not null,
    period_end       date not null,
    amount_cents     integer not null,
    stripe_charge_id text,
    paid_at          timestamptz,
    refunded_at      timestamptz,                  -- set on refund -> triggers clawback
    created_at       timestamptz not null default now()
);
create index on subscription_period (subscription_id);

-- ============================================================
-- 4. Payout runs — draft (Giancarlo) -> approve (Torino) -> paid
--    (defined before accrual because accrual references it)
-- ============================================================

create table payout_run (
    id            uuid primary key default gen_random_uuid(),
    period_label  text not null,                 -- e.g. '2026-11'
    status        text not null default 'draft', -- draft|approved|paid
    drafted_by    text,                           -- Giancarlo Zaccardelli
    approved_by   text,                           -- Torino Fitzgerald (required before paid)
    total_cents   integer not null default 0,
    created_at    timestamptz not null default now(),
    approved_at   timestamptz,
    paid_at       timestamptz
);

-- ============================================================
-- 5. Accruals — one row per (period x role x payee). The ledger.
-- ============================================================

create type accrual_status as enum ('held', 'payable', 'paid', 'clawed_back');

create table accrual (
    id                     uuid primary key default gen_random_uuid(),
    subscription_period_id uuid not null references subscription_period(id),
    party_id               uuid not null references party(id),   -- the payee
    role                   party_role not null,                  -- which share this is
    rate_bps               integer not null,                     -- snapshot of rate at accrual time
    amount_cents           integer not null,                     -- base * rate_bps / 10000
    status                 accrual_status not null default 'held',
    hold_until             date not null,                        -- paid_at + 30d refund window
    payout_run_id          uuid references payout_run(id),
    created_at             timestamptz not null default now()
);
create index on accrual (party_id, status);
create index on accrual (payout_run_id);

-- ============================================================
-- 6. Resolution notes
-- ============================================================
-- Resolution notes (app logic, not SQL):
--   agent on a subscription = (select upline_id from party where id = subscription.teacher_id)
--   a null role party => that share is retained by the company (not redistributed)
--   accrual.amount_cents = floor(period.amount_cents * rate_bps / 10000)
--   on refund: mark matching accruals 'clawed_back' (if unpaid) or queue a negative adjustment (if already paid)
