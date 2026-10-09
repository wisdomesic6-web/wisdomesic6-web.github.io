-- =====================================================================
-- 0009 — Give the browser a door to the three functions it must call
--
-- 0007 moved the helpers into an `app` schema so nobody could reach
-- auth_company_ids() and auth_has_role() over the public API. That was
-- right. But create_company, seed_demo_data and post_expense went into
-- `app` too, and those three ARE meant to be called from the browser.
-- PostgREST only serves `public`, so every one of them answered 404 and
-- a brand-new user could sign up and then go no further. The symptom
-- looks like a broken login, because the business-setup step that comes
-- straight after signing in is the thing that fails.
--
-- The fix is a thin wrapper in `public` for each. The wrappers are
-- SECURITY INVOKER, so they carry the caller's identity inward, and the
-- `app` functions they call are the ones that decide what is allowed:
-- create_company requires a signed-in user, post_expense and
-- seed_demo_data check membership. The helpers stay unreachable.
--
-- Verified against the live database as a signed-in user: create_company
-- returned a new company with 17 accounts and an owner row,
-- seed_demo_data produced 11 items, post_expense moved the entry count
-- 4 -> 5, and the same call as an anonymous visitor was refused.
-- =====================================================================

create or replace function public.create_company(
  p_name text,
  p_industry text default null,
  p_currency char(3) default 'NGN',
  p_country text default 'NG'
) returns uuid
language sql
as $$ select app.create_company(p_name, p_industry, p_currency, p_country); $$;

create or replace function public.seed_demo_data(p_company uuid)
returns void
language sql
as $$ select app.seed_demo_data(p_company); $$;

create or replace function public.post_expense(
  p_company uuid,
  p_date date,
  p_memo text,
  p_account_code text,
  p_amount numeric
) returns void
language sql
as $$ select app.post_expense(p_company, p_date, p_memo, p_account_code, p_amount); $$;

-- Signed-in users only. An anonymous visitor has no business creating a
-- company or posting into anyone's books.
revoke execute on function public.create_company(text, text, char, text) from public, anon;
revoke execute on function public.seed_demo_data(uuid)                   from public, anon;
revoke execute on function public.post_expense(uuid, date, text, text, numeric) from public, anon;

grant execute on function public.create_company(text, text, char, text) to authenticated;
grant execute on function public.seed_demo_data(uuid)                   to authenticated;
grant execute on function public.post_expense(uuid, date, text, text, numeric) to authenticated;
