-- CyberSafely Sales — commission engine: core schema
-- Source of truth for the data model. Design notes: ../../spec/commission-model.md
-- Dialect: Postgres 17 (Supabase). Money in integer cents. Rates in basis points.
-- HARD RULE: no subscriber (parent/child) PII in any table.

-- ------------------------------------------------------------
-- Enums
-- ------------------------------------------------------------
create type party_role      as enum ('school', 'principal', 'agent', 'teacher');
create type party_kind      as enum ('teacher', 'principal', 'sales_partner', 'creator', 'school_poc');
create type party_status    as enum ('onboarding', 'live', 'on_hold', 'paused');
create type sub_status       as enum ('pending', 'paid', 'active', 'churned', 'refunded');
create type reward_model     as enum ('split', 'flat_creator');
create type accrual_status   as enum ('held', 'payable', 'paid', 'clawed_back');
create type payout_status    as enum ('draft', 'approved', 'paid');

-- ------------------------------------------------------------
-- Schools
-- ------------------------------------------------------------
create table school (
    id            uuid primary key default gen_random_uuid(),
    name          text not null,
    external_ref  text,                         -- district / MO-directory id if any
    created_at    timestamptz not null default now()
);

-- ------------------------------------------------------------
-- Parties = people/orgs we PAY (teacher, principal, agent, school POC).
-- Subscribers (parents/children) are NEVER parties and never stored.
-- ------------------------------------------------------------
create table party (
    id            uuid primary key default gen_random_uuid(),
    display_name  text not null,
    kind          party_kind not null,
    email         text,                          -- payee contact, not a subscriber
    school_id     uuid references school(id),
    upline_id     uuid references party(id),     -- recursive referral: who recruited this party -> enables 2% agent chain
    status        party_status not null default 'onboarding',
    code          text unique,                   -- affiliate code / link join key
    created_at    timestamptz not null default now(),
    constraint no_self_upline check (upline_id is null or upline_id <> id)
);
create index party_upline_idx on party (upline_id);
create index party_school_idx on party (school_id);

-- The school's 20% is paid to a payee party (the school's account/POC).
-- Added after `party` exists because school<->party reference each other.
alter table school add column payee_party_id uuid references party(id);

-- ------------------------------------------------------------
-- Versioned commission rates (approved; leadership-editable, never hardcoded)
-- ------------------------------------------------------------
create table commission_rate (
    id             uuid primary key default gen_random_uuid(),
    role           party_role not null,
    rate_bps       integer not null check (rate_bps between 0 and 10000),  -- 2000 = 20%
    effective_from date not null,
    effective_to   date,                          -- null = current
    approved_by    text,
    source         text,
    created_at     timestamptz not null default now(),
    constraint rate_range check (effective_to is null or effective_to >= effective_from)
);
-- only one open (current) rate per role
create unique index commission_rate_one_current
    on commission_rate (role) where (effective_to is null);

-- Seed: approved split from the finalized leave-behind PDFs
insert into commission_rate (role, rate_bps, effective_from, approved_by, source) values
  ('school',    2000, '2026-09-01', 'leadership', 'District/Teacher leave-behind'),
  ('principal',  200, '2026-09-01', 'leadership', 'Teacher leave-behind v1.0'),
  ('agent',      200, '2026-09-01', 'leadership', 'Teacher leave-behind v1.0'),
  ('teacher',    500, '2026-09-01', 'leadership', 'Teacher leave-behind v1.0');

-- ------------------------------------------------------------
-- Subscriptions (attributed; NO subscriber PII)
-- ------------------------------------------------------------
create table subscription (
    id               uuid primary key default gen_random_uuid(),
    school_id        uuid references school(id),   -- school the 20% is attributed to
    teacher_id       uuid references party(id),    -- the 5% earner (agent derived from teacher.upline_id)
    principal_id     uuid references party(id),    -- the 2% principal
    reward_model     reward_model not null default 'split',
    amount_cents     integer not null default 15000 check (amount_cents >= 0),  -- $150.00
    stripe_customer  text,                          -- opaque Stripe id, NOT a name
    status           sub_status not null default 'pending',
    activated_at     timestamptz,                   -- child added + keyboard enabled
    started_at       timestamptz not null default now()
    -- intentionally NO parent/child name, email, or device columns.
);
create index subscription_school_idx  on subscription (school_id);
create index subscription_teacher_idx on subscription (teacher_id);

-- One paid charge (initial or renewal) = one row
create table subscription_period (
    id               uuid primary key default gen_random_uuid(),
    subscription_id  uuid not null references subscription(id) on delete cascade,
    period_start     date not null,
    period_end       date not null,
    amount_cents     integer not null check (amount_cents >= 0),
    stripe_charge_id text unique,
    paid_at          timestamptz,
    refunded_at      timestamptz,                  -- set on refund -> triggers clawback
    created_at       timestamptz not null default now(),
    constraint period_order check (period_end >= period_start)
);
create index sub_period_sub_idx on subscription_period (subscription_id);

-- ------------------------------------------------------------
-- Payout runs: draft (Giancarlo) -> approved (Torino) -> paid
-- ------------------------------------------------------------
create table payout_run (
    id            uuid primary key default gen_random_uuid(),
    period_label  text not null,                 -- e.g. '2026-11'
    status        payout_status not null default 'draft',
    drafted_by    text,
    approved_by   text,                           -- required before 'paid'
    total_cents   integer not null default 0,
    created_at    timestamptz not null default now(),
    approved_at   timestamptz,
    paid_at       timestamptz
);

-- ------------------------------------------------------------
-- Accrual ledger: one row per (period x role x payee)
-- ------------------------------------------------------------
create table accrual (
    id                     uuid primary key default gen_random_uuid(),
    subscription_period_id uuid not null references subscription_period(id) on delete cascade,
    party_id               uuid not null references party(id),
    role                   party_role not null,
    rate_bps               integer not null,       -- snapshot of the rate at accrual time
    amount_cents           integer not null,       -- floor(period.amount_cents * rate_bps / 10000)
    status                 accrual_status not null default 'held',
    hold_until             date not null,          -- paid_at + 30-day refund window
    payout_run_id          uuid references payout_run(id),
    created_at             timestamptz not null default now(),
    -- a given period pays each role at most once
    constraint accrual_unique_role unique (subscription_period_id, role)
);
create index accrual_party_status_idx on accrual (party_id, status);
create index accrual_run_idx          on accrual (payout_run_id);

-- ------------------------------------------------------------
-- Helper: resolve the agent (teacher's upline) for a subscription
-- ------------------------------------------------------------
create or replace function agent_party_id(p_subscription_id uuid)
returns uuid
language sql
stable
as $$
    select pr.upline_id
    from subscription s
    join party pr on pr.id = s.teacher_id
    where s.id = p_subscription_id
$$;
