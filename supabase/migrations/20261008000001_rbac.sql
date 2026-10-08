-- Accounts, roles, permissions, approvals and protected member data.
-- Pattern: Supabase RBAC guide (roles in a separate table, permissions per
-- role, role injected into the JWT by a Custom Access Token Hook).
-- Club data (schedule, teams, events, roster basics) stays on CloudKit;
-- member_id columns reference CloudKit Member.id UUIDs.

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------- enums ---

-- No user_roles row = "pending" (signed up, no role yet).
create type public.app_role as enum ('member', 'coach', 'admin', 'root');

create type public.app_permission as enum (
  'events.manage',
  'teams.manage',
  'members.manage',
  'members.private.read',
  'members.private.write',
  'users.approve',
  'roles.assign',
  'budget.manage',
  'rolelog.read',
  -- Club-wide scope: all teams/events, delete anyone's uploads.
  'club.manage'
);

-- ------------------------------------------------------------- profiles ---

create table public.profiles (
  id             uuid primary key references auth.users (id) on delete cascade,
  email          text not null default '',
  first_name     text not null default '',
  last_name      text not null default '',
  is_gvsc_member boolean not null default false,
  calendar_token text not null default encode(extensions.gen_random_bytes(24), 'hex'),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index profiles_calendar_token_key on public.profiles (calendar_token);
comment on table public.profiles is
  'One row per auth user, created by trigger. Owner may edit only first/last name.';

-- Profiles are created only here, never by the client.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, first_name, last_name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'first_name', ''),
    coalesce(new.raw_user_meta_data ->> 'last_name', '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Keep profiles.email in step with confirmed email changes.
create function public.handle_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles
     set email = coalesce(new.email, ''), updated_at = now()
   where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row when (old.email is distinct from new.email)
  execute function public.handle_user_email_change();

-- ----------------------------------------------------------- user roles ---

create table public.user_roles (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  role        public.app_role not null,
  -- null = system (migration, seed, rootcli)
  assigned_by uuid references auth.users (id) on delete set null,
  assigned_at timestamptz not null default now()
);

create table public.role_permissions (
  role       public.app_role not null,
  permission public.app_permission not null,
  primary key (role, permission)
);

insert into public.role_permissions (role, permission) values
  ('coach', 'events.manage'),
  ('coach', 'teams.manage'),
  ('admin', 'events.manage'),
  ('admin', 'teams.manage'),
  ('admin', 'members.manage'),
  ('admin', 'members.private.read'),
  ('admin', 'members.private.write'),
  ('admin', 'users.approve'),
  ('admin', 'budget.manage'),
  ('admin', 'rolelog.read'),
  ('admin', 'club.manage'),
  ('root',  'events.manage'),
  ('root',  'teams.manage'),
  ('root',  'members.manage'),
  ('root',  'members.private.read'),
  ('root',  'members.private.write'),
  ('root',  'users.approve'),
  ('root',  'budget.manage'),
  ('root',  'rolelog.read'),
  ('root',  'club.manage'),
  ('root',  'roles.assign');

-- Append-only audit trail, written by trigger only.
create table public.role_change_log (
  id         bigint generated always as identity primary key,
  user_id    uuid not null,
  old_role   public.app_role,
  new_role   public.app_role,
  changed_by uuid,
  changed_at timestamptz not null default now()
);

create function public.log_role_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.role_change_log (user_id, old_role, new_role, changed_by)
  values (
    coalesce(new.user_id, old.user_id),
    case when tg_op = 'INSERT' then null else old.role end,
    case when tg_op = 'DELETE' then null else new.role end,
    auth.uid()
  );
  return null;
end;
$$;

create trigger user_roles_audit
  after insert or update or delete on public.user_roles
  for each row execute function public.log_role_change();

-- ------------------------------------------------------------ approvals ---

-- An approved account is linked to exactly one roster entry.
create table public.account_approvals (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  member_id   uuid not null,
  approved_by uuid references auth.users (id) on delete set null,
  approved_at timestamptz not null default now()
);

-- One-time codes an admin hands to a user. Plain code is returned once by
-- create_activation_code(); only a SHA-256 hash is stored.
create table public.activation_codes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  member_id  uuid,
  code_hash  text not null unique,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '14 days',
  used_at    timestamptz
);

-- ------------------------------------------------- protected member data ---

-- Sensitive roster fields, removed from the CloudKit public database.
create table public.member_private (
  member_id                uuid primary key,
  svnr                     text not null default '',
  iban                     text not null default '',
  birth_date               date,
  last_medical_examination date,
  updated_at               timestamptz not null default now(),
  updated_by               uuid references auth.users (id) on delete set null
);

create function public.touch_member_private()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

create trigger member_private_touch
  before insert or update on public.member_private
  for each row execute function public.touch_member_private();
