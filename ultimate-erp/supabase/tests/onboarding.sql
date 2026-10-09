-- =====================================================================
-- The first five minutes of a new customer's life:
--   sign up -> create the business -> get starting data -> see it.
--
-- Run entirely as a signed-in, non-superuser role, so row-level security
-- is in force exactly as it will be for a real person in a browser.
-- =====================================================================

\set ON_ERROR_STOP on
begin;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'app_user') then
    create role app_user nologin;
  end if;
end;
$$;
grant usage on schema public, auth, app to app_user;
grant select, insert, update, delete on all tables in schema public to app_user;
grant select on all tables in schema auth to app_user;
grant execute on all functions in schema public, auth to app_user;
grant execute on function app.auth_company_ids() to app_user;
grant execute on function app.auth_has_role(uuid, company_role[]) to app_user;
grant execute on function app.create_company(text, text, char, text) to app_user;
grant execute on function app.seed_demo_data(uuid) to app_user;
grant usage, select on all sequences in schema public to app_user;

-- Supabase Auth would do this insert; the trigger reacts to it.
insert into auth.users (id, email)
values ('11110000-0000-0000-0000-00000000aaaa', 'ada@sweetthings.ng');

do $$
begin
  if not exists (select 1 from profiles where id = '11110000-0000-0000-0000-00000000aaaa') then
    raise exception 'FAILED: signing up did not create a profile';
  end if;
  raise notice 'ok  profile created automatically on sign-up';
end;
$$;

-- ---------------------------------------------------------------------
-- Now act as that person
-- ---------------------------------------------------------------------
set local role app_user;
set local request.jwt.claim.sub = '11110000-0000-0000-0000-00000000aaaa';

-- Before anything exists, she must not be able to invent a company by hand
do $$
declare blocked boolean := false;
begin
  begin
    insert into companies (name) values ('Sneaky Ltd');
  exception when others then
    blocked := true;
    raise notice 'ok  direct company insert is refused: %', sqlerrm;
  end;
  if not blocked then raise exception 'FAILED: a stranger created a company directly'; end if;
end;
$$;

-- The supported route
do $$
declare v_company uuid; n int;
begin
  v_company := app.create_company('Sweet Things Bakery', 'bakery', 'NGN', 'NG');
  raise notice 'ok  business created via app.create_company';

  select count(*) into n from company_members
   where company_id = v_company and user_id = auth.uid() and role = 'owner';
  if n <> 1 then raise exception 'FAILED: caller is not the owner'; end if;
  raise notice 'ok  caller is the owner';

  select count(*) into n from accounts where company_id = v_company;
  if n < 15 then raise exception 'FAILED: chart of accounts has only % rows', n; end if;
  raise notice 'ok  chart of accounts seeded (% accounts)', n;

  select count(*) into n from locations where company_id = v_company and is_default;
  if n <> 1 then raise exception 'FAILED: no default location'; end if;

  select count(*) into n from company_modules where company_id = v_company and enabled;
  raise notice 'ok  % modules switched on', n;

  -- starting data
  perform app.seed_demo_data(v_company);
  raise notice 'ok  demo data seeded';

  -- running it twice must not double anything
  perform app.seed_demo_data(v_company);
  select count(*) into n from items where company_id = v_company;
  if n <> 11 then raise exception 'FAILED: seeding twice produced % items, expected 11', n; end if;
  raise notice 'ok  seeding is idempotent (% items)', n;
end;
$$;

-- ---------------------------------------------------------------------
-- What she now sees, read back through the same policies
-- ---------------------------------------------------------------------
do $$
declare
  n int; v numeric; v_company uuid;
begin
  select company_id into v_company from company_members where user_id = auth.uid();

  select count(*) into n from contacts;
  if n <> 5 then raise exception 'FAILED: % customers, expected 5', n; end if;
  raise notice 'ok  % customers visible', n;

  select count(*) into n from orders;
  if n <> 4 then raise exception 'FAILED: % orders, expected 4', n; end if;
  raise notice 'ok  % orders visible (3 orders + 1 quote)', n;

  -- stock came through the movement ledger, not a typed-in number
  select qty_on_hand into v from stock_on_hand s
    join items i on i.id = s.item_id where i.name = 'Flour';
  if v <> 50 then raise exception 'FAILED: flour on hand is %, expected 50', v; end if;
  raise notice 'ok  flour on hand = % (from movements)', v;

  -- order totals are derived, including tax and delivery
  select total into v from order_totals t join orders o on o.id = t.order_id
   where o.status = 'in_production';
  -- 2 x 18,000 = 36,000 + 7.5% = 38,700 + 3,000 delivery = 41,700
  if v <> 41700 then raise exception 'FAILED: order total is %, expected 41700', v; end if;
  raise notice 'ok  order total computed = % (2 x 18,000 +7.5%% +3,000 delivery)', v;

  select balance into v from order_balances b join orders o on o.id = b.order_id
   where o.status = 'in_production';
  if v <> 21700 then raise exception 'FAILED: balance is %, expected 21700 after 20,000 deposit', v; end if;
  raise notice 'ok  balance after deposit = %', v;

  -- the recipe gives a real cost per cake
  select count(*) into n from recipe_lines rl
    join recipes r on r.id = rl.recipe_id where r.company_id = v_company;
  if n <> 7 then raise exception 'FAILED: recipe has % lines', n; end if;
  raise notice 'ok  recipe has % ingredients', n;

  -- the ledger balances
  select sum(amount) into v from journal_lines l
    join journal_entries e on e.id = l.entry_id where e.company_id = v_company;
  if v <> 0 then raise exception 'FAILED: ledger is off by %', v; end if;
  select count(*) into n from journal_entries where company_id = v_company and posted;
  raise notice 'ok  % posted journal entries, all balancing to zero', n;

  select count(*) into n from production_jobs;
  raise notice 'ok  % production job(s) on the calendar', n;
end;
$$;

-- ---------------------------------------------------------------------
-- A second business must not see any of it
-- ---------------------------------------------------------------------
reset role;
insert into auth.users (id, email) values ('22220000-0000-0000-0000-00000000bbbb','bolu@other.ng');
set local role app_user;
set local request.jwt.claim.sub = '22220000-0000-0000-0000-00000000bbbb';

do $$
declare n int; v_company uuid;
begin
  select count(*) into n from items;
  if n <> 0 then raise exception 'FAILED: a new user sees % items belonging to someone else', n; end if;
  raise notice 'ok  a brand-new user sees nothing';

  v_company := app.create_company('Other Cakes Ltd', 'bakery');
  select count(*) into n from items;              -- still empty, not seeded
  if n <> 0 then raise exception 'FAILED: sees % items after creating own company', n; end if;

  select count(*) into n from orders;
  if n <> 0 then raise exception 'FAILED: sees % foreign orders', n; end if;
  raise notice 'ok  second business is completely isolated';
end;
$$;

-- and may not seed a company it does not own
do $$
declare blocked boolean := false; v_other uuid;
begin
  select company_id into v_other from company_members
   where user_id = '11110000-0000-0000-0000-00000000aaaa';
  begin
    perform app.seed_demo_data(v_other);
  exception when others then
    blocked := true;
    raise notice 'ok  cannot seed another company: %', sqlerrm;
  end;
  if not blocked then raise exception 'FAILED: seeded a company it does not own'; end if;
end;
$$;

reset role;
rollback;
