-- =====================================================================
-- 0001 — Foundation: tenants, people, roles, audit, document numbering
--
-- Every business table carries company_id. One deployment serves many
-- companies; row-level security (0006) keeps them from seeing each other.
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- Companies (tenants)
-- ---------------------------------------------------------------------
create table companies (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  legal_name    text,
  industry      text,                                  -- 'bakery', 'distribution', …
  country       text not null default 'NG',
  currency      char(3) not null default 'NGN',
  timezone      text not null default 'Africa/Lagos',
  fiscal_year_start_month smallint not null default 1
                check (fiscal_year_start_month between 1 and 12),
  logo_url      text,
  settings      jsonb not null default '{}'::jsonb,    -- per-company config
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- Which optional modules a company has switched on. This is what lets one
-- codebase serve a bakery and a distributor without either seeing the
-- other's screens.
create table company_modules (
  company_id  uuid not null references companies(id) on delete cascade,
  module      text not null,          -- 'sales','purchasing','inventory',
                                      -- 'production','payroll','accounting','pos'
  enabled     boolean not null default true,
  config      jsonb not null default '{}'::jsonb,
  primary key (company_id, module)
);

-- ---------------------------------------------------------------------
-- People. Supabase Auth owns auth.users; this mirrors the bits we need.
-- ---------------------------------------------------------------------
create table profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null default '',
  phone       text,
  avatar_url  text,
  created_at  timestamptz not null default now()
);

create type company_role as enum ('owner','admin','manager','sales','clerk','viewer');

create table company_members (
  company_id  uuid not null references companies(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        company_role not null default 'clerk',
  active      boolean not null default true,
  invited_by  uuid references auth.users(id),
  joined_at   timestamptz not null default now(),
  primary key (company_id, user_id)
);
create index on company_members (user_id) where active;

-- ---------------------------------------------------------------------
-- Audit log. Written by triggers (0005) — never by application code, so
-- it cannot be forgotten. Agents and humans are logged identically.
-- ---------------------------------------------------------------------
create table audit_log (
  id          bigserial primary key,
  company_id  uuid references companies(id) on delete cascade,
  actor_id    uuid,                 -- auth.users id, or null for system
  actor_kind  text not null default 'user',   -- 'user' | 'agent' | 'system'
  table_name  text not null,
  row_id      text,
  action      text not null,        -- 'insert' | 'update' | 'delete'
  before      jsonb,
  after       jsonb,
  at          timestamptz not null default now()
);
create index on audit_log (company_id, at desc);
create index on audit_log (table_name, row_id);

-- ---------------------------------------------------------------------
-- Document numbering. Gap-free per company per document type, so two
-- people saving at once cannot land on the same invoice number.
-- ---------------------------------------------------------------------
create table doc_sequences (
  company_id  uuid not null references companies(id) on delete cascade,
  doc_type    text not null,        -- 'invoice','quote','order','po','payment','journal'
  prefix      text not null default '',
  next_value  bigint not null default 1,
  padding     smallint not null default 4,
  reset_yearly boolean not null default true,
  period      text not null default '',   -- the year the counter belongs to
  primary key (company_id, doc_type)
);

create or replace function next_doc_number(p_company uuid, p_doc_type text)
returns text
language plpgsql
as $$
declare
  v_row   doc_sequences%rowtype;
  v_year  text := to_char(now(), 'YYYY');
begin
  -- row lock serialises concurrent callers
  select * into v_row from doc_sequences
   where company_id = p_company and doc_type = p_doc_type
   for update;

  if not found then
    insert into doc_sequences (company_id, doc_type, prefix, next_value, period)
    values (p_company, p_doc_type, upper(left(p_doc_type, 3)) || '-', 1, v_year)
    returning * into v_row;
  end if;

  if v_row.reset_yearly and v_row.period is distinct from v_year then
    v_row.next_value := 1;
    v_row.period := v_year;
  end if;

  update doc_sequences
     set next_value = v_row.next_value + 1,
         period     = v_row.period
   where company_id = p_company and doc_type = p_doc_type;

  return v_row.prefix
       || case when v_row.reset_yearly then v_row.period || '-' else '' end
       || lpad(v_row.next_value::text, v_row.padding, '0');
end;
$$;

-- ---------------------------------------------------------------------
-- updated_at upkeep
-- ---------------------------------------------------------------------
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger companies_touch before update on companies
  for each row execute function touch_updated_at();
