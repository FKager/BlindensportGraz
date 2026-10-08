-- Row Level Security on every table. Clients never write user_roles,
-- account_approvals, activation_codes or role_change_log directly — only
-- through the SECURITY DEFINER RPCs in the next migration.

alter table public.profiles          enable row level security;
alter table public.user_roles        enable row level security;
alter table public.role_permissions  enable row level security;
alter table public.role_change_log   enable row level security;
alter table public.account_approvals enable row level security;
alter table public.activation_codes  enable row level security;
alter table public.member_private    enable row level security;

-- Table privileges: start from nothing, grant only what policies refine.
revoke all on public.profiles, public.user_roles, public.role_permissions,
              public.role_change_log, public.account_approvals,
              public.activation_codes, public.member_private
  from anon, authenticated;

-- ---------------------------------------------------------------- profiles
grant select on public.profiles to authenticated;
grant update (first_name, last_name) on public.profiles to authenticated;

create policy "profiles: read own or as approver"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.authorize('users.approve')));

create policy "profiles: update own name"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- -------------------------------------------------------------- user_roles
grant select on public.user_roles to authenticated;

create policy "user_roles: read own or as approver"
  on public.user_roles for select to authenticated
  using (user_id = (select auth.uid()) or (select public.authorize('users.approve')));

-- The access-token hook runs as supabase_auth_admin.
create policy "user_roles: auth hook reads"
  on public.user_roles for select to supabase_auth_admin
  using (true);

-- -------------------------------------------------------- role_permissions
grant select on public.role_permissions to authenticated;

create policy "role_permissions: readable when signed in"
  on public.role_permissions for select to authenticated
  using (true);

-- --------------------------------------------------------- role_change_log
grant select on public.role_change_log to authenticated;

create policy "role_change_log: read with permission"
  on public.role_change_log for select to authenticated
  using ((select public.authorize('rolelog.read')));

-- ------------------------------------------------------- account_approvals
grant select on public.account_approvals to authenticated;

create policy "account_approvals: read own or as approver"
  on public.account_approvals for select to authenticated
  using (user_id = (select auth.uid()) or (select public.authorize('users.approve')));

create policy "account_approvals: auth hook reads"
  on public.account_approvals for select to supabase_auth_admin
  using (true);

-- -------------------------------------------------------- activation_codes
-- code_hash is never exposed to clients.
grant select (id, user_id, member_id, created_by, created_at, expires_at, used_at)
  on public.activation_codes to authenticated;

create policy "activation_codes: read as approver"
  on public.activation_codes for select to authenticated
  using ((select public.authorize('users.approve')));

-- ---------------------------------------------------------- member_private
grant select, insert, update, delete on public.member_private to authenticated;

create policy "member_private: read with permission"
  on public.member_private for select to authenticated
  using ((select public.authorize('members.private.read')));

create policy "member_private: insert with permission"
  on public.member_private for insert to authenticated
  with check ((select public.authorize('members.private.write')));

create policy "member_private: update with permission"
  on public.member_private for update to authenticated
  using ((select public.authorize('members.private.write')))
  with check ((select public.authorize('members.private.write')));

create policy "member_private: delete with permission"
  on public.member_private for delete to authenticated
  using ((select public.authorize('members.private.write')));
