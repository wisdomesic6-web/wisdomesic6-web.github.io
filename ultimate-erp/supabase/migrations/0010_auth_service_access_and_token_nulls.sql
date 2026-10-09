-- =====================================================================
-- 0010 — Two things that stopped anyone actually signing in
--
-- Symptom in the browser: "Database error querying schema" on sign-in.
-- Supabase's auth logs showed the truth:
--   error finding user: Scan error on column "confirmation_token":
--   converting NULL to string is unsupported   (HTTP 500 on /token)
--
-- (1) GoTrue, the auth service, reads a set of token columns on
--     auth.users into plain Go strings. A NULL is not a string, so the
--     read fails for the whole request. GoTrue's own sign-up writes ''
--     into these; the account I created by hand over SQL left them NULL,
--     so every sign-in attempt for that user 500'd. Backfilled to ''.
--     (`phone` stays NULL on purpose — it is genuinely nullable and
--     carries a unique index.)
--
-- (2) Separately, the auth service could not reach its own trigger. The
--     on_auth_user_created trigger on auth.users calls
--     app.handle_new_user(), but schema `app` had only been granted to
--     `authenticated` and `anon`. The role that inserts into auth.users
--     is supabase_auth_admin, which had no USAGE on `app`, so a real
--     API sign-up would fail with "Database error saving new user".
--
-- Both went unnoticed because every account in testing was made over
-- SQL as the database owner, which bypasses both the GoTrue read path
-- and the schema-usage check.
-- =====================================================================

-- (2) the auth service may use its own trigger
grant usage on schema app to supabase_auth_admin;
grant execute on function app.handle_new_user() to supabase_auth_admin;

-- (1) no NULL in any GoTrue string column
update auth.users
   set confirmation_token         = coalesce(confirmation_token, ''),
       recovery_token             = coalesce(recovery_token, ''),
       email_change               = coalesce(email_change, ''),
       email_change_token_new     = coalesce(email_change_token_new, ''),
       email_change_token_current = coalesce(email_change_token_current, ''),
       phone_change               = coalesce(phone_change, ''),
       phone_change_token         = coalesce(phone_change_token, ''),
       reauthentication_token     = coalesce(reauthentication_token, '')
 where confirmation_token is null
    or recovery_token is null
    or email_change is null
    or email_change_token_new is null
    or email_change_token_current is null
    or phone_change is null
    or phone_change_token is null
    or reauthentication_token is null;
