-- Hardening for root account administration (review of 20261014000002):
--  * audit log of block / unblock / delete (with a snapshot of the target),
--  * root accounts can't be blocked or deleted directly — demote first
--    (set_user_role, which is logged) — and the last-root guard only counts
--    roots that can still sign in,
--  * a blocked account's calendar link is replaced,
--  * the remaining "own account" paths refuse a blocked caller during the
--    ≤ 15 min its access token stays valid,
--  * unblocked_user_ids() lets notify-schedule skip blocked accounts.

-- ------------------------------------------------------ account_admin_log ---
-- Append-only, written only by the RPCs below. No FK to auth.users: rows
-- outlive deleted accounts, so email and name are stored as they were.
create table public.account_admin_log (
  id           bigint generated always as identity primary key,
  action       text not null check (action in ('block', 'unblock', 'delete')),
  target       uuid not null,
  target_email text not null default '',
  target_name  text not null default '',
  actor        uuid,
  at           timestamptz not null default now()
);
alter table public.account_admin_log enable row level security;
revoke all on public.account_admin_log from anon, authenticated;
grant select on public.account_admin_log to authenticated;
create policy "account_admin_log: read with rolelog.read"
  on public.account_admin_log for select to authenticated
  using ((select public.authorize('rolelog.read')));

create function public.log_account_admin(p_action text, p_target uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.account_admin_log (action, target, target_email, target_name, actor)
  select p_action, p_target, coalesce(p.email, ''),
         trim(coalesce(p.first_name, '') || ' ' || coalesce(p.last_name, '')), auth.uid()
    from (select p_target as id) t
    left join public.profiles p on p.id = t.id;
$$;

-- Shared checks for set_account_blocked / delete_account.
create function public.check_account_admin_target(target uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('roles.assign') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if target = auth.uid() then
    raise exception 'not allowed on your own account' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users where id = target) then
    raise exception 'unknown user' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.user_roles where user_id = target and role = 'root') then
    raise exception 'demote the root account first' using errcode = '42501', hint = 'target_root';
  end if;
end;
$$;

-- ------------------------------------------------- set_account_blocked ---
create or replace function public.set_account_blocked(target uuid, blocked boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_account_admin_target(target);

  update auth.users
     set banned_until = case when blocked then now() + interval '100 years' end,
         updated_at = now()
   where id = target;
  if blocked then
    -- Refresh tokens hang off sessions (cascade); older ones only carry user_id.
    delete from auth.sessions where user_id = target;
    delete from auth.refresh_tokens where user_id = target::text;
    -- No pushes to a locked account's phones.
    delete from public.device_tokens where user_id = target;
    -- A subscribed calendar must stop working; unblocking doesn't bring
    -- the old link back (the person copies the new one from the app).
    update public.profiles
       set calendar_token = encode(extensions.gen_random_bytes(24), 'hex'), updated_at = now()
     where id = target;
  end if;
  perform public.log_account_admin(case when blocked then 'block' else 'unblock' end, target);
end;
$$;

-- ---------------------------------------------------- delete_account ---
create or replace function public.delete_account(target uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_account_admin_target(target);
  -- Logged first: the profile (email, name) cascades away with the user.
  perform public.log_account_admin('delete', target);
  delete from auth.users where id = target;
end;
$$;

-- --------------------------------------------------- last-root guard ---
-- Only roots that can still sign in count; a blocked root can't recover
-- the club's administration.
create or replace function public.guard_last_root()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  remaining int;
begin
  if old.role = 'root' and (tg_op = 'DELETE' or new.role <> 'root') then
    perform 1 from public.user_roles where role = 'root' for update;
    select count(*) into remaining
      from public.user_roles r
      join auth.users u on u.id = r.user_id
     where r.role = 'root' and r.user_id <> old.user_id
       and (u.banned_until is null or u.banned_until <= now());
    if remaining = 0 then
      raise exception 'cannot remove the last root account'
        using errcode = 'P0001', hint = 'last_root';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;

-- --------------------------------------- own-account paths see blocks ---
create or replace function public.register_device_token(p_token text, p_apns_env text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or public.is_blocked() then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if p_apns_env not in ('sandbox', 'production') then
    raise exception 'invalid apns_env %', p_apns_env using errcode = '22023';
  end if;
  insert into public.device_tokens (token, user_id, apns_env)
  values (p_token, auth.uid(), p_apns_env)
  on conflict (token) do update
    set user_id = excluded.user_id, apns_env = excluded.apns_env, updated_at = now();
end;
$$;

create or replace function public.redeem_activation_code(code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized text := upper(regexp_replace(code, '[^A-Za-z0-9]', '', 'g'));
  rec public.activation_codes;
begin
  if auth.uid() is null or public.is_blocked() then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  select * into rec
    from public.activation_codes
   where code_hash = encode(extensions.digest(normalized, 'sha256'), 'hex')
     and user_id = auth.uid()
     and used_at is null
     and expires_at > now()
   for update;
  if not found then
    return false;
  end if;

  update public.activation_codes set used_at = now() where id = rec.id;
  if rec.member_id is not null then
    insert into public.account_approvals (user_id, member_id, approved_by)
    values (rec.user_id, rec.member_id, rec.created_by)
    on conflict (user_id) do update set member_id = excluded.member_id;
    insert into public.user_roles (user_id, role, assigned_by)
    values (rec.user_id, 'member', rec.created_by)
    on conflict (user_id) do nothing;
  end if;
  return true;
end;
$$;

-- Returns null (no new link) for a blocked caller.
create or replace function public.rotate_calendar_token()
returns text
language sql
security definer
set search_path = ''
as $$
  update public.profiles
     set calendar_token = encode(extensions.gen_random_bytes(24), 'hex'),
         updated_at = now()
   where id = (select auth.uid()) and not public.is_blocked()
  returning calendar_token;
$$;

drop policy "profiles: update own name" on public.profiles;
create policy "profiles: update own name"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()) and not (select public.is_blocked()))
  with check (id = (select auth.uid()));

-- ------------------------------------------------- unblocked_user_ids ---
-- For notify-schedule (service role): the given accounts minus blocked ones.
create function public.unblocked_user_ids(ids uuid[])
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.id from auth.users u
   where u.id = any (ids) and (u.banned_until is null or u.banned_until <= now());
$$;

-- ---------------------------------------------------------------- grants ---
revoke execute on function
  public.log_account_admin(text, uuid),
  public.check_account_admin_target(uuid),
  public.unblocked_user_ids(uuid[])
  from anon, authenticated, public;
grant execute on function public.unblocked_user_ids(uuid[]) to service_role;
