-- EMERGENCY ONLY: give one account the root role when no root can sign in
-- any more (forgotten password AND no working reset, root blocked by
-- mistake, last root deleted …). Everything else goes through the app, the
-- web UI or `bsg accounts set-role`, which run as a signed-in root.
--
-- How: Supabase dashboard → the project → SQL Editor → paste this file →
-- replace the e-mail address below → Run. The editor runs as the database
-- owner, so the usual permission checks don't apply here; that's the point.
--
-- It:
--   1. finds the account by e-mail (stops if there is none),
--   2. lifts a block ("Sperren": auth.users.banned_until),
--   3. sets its role to root (logged in the role history with changed_by
--      empty, shown as "System"),
--   4. notes a lifted block in the account admin log ("unblock").
-- The role history already records the role change by itself (trigger).
-- It doesn't touch passwords: if that's the problem, send a reset from the
-- dashboard (Authentication → Users → the account → Send password recovery).

do $$
declare
  -- ↓↓↓ the account that becomes root ↓↓↓
  v_email  text := coalesce(nullif(current_setting('bsg.emergency_email', true), ''), 'name@example.org');
  v_user   uuid;
  v_before public.app_role;
  v_blocked boolean;
begin
  select id into v_user from auth.users where lower(email) = lower(trim(v_email));
  if v_user is null then
    raise exception 'No account with e-mail %; nothing changed.', v_email;
  end if;

  select banned_until is not null and banned_until > now() into v_blocked from auth.users where id = v_user;
  update auth.users set banned_until = null, updated_at = now()
   where id = v_user and banned_until is not null;

  select role into v_before from public.user_roles where user_id = v_user;
  insert into public.user_roles (user_id, role, assigned_by, assigned_at)
  values (v_user, 'root', null, now())
  on conflict (user_id) do update set role = 'root', assigned_by = null, assigned_at = now();

  if v_blocked then
    insert into public.account_admin_log (action, target, target_email, target_name, actor)
    select 'unblock', v_user, coalesce(u.email, ''),
           trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), null
      from auth.users u left join public.profiles p on p.id = u.id
     where u.id = v_user;
  end if;

  raise notice '% (%) is root now (before: %). Sign in again in the app or web UI.',
    v_email, v_user, coalesce(v_before::text, 'no role');
end;
$$;
