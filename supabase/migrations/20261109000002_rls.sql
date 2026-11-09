-- CyberSafely Sales — access control (RLS) + payout approval guard
-- Enforces the hard rules at the DB layer, not just in app code:
--   * only staff touch the money tables
--   * an affiliate who logs in sees ONLY their own accrual rows (counts), never a subscription
--   * a payout run cannot be marked paid without an approver (Torino)
-- Depends on Supabase 'auth' schema (auth.users, auth.uid()).

-- ------------------------------------------------------------
-- Staff = internal operators. role: admin drafts, approver signs off.
-- ------------------------------------------------------------
create table staff (
    auth_user_id  uuid primary key references auth.users(id) on delete cascade,
    display_name  text not null,
    role          text not null check (role in ('admin', 'approver')),
    created_at    timestamptz not null default now()
);

-- Link an affiliate login to their party row (optional self-service portal)
alter table party add column auth_user_id uuid unique references auth.users(id);

-- ------------------------------------------------------------
-- Helper functions (security definer so they can read staff/party under RLS)
-- ------------------------------------------------------------
create or replace function is_staff()
returns boolean language sql stable security definer set search_path = public as $$
    select exists (select 1 from staff where auth_user_id = auth.uid())
$$;

create or replace function current_party_id()
returns uuid language sql stable security definer set search_path = public as $$
    select id from party where auth_user_id = auth.uid()
$$;

-- ------------------------------------------------------------
-- Enable RLS everywhere (RLS on + no matching policy = deny)
-- ------------------------------------------------------------
alter table school              enable row level security;
alter table party               enable row level security;
alter table commission_rate     enable row level security;
alter table subscription        enable row level security;
alter table subscription_period enable row level security;
alter table payout_run          enable row level security;
alter table accrual             enable row level security;
alter table staff               enable row level security;

-- Staff: full access to every operational table
create policy staff_all_school  on school              for all using (is_staff()) with check (is_staff());
create policy staff_all_party   on party               for all using (is_staff()) with check (is_staff());
create policy staff_all_rate    on commission_rate     for all using (is_staff()) with check (is_staff());
create policy staff_all_sub     on subscription        for all using (is_staff()) with check (is_staff());
create policy staff_all_period  on subscription_period for all using (is_staff()) with check (is_staff());
create policy staff_all_run     on payout_run          for all using (is_staff()) with check (is_staff());
create policy staff_all_accrual on accrual             for all using (is_staff()) with check (is_staff());
create policy staff_read_staff  on staff               for select using (is_staff());

-- Affiliate self-service (read-only): see only your own party row and your own accruals.
-- Deliberately NO policy granting affiliates access to subscription / subscription_period:
-- they never see a family, only their own earned amounts.
create policy affiliate_own_party   on party   for select using (id = current_party_id());
create policy affiliate_own_accrual on accrual for select using (party_id = current_party_id());

-- ------------------------------------------------------------
-- Payout approval guard: no 'paid' without an approver; no skipping 'approved'
-- ------------------------------------------------------------
create or replace function enforce_payout_approval()
returns trigger language plpgsql as $$
begin
    if new.status = 'approved' and new.approved_by is null then
        raise exception 'payout_run cannot be approved without approved_by';
    end if;
    if new.status = 'paid' then
        if new.approved_by is null then
            raise exception 'payout_run cannot be paid without an approver';
        end if;
        if tg_op = 'UPDATE' and old.status <> 'approved' then
            raise exception 'payout_run must be approved before it can be paid (was %)', old.status;
        end if;
    end if;
    return new;
end;
$$;

create trigger trg_payout_approval
    before insert or update on payout_run
    for each row execute function enforce_payout_approval();
