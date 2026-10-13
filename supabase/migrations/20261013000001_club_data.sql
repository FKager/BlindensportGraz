-- Club data moved from the CloudKit public database (v0.3.0): roster names
-- and contacts, teams, events (trainings/tournaments), attendance, budget,
-- favourites, welcome text, change requests, image/receipt metadata.
--
-- Ids are the former CloudKit record names, so every reference survives
-- the copy (`rootcli cloudkit-copy-to-supabase`).
--
-- Read access mirrors the app (AccessPolicy / user.can):
--   anon + pending accounts  -> public_schedule view and welcome_content only
--   approved accounts        -> club data (not contacts, not budget)
--   members.manage           -> member contacts, change-request review
--   budget.manage            -> budget entries, expense receipts
-- Writes check has_permission() (fresh table lookup), reads authorize()
-- (JWT claim), like the RBAC migrations.

-- ------------------------------------------------------------ helpers ---

-- Full app access: an admin-approved account, or admin/root (who can never
-- lock themselves out) — same rule as AccessPolicy.hasFullAccess.
create function public.is_approved()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((auth.jwt() ->> 'approved')::boolean, false)
      or coalesce(auth.jwt() ->> 'user_role', '') in ('admin', 'root');
$$;
revoke execute on function public.is_approved from public;
grant execute on function public.is_approved to anon, authenticated;

create function public.touch_row()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

-- Deletions are recorded so offline caches can drop rows they still hold.
-- Only ids and table names — nothing readable beyond that.
create table public.deletions (
  table_name text not null,
  row_id     uuid not null,
  deleted_at timestamptz not null default now(),
  primary key (table_name, row_id)
);
create index deletions_deleted_at on public.deletions (deleted_at);

create function public.log_deletion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.deletions (table_name, row_id) values (tg_table_name, old.id)
  on conflict (table_name, row_id) do update set deleted_at = now();
  return old;
end;
$$;

-- A row that comes back (re-created with the same id) is no longer deleted.
create function public.clear_deletion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.deletions where table_name = tg_table_name and row_id = new.id;
  return new;
end;
$$;

-- -------------------------------------------------------------- tables ---

create table public.members (
  id               uuid primary key,
  first_name       text not null,
  last_name        text not null,
  member_number    text not null default '',
  sport_id         text not null default '',
  default_function text not null default '',
  member_of_gvsc   boolean not null default true,
  joined_at        timestamptz not null default now(),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  updated_by       uuid references auth.users (id) on delete set null
);

create table public.member_contacts (
  id         uuid primary key references public.members (id) on delete cascade,
  street     text not null default '',
  zip        text not null default '',
  city       text not null default '',
  country    text not null default '',
  email      text not null default '',
  phone      text not null default '',
  notes      text not null default '',
  gender     text not null default '',
  title      text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);

create table public.teams (
  id               uuid primary key,
  name             text not null,
  sport            text not null default '',
  description_text text not null default '',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  updated_by       uuid references auth.users (id) on delete set null
);

create table public.team_memberships (
  id         uuid primary key,
  team_id    uuid not null references public.teams (id) on delete cascade,
  member_id  uuid references public.members (id) on delete set null,
  user_id    uuid references auth.users (id) on delete set null,
  role       text not null default 'player',
  joined_at  timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);
create index team_memberships_team on public.team_memberships (team_id);
create index team_memberships_user on public.team_memberships (user_id);

-- SportEvent -> Training / Tournament in one table (the app models them as
-- SwiftData subclasses; attendance and images point at any of them).
create table public.events (
  id               uuid primary key,
  kind             text not null check (kind in ('event', 'training', 'tournament')),
  title            text not null,
  sport            text not null default '',
  location         text not null default '',
  street           text not null default '',
  zip              text not null default '',
  city             text not null default '',
  country          text not null default '',
  start_date       timestamptz not null,
  end_date         timestamptz not null,
  notes            text not null default '',
  -- training: open/done/cancelled; tournament: planned/ongoing/finished
  status           text not null default '',
  duration_minutes integer,
  focus_area       text,
  max_teams        integer,
  created_by       text not null default '',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  updated_by       uuid references auth.users (id) on delete set null
);
create index events_start on public.events (start_date);

create table public.event_teams (
  -- Own id so the deletions log and outbox treat it like any other row.
  id       uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  team_id  uuid not null references public.teams (id) on delete cascade,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  unique (event_id, team_id)
);

create table public.attendances (
  id            uuid primary key,
  event_id      uuid not null references public.events (id) on delete cascade,
  membership_id uuid not null references public.team_memberships (id) on delete cascade,
  attended      boolean not null default false,
  recorded_at   timestamptz not null default now(),
  prae_amount   numeric(10, 2),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references auth.users (id) on delete set null
);
create index attendances_event on public.attendances (event_id);

create table public.event_participations (
  id            uuid primary key,
  event_id      uuid not null references public.events (id) on delete cascade,
  user_id       uuid not null references auth.users (id) on delete cascade,
  status        text not null default 'invited',
  registered_at timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references auth.users (id) on delete set null
);

create table public.event_memberships (
  id         uuid primary key,
  event_id   uuid not null references public.events (id) on delete cascade,
  member_id  uuid references public.members (id) on delete cascade,
  user_id    uuid references auth.users (id) on delete cascade,
  added_at   timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);

create table public.budget_entries (
  id         uuid primary key,
  category   text not null,
  amount     numeric(12, 2) not null,
  date       timestamptz not null,
  note       text not null default '',
  event_id   uuid references public.events (id) on delete set null,
  created_by text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);

create table public.training_favorites (
  id           uuid primary key,
  title        text not null,
  sport        text not null default '',
  weekday      integer not null default 2,
  start_hour   integer not null default 0,
  start_minute integer not null default 0,
  end_hour     integer not null default 0,
  end_minute   integer not null default 0,
  location     text not null default '',
  street       text not null default '',
  zip          text not null default '',
  city         text not null default '',
  country      text not null default '',
  -- Small list, always written together with the favourite.
  team_ids     uuid[] not null default '{}',
  last_used_at timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users (id) on delete set null
);

create table public.welcome_content (
  id         uuid primary key,
  markdown   text not null default '',
  is_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);

-- Contact-data change proposals by a member for their own roster entry
-- (protected fields go through member_private_requests instead).
create table public.member_change_requests (
  id           uuid primary key,
  member_id    uuid not null references public.members (id) on delete cascade,
  user_id      uuid references auth.users (id) on delete set null default auth.uid(),
  requested_by text not null default '',
  requested_at timestamptz not null default now(),
  status       text not null default 'pending',
  reviewed_by  text not null default '',
  reviewed_at  timestamptz,
  first_name   text not null default '',
  last_name    text not null default '',
  title        text not null default '',
  gender       text not null default '',
  street       text not null default '',
  zip          text not null default '',
  city         text not null default '',
  country      text not null default '',
  email        text not null default '',
  phone        text not null default '',
  sport_id     text not null default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users (id) on delete set null
);

create table public.event_images (
  id           uuid primary key,
  event_id     uuid references public.events (id) on delete cascade,
  storage_path text not null,
  uploaded_by  text not null default '',
  uploaded_at  timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references auth.users (id) on delete set null
);

create table public.expense_receipts (
  id            uuid primary key,
  tournament_id uuid references public.events (id) on delete set null,
  storage_path  text not null,
  note          text not null default '',
  month         integer,
  year          integer,
  uploaded_by   text not null default '',
  uploaded_at   timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references auth.users (id) on delete set null
);

-- --------------------------------------------- triggers + base grants ---

do $$
declare
  t text;
begin
  foreach t in array array[
    'members', 'member_contacts', 'teams', 'team_memberships', 'events', 'event_teams',
    'attendances', 'event_participations', 'event_memberships', 'budget_entries',
    'training_favorites', 'welcome_content', 'member_change_requests', 'event_images',
    'expense_receipts'
  ] loop
    execute format('create trigger touch before insert or update on public.%I
                      for each row execute function public.touch_row()', t);
    execute format('create trigger log_deletion after delete on public.%I
                      for each row execute function public.log_deletion()', t);
    execute format('create trigger clear_deletion after insert on public.%I
                      for each row execute function public.clear_deletion()', t);
    execute format('create index %I on public.%I (updated_at)', t || '_updated_at', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end;
$$;

alter table public.deletions enable row level security;
revoke all on public.deletions from anon, authenticated;
grant select on public.deletions to anon, authenticated;
create policy "deletions: read" on public.deletions for select to anon, authenticated using (true);

-- ------------------------------------------------------------ policies ---

-- Approved accounts read; one permission writes.
do $$
declare
  rule record;
begin
  for rule in
    select * from (values
      ('members',              'members.manage'),
      ('teams',                'teams.manage'),
      ('team_memberships',     'teams.manage'),
      ('events',               'events.manage'),
      ('event_teams',          'events.manage'),
      ('attendances',          'events.manage'),
      ('event_memberships',    'events.manage'),
      ('training_favorites',   'events.manage'),
      ('event_images',         'events.manage')
    ) as r(tbl, perm)
  loop
    execute format('create policy "%1$s: approved read" on public.%1$I for select to authenticated
                      using ((select public.is_approved()))', rule.tbl);
    execute format('create policy "%1$s: insert" on public.%1$I for insert to authenticated
                      with check ((select public.has_permission(%2$L)))', rule.tbl, rule.perm);
    execute format('create policy "%1$s: update" on public.%1$I for update to authenticated
                      using ((select public.has_permission(%2$L)))
                      with check ((select public.has_permission(%2$L)))', rule.tbl, rule.perm);
    execute format('create policy "%1$s: delete" on public.%1$I for delete to authenticated
                      using ((select public.has_permission(%2$L)))', rule.tbl, rule.perm);
  end loop;
end;
$$;

-- Same, but readable only with a permission (not by every approved account).
do $$
declare
  rule record;
begin
  for rule in
    select * from (values
      ('member_contacts',  'members.manage'),
      ('budget_entries',   'budget.manage'),
      ('expense_receipts', 'budget.manage')
    ) as r(tbl, perm)
  loop
    execute format('create policy "%1$s: read" on public.%1$I for select to authenticated
                      using ((select public.authorize(%2$L)))', rule.tbl, rule.perm);
    execute format('create policy "%1$s: insert" on public.%1$I for insert to authenticated
                      with check ((select public.has_permission(%2$L)))', rule.tbl, rule.perm);
    execute format('create policy "%1$s: update" on public.%1$I for update to authenticated
                      using ((select public.has_permission(%2$L)))
                      with check ((select public.has_permission(%2$L)))', rule.tbl, rule.perm);
    execute format('create policy "%1$s: delete" on public.%1$I for delete to authenticated
                      using ((select public.has_permission(%2$L)))', rule.tbl, rule.perm);
  end loop;
end;
$$;

-- A member also reads their own contact details ("Vereinsdaten bearbeiten").
create policy "member_contacts: read own" on public.member_contacts for select to authenticated
  using (id = (select public.my_member_id()));

-- Participations: everyone approved reads; each account (un)registers itself;
-- events.manage manages all.
create policy "event_participations: approved read" on public.event_participations
  for select to authenticated using ((select public.is_approved()));
create policy "event_participations: own or manager insert" on public.event_participations
  for insert to authenticated
  with check (((select public.is_approved()) and user_id = (select auth.uid()))
              or (select public.has_permission('events.manage')));
create policy "event_participations: own or manager update" on public.event_participations
  for update to authenticated
  using (user_id = (select auth.uid()) or (select public.has_permission('events.manage')))
  with check (((select public.is_approved()) and user_id = (select auth.uid()))
              or (select public.has_permission('events.manage')));
create policy "event_participations: own or manager delete" on public.event_participations
  for delete to authenticated
  using (user_id = (select auth.uid()) or (select public.has_permission('events.manage')));

-- Change requests: a member proposes for their own entry; members.manage reviews.
create policy "member_change_requests: read own or reviewer" on public.member_change_requests
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.authorize('members.manage')));
create policy "member_change_requests: propose own" on public.member_change_requests
  for insert to authenticated
  with check ((select public.is_approved())
              and user_id = (select auth.uid())
              and member_id = (select public.my_member_id())
              and status = 'pending');
create policy "member_change_requests: review" on public.member_change_requests
  for update to authenticated
  using ((select public.has_permission('members.manage')))
  with check ((select public.has_permission('members.manage')));
create policy "member_change_requests: delete" on public.member_change_requests
  for delete to authenticated
  using ((select public.has_permission('members.manage')));

-- Welcome text: shown to everyone at startup, also before signing in.
grant select on public.welcome_content to anon;
create policy "welcome_content: read" on public.welcome_content
  for select to anon, authenticated using (true);
create policy "welcome_content: insert" on public.welcome_content
  for insert to authenticated with check ((select public.has_permission('club.manage')));
create policy "welcome_content: update" on public.welcome_content
  for update to authenticated
  using ((select public.has_permission('club.manage')))
  with check ((select public.has_permission('club.manage')));
create policy "welcome_content: delete" on public.welcome_content
  for delete to authenticated using ((select public.has_permission('club.manage')));

-- ------------------------------------------------------ public schedule ---

-- What anonymous and not-yet-approved accounts may see: name, date, place
-- (UpcomingScheduleSections). A view owned by postgres, so it bypasses the
-- events RLS on purpose and exposes only these columns.
create view public.public_schedule
with (security_invoker = false)
as
select id, kind, title, sport, location, city, start_date, end_date, status, updated_at
  from public.events
 where kind in ('training', 'tournament');

revoke all on public.public_schedule from anon, authenticated;
grant select on public.public_schedule to anon, authenticated;

-- ------------------------------------------------------- team names ---

-- The app creates missing default teams by name (Team.defaultTeams); this
-- keeps two devices from creating the same team twice.
create unique index teams_name_unique on public.teams (lower(btrim(name)));
