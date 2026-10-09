-- =====================================================================
-- 0005 — Double-entry accounting
--
-- The workbook kept a single-entry list: a transaction had an account and
-- an amount, and the P&L summed them by type. That can produce a profit
-- figure but never a balance sheet, and nothing forces it to be coherent.
--
-- Here every entry has lines that must sum to zero — debits equal credits,
-- enforced by the database rather than by discipline. This is the line
-- between "a stock tracker" and something an accountant will sign.
-- =====================================================================

create type account_type as enum ('asset','liability','equity','income','expense');

create table accounts (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  code          text not null,              -- '1000', '4000'
  name          text not null,
  type          account_type not null,
  parent_id     uuid references accounts(id) on delete set null,
  -- marks the accounts the system posts to automatically
  system_tag    text,                       -- 'ar','ap','cash','bank','sales',
                                            -- 'cogs','inventory','tax','payroll',
                                            -- 'deposits','retained_earnings'
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);
create unique index on accounts (company_id, code);
create index on accounts (company_id, type) where active;
create unique index on accounts (company_id, system_tag) where system_tag is not null;

-- ---------------------------------------------------------------------
-- Journal entries
-- ---------------------------------------------------------------------
create table journal_entries (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  entry_no      text,
  entry_date    date not null default current_date,
  memo          text,
  -- what produced it, so every figure traces back to its document
  source_type   text,                       -- 'order','payment','production_job',
                                            -- 'payroll_run','manual'
  source_id     uuid,
  posted        boolean not null default false,
  posted_at     timestamptz,
  created_by    uuid references auth.users(id),
  created_at    timestamptz not null default now()
);
create index on journal_entries (company_id, entry_date desc);
create index on journal_entries (source_type, source_id);

create table journal_lines (
  id            uuid primary key default gen_random_uuid(),
  entry_id      uuid not null references journal_entries(id) on delete cascade,
  account_id    uuid not null references accounts(id) on delete restrict,
  -- one signed amount rather than separate debit/credit columns: positive
  -- is a debit, negative a credit. Makes "must balance" a plain sum = 0.
  amount        numeric(14,2) not null check (amount <> 0),
  contact_id    uuid references contacts(id) on delete set null,
  memo          text,
  line_no       smallint not null default 1
);
create index on journal_lines (entry_id);
create index on journal_lines (account_id);

-- An entry may not be posted unless its lines balance.
create or replace function assert_entry_balances()
returns trigger language plpgsql as $$
declare
  v_entry uuid := coalesce(new.entry_id, old.entry_id);
  v_sum   numeric(14,2);
  v_posted boolean;
begin
  select posted into v_posted from journal_entries where id = v_entry;
  if v_posted then
    select coalesce(sum(amount), 0) into v_sum from journal_lines where entry_id = v_entry;
    if v_sum <> 0 then
      raise exception 'Journal entry % does not balance (off by %)', v_entry, v_sum;
    end if;
  end if;
  return null;
end;
$$;

create constraint trigger journal_lines_balance
  after insert or update or delete on journal_lines
  deferrable initially deferred
  for each row execute function assert_entry_balances();

create or replace function assert_entry_balances_on_post()
returns trigger language plpgsql as $$
declare v_sum numeric(14,2);
begin
  if new.posted and not coalesce(old.posted, false) then
    select coalesce(sum(amount), 0) into v_sum from journal_lines where entry_id = new.id;
    if v_sum <> 0 then
      raise exception 'Cannot post entry %: debits and credits differ by %', new.id, v_sum;
    end if;
    new.posted_at := now();
  end if;
  return new;
end;
$$;

create trigger journal_entries_post_check
  before update on journal_entries
  for each row execute function assert_entry_balances_on_post();

-- ---------------------------------------------------------------------
-- Reporting views
-- ---------------------------------------------------------------------
create view trial_balance as
select
  a.company_id,
  a.id   as account_id,
  a.code,
  a.name,
  a.type,
  sum(case when l.amount > 0 then l.amount else 0 end) as debit,
  sum(case when l.amount < 0 then -l.amount else 0 end) as credit,
  sum(l.amount)                                        as balance
from accounts a
join journal_lines l   on l.account_id = a.id
join journal_entries e on e.id = l.entry_id and e.posted
group by a.company_id, a.id, a.code, a.name, a.type;

-- ---------------------------------------------------------------------
-- A starting chart of accounts for a new company
-- ---------------------------------------------------------------------
create or replace function seed_chart_of_accounts(p_company uuid)
returns void language plpgsql as $$
begin
  insert into accounts (company_id, code, name, type, system_tag) values
    (p_company, '1000', 'Cash',                 'asset',     'cash'),
    (p_company, '1010', 'Bank',                 'asset',     'bank'),
    (p_company, '1100', 'Accounts receivable',  'asset',     'ar'),
    (p_company, '1200', 'Inventory',            'asset',     'inventory'),
    (p_company, '2000', 'Accounts payable',     'liability', 'ap'),
    (p_company, '2100', 'Customer deposits',    'liability', 'deposits'),
    (p_company, '2200', 'Tax payable',          'liability', 'tax'),
    (p_company, '3000', 'Owner equity',         'equity',    null),
    (p_company, '3900', 'Retained earnings',    'equity',    'retained_earnings'),
    (p_company, '4000', 'Sales',                'income',    'sales'),
    (p_company, '5000', 'Cost of goods sold',   'expense',   'cogs'),
    (p_company, '6000', 'Wages and salaries',   'expense',   'payroll'),
    (p_company, '6100', 'Rent',                 'expense',   null),
    (p_company, '6200', 'Utilities',            'expense',   null),
    (p_company, '6300', 'Transport and delivery','expense',  null),
    (p_company, '6400', 'Packaging',            'expense',   null),
    (p_company, '6900', 'Other expenses',       'expense',   null)
  on conflict do nothing;
end;
$$;
