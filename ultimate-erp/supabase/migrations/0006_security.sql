-- =====================================================================
-- 0006 — Row-level security and audit triggers
--
-- This is the file that replaces "the menu item is hidden" with a rule the
-- database itself enforces. A signed-in user can only ever reach rows
-- belonging to a company they are a member of, whether they come through
-- the app, the API, or an AI agent holding their token.
-- =====================================================================

-- SECURITY DEFINER so it can read company_members without tripping that
-- table's own policy (which would recurse).
create or replace function auth_company_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select company_id from company_members
   where user_id = auth.uid() and active;
$$;

create or replace function auth_has_role(p_company uuid, p_roles company_role[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from company_members
     where user_id = auth.uid()
       and company_id = p_company
       and active
       and role = any(p_roles)
  );
$$;

-- ---------------------------------------------------------------------
-- Enable RLS everywhere, then grant per table
-- ---------------------------------------------------------------------
alter table companies              enable row level security;
alter table company_modules        enable row level security;
alter table profiles               enable row level security;
alter table company_members        enable row level security;
alter table audit_log              enable row level security;
alter table doc_sequences          enable row level security;
alter table contacts               enable row level security;
alter table items                  enable row level security;
alter table recipes                enable row level security;
alter table recipe_lines           enable row level security;
alter table locations              enable row level security;
alter table stock_movements        enable row level security;
alter table production_jobs        enable row level security;
alter table production_consumption enable row level security;
alter table orders                 enable row level security;
alter table order_lines            enable row level security;
alter table payments               enable row level security;
alter table attachments            enable row level security;
alter table accounts               enable row level security;
alter table journal_entries        enable row level security;
alter table journal_lines          enable row level security;

-- Companies: members read; only owner/admin may change
create policy companies_read on companies for select
  using (id in (select auth_company_ids()));
create policy companies_write on companies for update
  using (auth_has_role(id, array['owner','admin']::company_role[]));

create policy company_modules_read on company_modules for select
  using (company_id in (select auth_company_ids()));
create policy company_modules_write on company_modules for all
  using (auth_has_role(company_id, array['owner','admin']::company_role[]))
  with check (auth_has_role(company_id, array['owner','admin']::company_role[]));

-- Profiles: you see your own, and those of people you share a company with
create policy profiles_self on profiles for all
  using (id = auth.uid()) with check (id = auth.uid());
create policy profiles_colleagues on profiles for select
  using (exists (
    select 1 from company_members m
     where m.user_id = profiles.id
       and m.company_id in (select auth_company_ids())
  ));

create policy members_read on company_members for select
  using (company_id in (select auth_company_ids()));
create policy members_manage on company_members for all
  using (auth_has_role(company_id, array['owner','admin']::company_role[]))
  with check (auth_has_role(company_id, array['owner','admin']::company_role[]));

-- Audit log is readable by admins and append-only: nobody may edit history
create policy audit_read on audit_log for select
  using (auth_has_role(company_id, array['owner','admin']::company_role[]));

create policy doc_sequences_use on doc_sequences for all
  using (company_id in (select auth_company_ids()))
  with check (company_id in (select auth_company_ids()));

-- ---------------------------------------------------------------------
-- The ordinary business tables: any active member of the company
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'contacts','items','recipes','locations','stock_movements',
    'production_jobs','orders','payments','attachments',
    'accounts','journal_entries'
  ]
  loop
    execute format(
      'create policy %1$s_tenant on %1$s for all
         using (company_id in (select auth_company_ids()))
         with check (company_id in (select auth_company_ids()))', t);
  end loop;
end;
$$;

-- Child tables reach their company through the parent
create policy order_lines_tenant on order_lines for all
  using (exists (select 1 from orders o
                  where o.id = order_lines.order_id
                    and o.company_id in (select auth_company_ids())))
  with check (exists (select 1 from orders o
                  where o.id = order_lines.order_id
                    and o.company_id in (select auth_company_ids())));

create policy recipe_lines_tenant on recipe_lines for all
  using (exists (select 1 from recipes r
                  where r.id = recipe_lines.recipe_id
                    and r.company_id in (select auth_company_ids())))
  with check (exists (select 1 from recipes r
                  where r.id = recipe_lines.recipe_id
                    and r.company_id in (select auth_company_ids())));

create policy production_consumption_tenant on production_consumption for all
  using (exists (select 1 from production_jobs j
                  where j.id = production_consumption.job_id
                    and j.company_id in (select auth_company_ids())))
  with check (exists (select 1 from production_jobs j
                  where j.id = production_consumption.job_id
                    and j.company_id in (select auth_company_ids())));

create policy journal_lines_tenant on journal_lines for all
  using (exists (select 1 from journal_entries e
                  where e.id = journal_lines.entry_id
                    and e.company_id in (select auth_company_ids())))
  with check (exists (select 1 from journal_entries e
                  where e.id = journal_lines.entry_id
                    and e.company_id in (select auth_company_ids())));

-- ---------------------------------------------------------------------
-- Audit triggers
--
-- Attached to the tables where "who changed this, and what did it say
-- before?" is a question someone will eventually need answered.
-- ---------------------------------------------------------------------
create or replace function write_audit()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_row     jsonb;
begin
  v_row := to_jsonb(coalesce(new, old));
  v_company := nullif(v_row->>'company_id', '')::uuid;

  -- Child rows (order_lines) carry no company_id of their own; find it via
  -- the parent so the entry is still visible to that company's admins.
  if v_company is null and (v_row ? 'order_id') then
    select company_id into v_company from orders
     where id = nullif(v_row->>'order_id', '')::uuid;
  end if;

  insert into audit_log (company_id, actor_id, actor_kind, table_name, row_id,
                         action, before, after)
  values (
    v_company,
    auth.uid(),
    coalesce(current_setting('app.actor_kind', true), 'user'),
    tg_table_name,
    v_row->>'id',
    lower(tg_op),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end
  );
  return null;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'contacts','items','orders','order_lines','payments',
    'stock_movements','production_jobs','accounts','journal_entries'
  ]
  loop
    execute format(
      'create trigger %1$s_audit after insert or update or delete on %1$s
         for each row execute function write_audit()', t);
  end loop;
end;
$$;
