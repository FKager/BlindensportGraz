-- Root account administration: block (lock) / unblock and delete another
-- account. Gated by roles.assign (root only), like role changes. Nobody can
-- target their own account here — self-deletion is "Konto löschen"
-- (delete-account Edge Function), and the last-root guard still applies.
--
-- Blocking sets auth.users.banned_until (GoTrue then refuses sign-in and
-- token refresh with `user_banned`) and ends every session. The access
-- token already issued stays valid until it expires (jwt_expiry 900 s), so
-- has_permission / authorize / is_approved also check the block — writes
-- and club data reads stop at once.

-- GoTrue reads banned_until into a Go time; 'infinity' would not scan.
-- 100 years, same as GoTrue's own ban_duration "876000h".

-- --------------------------------------------------------- is_blocked ---
-- The caller only, so it can't be used to probe other accounts.
create function public.is_blocked()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from auth.users u
     where u.id = (select auth.uid()) and u.banned_until is not null and u.banned_until > now()
  );
$$;

-- ------------------------------------------------- set_account_blocked ---
create function public.set_account_blocked(target uuid, blocked boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('roles.assign') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if target = auth.uid() then
    raise exception 'cannot block your own account' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users where id = target) then
    raise exception 'unknown user' using errcode = 'P0002';
  end if;

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
  end if;
end;
$$;

-- ---------------------------------------------------- delete_account ---
-- Same effect as the person's own "Konto löschen": public.* rows cascade or
-- lose their author (on delete set null). Fails for the last root.
create function public.delete_account(target uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('roles.assign') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if target = auth.uid() then
    raise exception 'use Konto löschen for your own account' using errcode = '42501';
  end if;
  delete from auth.users where id = target;
  if not found then
    raise exception 'unknown user' using errcode = 'P0002';
  end if;
end;
$$;

-- ---------------------------------------------------- blocked_accounts ---
-- For root's "App-Konten" list.
create function public.blocked_accounts()
returns table (user_id uuid, blocked_until timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('roles.assign') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
    select u.id, u.banned_until from auth.users u
     where u.banned_until is not null and u.banned_until > now();
end;
$$;

-- --------------------------------------- permission checks see blocks ---
create or replace function public.has_permission(requested public.app_permission)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.user_roles ur
      join public.role_permissions rp on rp.role = ur.role
     where ur.user_id = (select auth.uid())
       and rp.permission = requested
  ) and not public.is_blocked();
$$;

create or replace function public.authorize(requested public.app_permission)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.role_permissions rp
     where rp.permission = requested
       and rp.role::text = (select auth.jwt() ->> 'user_role')
  ) and not public.is_blocked();
$$;

create or replace function public.is_approved()
returns boolean
language sql
stable
set search_path = ''
as $$
  select (coalesce((auth.jwt() ->> 'approved')::boolean, false)
          or coalesce(auth.jwt() ->> 'user_role', '') in ('admin', 'root'))
     and not public.is_blocked();
$$;

-- ---------------------------------------------------------------- grants ---
revoke execute on function
  public.is_blocked(),
  public.set_account_blocked(uuid, boolean),
  public.delete_account(uuid),
  public.blocked_accounts()
  from anon, public;

-- is_approved() is granted to anon too and calls is_blocked().
grant execute on function public.is_blocked() to anon, authenticated;
grant execute on function
  public.set_account_blocked(uuid, boolean),
  public.delete_account(uuid),
  public.blocked_accounts()
  to authenticated;
