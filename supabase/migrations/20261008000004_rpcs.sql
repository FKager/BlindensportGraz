-- Write paths for roles and approvals. Every function is SECURITY DEFINER
-- with an empty search_path and checks the caller against the tables
-- (has_permission), never the possibly stale JWT claim.

-- ------------------------------------------------------ last-root guard ---
-- Row trigger, so it also covers cascades from auth.users deletion
-- (delete-account Edge Function) and direct SQL by the service role.
create function public.guard_last_root()
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
      from public.user_roles
     where role = 'root' and user_id <> old.user_id;
    if remaining = 0 then
      raise exception 'cannot remove the last root account'
        using errcode = 'P0001', hint = 'last_root';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;

create trigger user_roles_guard_last_root
  before update or delete on public.user_roles
  for each row execute function public.guard_last_root();

-- ------------------------------------------------------------ set_user_role
-- new_role = null removes the role (account goes back to "pending").
create function public.set_user_role(target uuid, new_role public.app_role)
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
    raise exception 'cannot change your own role' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users where id = target) then
    raise exception 'unknown user' using errcode = 'P0002';
  end if;

  if new_role is null then
    delete from public.user_roles where user_id = target;
  else
    insert into public.user_roles (user_id, role, assigned_by, assigned_at)
    values (target, new_role, auth.uid(), now())
    on conflict (user_id) do update
      set role = excluded.role,
          assigned_by = excluded.assigned_by,
          assigned_at = excluded.assigned_at
      where public.user_roles.role is distinct from excluded.role;
  end if;
end;
$$;

-- ---------------------------------------------------------- approvals
create function public.approve_account(target uuid, p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('users.approve') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into public.account_approvals (user_id, member_id, approved_by, approved_at)
  values (target, p_member_id, auth.uid(), now())
  on conflict (user_id) do update
    set member_id = excluded.member_id,
        approved_by = excluded.approved_by,
        approved_at = excluded.approved_at;
  -- Approved accounts get the base role unless they already have one.
  insert into public.user_roles (user_id, role, assigned_by)
  values (target, 'member', auth.uid())
  on conflict (user_id) do nothing;
end;
$$;

create function public.revoke_approval(target uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_permission('users.approve') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  delete from public.account_approvals where user_id = target;
  -- Staff roles are managed by root via set_user_role; only drop plain member.
  delete from public.user_roles where user_id = target and role = 'member';
end;
$$;

-- ---------------------------------------------------- activation codes
-- Format ABCD-EFGH from an alphabet without 0/O/1/I/L (matches ActivationCode.swift).
create function public.create_activation_code(target uuid, p_member_id uuid default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  bytes bytea := extensions.gen_random_bytes(8);
  raw text := '';
  i int;
begin
  if not public.has_permission('users.approve') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  for i in 0..7 loop
    raw := raw || substr(alphabet, (get_byte(bytes, i) % length(alphabet)) + 1, 1);
  end loop;
  -- Only one open code per user.
  delete from public.activation_codes where user_id = target and used_at is null;
  insert into public.activation_codes (user_id, member_id, code_hash, created_by)
  values (target, p_member_id,
          encode(extensions.digest(raw, 'sha256'), 'hex'), auth.uid());
  return substr(raw, 1, 4) || '-' || substr(raw, 5, 4);
end;
$$;

-- Redeemed by the signed-in user it was issued for. If the admin attached
-- a roster entry, redeeming approves the account.
create function public.redeem_activation_code(code text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized text := upper(regexp_replace(code, '[^A-Za-z0-9]', '', 'g'));
  rec public.activation_codes;
begin
  if auth.uid() is null then
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

-- ---------------------------------------------------- calendar token
create function public.rotate_calendar_token()
returns text
language sql
security definer
set search_path = ''
as $$
  update public.profiles
     set calendar_token = encode(extensions.gen_random_bytes(24), 'hex'),
         updated_at = now()
   where id = (select auth.uid())
  returning calendar_token;
$$;

-- ---------------------------------------------------- grants
revoke execute on function
  public.set_user_role(uuid, public.app_role),
  public.approve_account(uuid, uuid),
  public.revoke_approval(uuid),
  public.create_activation_code(uuid, uuid),
  public.redeem_activation_code(text),
  public.rotate_calendar_token(),
  public.guard_last_root(),
  public.log_role_change(),
  public.handle_new_user(),
  public.handle_user_email_change(),
  public.touch_member_private()
  from anon, public;

grant execute on function
  public.set_user_role(uuid, public.app_role),
  public.approve_account(uuid, uuid),
  public.revoke_approval(uuid),
  public.create_activation_code(uuid, uuid),
  public.redeem_activation_code(text),
  public.rotate_calendar_token()
  to authenticated;
