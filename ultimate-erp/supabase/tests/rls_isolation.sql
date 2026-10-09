-- =====================================================================
-- Proves the tenant boundary is enforced by the database, not by the UI.
--
-- Two bakeries, two owners. Each must see exactly their own rows, and
-- must not be able to read, change, or plant data in the other's company
-- even when asking for it directly.
-- =====================================================================

\set ON_ERROR_STOP on
begin;

-- A role that is NOT the owner/superuser, since superusers bypass RLS
-- the way Supabase's service key does. This mimics a signed-in user.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'app_user') then
    create role app_user nologin;
  end if;
end;
$$;
grant usage on schema public, auth to app_user;
grant select, insert, update, delete on all tables in schema public to app_user;
grant select on all tables in schema auth to app_user;
grant execute on all functions in schema public, auth to app_user;
grant usage, select on all sequences in schema public to app_user;

insert into auth.users (id, email) values
 ('aaaa0000-0000-0000-0000-00000000000a', 'ada@sweetthings.ng'),
 ('bbbb0000-0000-0000-0000-00000000000b', 'bolu@othercakes.ng');

insert into companies (id, name) values
 ('c0000000-0000-0000-0000-00000000000a', 'Sweet Things Bakery'),
 ('c0000000-0000-0000-0000-00000000000b', 'Other Cakes Ltd');

insert into company_members (company_id, user_id, role) values
 ('c0000000-0000-0000-0000-00000000000a', 'aaaa0000-0000-0000-0000-00000000000a', 'owner'),
 ('c0000000-0000-0000-0000-00000000000b', 'bbbb0000-0000-0000-0000-00000000000b', 'owner');

insert into contacts (company_id, name, is_customer) values
 ('c0000000-0000-0000-0000-00000000000a', 'Ada customer one', true),
 ('c0000000-0000-0000-0000-00000000000a', 'Ada customer two', true),
 ('c0000000-0000-0000-0000-00000000000b', 'Bolu secret customer', true);

-- ---------------------------------------------------------------------
-- Sign in as Ada
-- ---------------------------------------------------------------------
set local role app_user;
set local request.jwt.claim.sub = 'aaaa0000-0000-0000-0000-00000000000a';

do $$
declare n int; leaked int;
begin
  select count(*) into n from contacts;
  if n <> 2 then raise exception 'FAILED: Ada sees % contacts, expected her 2', n; end if;
  raise notice 'ok  Ada sees only her own % contacts', n;

  -- even asking for the other company's row by name returns nothing
  select count(*) into leaked from contacts where name = 'Bolu secret customer';
  if leaked <> 0 then raise exception 'FAILED: Ada can read another company''s contact'; end if;
  raise notice 'ok  Ada cannot read Other Cakes'' customer';

  select count(*) into n from companies;
  if n <> 1 then raise exception 'FAILED: Ada sees % companies, expected 1', n; end if;
  raise notice 'ok  Ada sees only her own company';
end;
$$;

-- she must not be able to write into the other company either
do $$
declare blocked boolean := false;
begin
  begin
    insert into contacts (company_id, name, is_customer)
    values ('c0000000-0000-0000-0000-00000000000b', 'planted by Ada', true);
  exception when others then
    blocked := true;
    raise notice 'ok  Ada blocked from inserting into Other Cakes: %', sqlerrm;
  end;
  if not blocked then
    raise exception 'FAILED: Ada planted a row in another company';
  end if;
end;
$$;

-- nor update rows she cannot see
do $$
declare n int;
begin
  update contacts set name = 'hijacked' where name = 'Bolu secret customer';
  get diagnostics n = ROW_COUNT;
  if n <> 0 then raise exception 'FAILED: Ada updated % foreign rows', n; end if;
  raise notice 'ok  Ada''s update touched 0 foreign rows';
end;
$$;

-- ---------------------------------------------------------------------
-- Sign in as Bolu — the mirror image
-- ---------------------------------------------------------------------
set local request.jwt.claim.sub = 'bbbb0000-0000-0000-0000-00000000000b';

do $$
declare n int;
begin
  select count(*) into n from contacts;
  if n <> 1 then raise exception 'FAILED: Bolu sees % contacts, expected 1', n; end if;
  raise notice 'ok  Bolu sees only his own contact';

  select count(*) into n from contacts where name like 'Ada%';
  if n <> 0 then raise exception 'FAILED: Bolu can see Ada''s customers'; end if;
  raise notice 'ok  Bolu cannot see Ada''s customers';
end;
$$;

-- ---------------------------------------------------------------------
-- Signed out entirely: no rows at all
-- ---------------------------------------------------------------------
set local request.jwt.claim.sub = '';

do $$
declare n int;
begin
  select count(*) into n from contacts;
  if n <> 0 then raise exception 'FAILED: anonymous session saw % contacts', n; end if;
  raise notice 'ok  signed-out session sees nothing';
end;
$$;

reset role;
rollback;
