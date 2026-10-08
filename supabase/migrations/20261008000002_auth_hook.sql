-- Custom Access Token Hook: adds `user_role` (text or null) and `approved`
-- (bool) claims to every access token. Configured in config.toml
-- ([auth.hook.custom_access_token]) and in the dashboard for the hosted project.

create function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $$
declare
  claims    jsonb;
  uid       uuid := (event ->> 'user_id')::uuid;
  the_role  public.app_role;
  is_approved boolean;
begin
  select role into the_role from public.user_roles where user_id = uid;
  select exists (select 1 from public.account_approvals where user_id = uid)
    into is_approved;

  claims := event -> 'claims';
  if the_role is not null then
    claims := jsonb_set(claims, '{user_role}', to_jsonb(the_role));
  else
    claims := jsonb_set(claims, '{user_role}', 'null');
  end if;
  -- Staff roles always get the full app, like before.
  claims := jsonb_set(claims, '{approved}',
    to_jsonb(coalesce(is_approved, false)
             or coalesce(the_role in ('admin', 'root'), false)));

  return jsonb_set(event, '{claims}', claims);
end;
$$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook from authenticated, anon, public;

grant select on table public.user_roles to supabase_auth_admin;
grant select on table public.account_approvals to supabase_auth_admin;

-- ------------------------------------------------------------ authorize ---

-- For RLS policies on read paths: trusts the JWT role claim (≤ 15 min old).
-- Write RPCs use has_permission() against the tables instead.
create function public.authorize(requested public.app_permission)
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
  );
$$;

-- Fresh, table-based check for the caller (used by every write RPC).
create function public.has_permission(requested public.app_permission)
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
  );
$$;

revoke execute on function public.authorize from anon, public;
revoke execute on function public.has_permission from anon, public;
grant execute on function public.authorize to authenticated;
grant execute on function public.has_permission to authenticated;
