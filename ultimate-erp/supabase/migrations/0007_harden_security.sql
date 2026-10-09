-- =====================================================================
-- 0007 — Close two holes the Supabase linter found in 0006
--
-- 1. VIEWS BYPASSED RLS.  A Postgres view runs as its owner unless told
--    otherwise, so stock_on_hand, order_totals, order_balances and
--    trial_balance returned every company's rows to any signed-in user.
--    tests/rls_isolation.sql passed before this because it only queried
--    tables directly; it now covers the views, and fails without the fix
--    (verified: Ada saw 2 companies' stock instead of 1).
--
-- 2. HELPER FUNCTIONS WERE CALLABLE OVER THE PUBLIC API.  They must be
--    SECURITY DEFINER (they read company_members, whose own policy would
--    otherwise recurse), but living in `public` meant anyone could reach
--    them at /rest/v1/rpc/. Copies now live in an `app` schema that
--    PostgREST does not expose, policies point there, and EXECUTE on the
--    public originals is revoked.
--
-- NOTE ON STYLE: policies are repointed with ALTER POLICY rather than
-- dropped and recreated, and the public functions are left in place with
-- EXECUTE revoked rather than dropped. On the hosted instance every DROP
-- statement stalled past the 60s client timeout while ALTER/CREATE/REVOKE
-- returned immediately, so this migration avoids DROP entirely. The end
-- state is equivalent: nothing reachable, nothing callable.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Views honour the caller's policies
-- ---------------------------------------------------------------------
alter view stock_on_hand   set (security_invoker = on);
alter view order_totals    set (security_invoker = on);
alter view order_balances  set (security_invoker = on);
alter view trial_balance   set (security_invoker = on);

-- ---------------------------------------------------------------------
-- 2. The helpers, out of the API-exposed schema
-- ---------------------------------------------------------------------
create schema if not exists app;

create or replace function app.auth_company_ids()
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  select company_id from company_members
   where user_id = auth.uid() and active;
$$;

create or replace function app.auth_has_role(p_company uuid, p_roles company_role[])
returns boolean
language sql stable security definer
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

-- Policies are evaluated as the querying role, so that role needs EXECUTE
-- here — but PostgREST serves `public`, not `app`, so this is not an
-- endpoint anyone can call.
grant usage on schema app to authenticated, anon;
grant execute on function app.auth_company_ids() to authenticated, anon;
grant execute on function app.auth_has_role(uuid, company_role[]) to authenticated, anon;

-- ---------------------------------------------------------------------
-- 3. Repoint every policy from public.* to app.*
--
-- Rewrites each stored expression in place. Only call sites are matched
-- (on the trailing parenthesis) so that the column alias Postgres renders
-- as `... AS auth_company_ids` is left alone — replacing that too
-- produces `AS app.auth_company_ids`, which is a syntax error.
-- ---------------------------------------------------------------------
do $$
declare
  r record; v_qual text; v_check text; v_sql text;
begin
  for r in
    select schemaname, tablename, policyname, qual::text as q, with_check::text as c
    from pg_policies
    where schemaname = 'public'
      and (qual::text       like '%auth_company_ids(%' or qual::text       like '%auth_has_role(%'
        or with_check::text like '%auth_company_ids(%' or with_check::text like '%auth_has_role(%')
  loop
    v_qual := r.q;
    if v_qual is not null then
      v_qual := replace(v_qual, 'app.auth_company_ids(', 'auth_company_ids(');
      v_qual := replace(v_qual, 'app.auth_has_role(',    'auth_has_role(');
      v_qual := replace(v_qual, 'auth_company_ids(', 'app.auth_company_ids(');
      v_qual := replace(v_qual, 'auth_has_role(',    'app.auth_has_role(');
    end if;

    v_check := r.c;
    if v_check is not null then
      v_check := replace(v_check, 'app.auth_company_ids(', 'auth_company_ids(');
      v_check := replace(v_check, 'app.auth_has_role(',    'auth_has_role(');
      v_check := replace(v_check, 'auth_company_ids(', 'app.auth_company_ids(');
      v_check := replace(v_check, 'auth_has_role(',    'app.auth_has_role(');
    end if;

    v_sql := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    if v_qual  is not null then v_sql := v_sql || format(' using (%s)', v_qual); end if;
    if v_check is not null then v_sql := v_sql || format(' with check (%s)', v_check); end if;
    execute v_sql;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Shut the public originals. The audit triggers created in 0006 still
--    call public.write_audit(); a trigger runs regardless of the calling
--    user's EXECUTE privilege, so revoking here stops RPC access without
--    stopping the audit trail. (Verified on the live database: an insert
--    still wrote its audit_log row after this revoke.)
-- ---------------------------------------------------------------------
revoke execute on function public.write_audit()       from public, anon, authenticated;
revoke execute on function public.auth_company_ids()  from public, anon, authenticated;
revoke execute on function public.auth_has_role(uuid, company_role[]) from public, anon, authenticated;
