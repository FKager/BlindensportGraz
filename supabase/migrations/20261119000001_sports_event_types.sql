-- Sports (Sportarten) and event types (Veranstaltungsarten) become tables
-- that admins (club.manage) extend instead of lists hard-coded in the app and
-- the web UI.
--
-- References stay by NAME: events.sport, teams.sport and
-- training_favorites.sport keep their text columns, and events gets a new
-- event_type text column. Older app builds keep reading and writing those
-- columns unchanged. Renaming goes through rename_sport / rename_event_type,
-- which update every referencing row in the same transaction (their
-- updated_at moves, so every client pulls the new name). Entries are
-- deactivated, not deleted, so past events keep a valid name.
--
-- Each event type has a behaviour: 'training', 'tournament' or 'event' —
-- the existing events.kind, which decides status values, teams, PRAE and
-- reports. A new type like "Trainingslager" can behave like a training.

-- ------------------------------------------------------------- tables ---

create table public.sports (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (btrim(name) <> '' and name = btrim(name)),
  is_active  boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);
create unique index sports_name_unique on public.sports (lower(name));

create table public.event_types (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (btrim(name) <> '' and name = btrim(name)),
  behavior   text not null check (behavior in ('training', 'tournament', 'event')),
  is_active  boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);
create unique index event_types_name_unique on public.event_types (lower(name));

alter table public.events add column event_type text not null default '';

-- Same plumbing as every synced club table (20261013000001).
do $$
declare
  t text;
begin
  foreach t in array array['sports', 'event_types'] loop
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
    execute format('create policy "%s: approved read" on public.%I for select to authenticated
                      using ((select public.is_approved()))', t, t);
    execute format('create policy "%s: insert" on public.%I for insert to authenticated
                      with check ((select public.has_permission(''club.manage'')))', t, t);
    execute format('create policy "%s: update" on public.%I for update to authenticated
                      using ((select public.has_permission(''club.manage'')))
                      with check ((select public.has_permission(''club.manage'')))', t, t);
    execute format('create policy "%s: delete" on public.%I for delete to authenticated
                      using ((select public.has_permission(''club.manage'')))', t, t);
  end loop;
end;
$$;

-- --------------------------------------------------------------- seed ---

insert into public.sports (name, sort_order) values
  ('Torball', 10), ('Goalball', 20), ('Blindenfußball', 30), ('Showdown', 40),
  ('Judo', 50), ('Leichtathletik', 60), ('Schwimmen', 70), ('Ski', 80), ('Radfahren', 90);

insert into public.event_types (name, behavior, sort_order) values
  ('Training', 'training', 10),
  ('Turnier', 'tournament', 20),
  ('Kurs', 'event', 30),
  ('Langlaufkurs', 'event', 40),
  ('Tandemfahrt', 'event', 50),
  ('Generalversammlung', 'event', 60),
  ('Weihnachtsfeier', 'event', 70),
  ('ÖSTM Nordisch', 'event', 80),
  ('ÖM Torball', 'event', 90);

-- Plain events stored their type in `sport` (the app's "Art der
-- Veranstaltung" picker). Any such value becomes an event type; the sport
-- is cleared.
insert into public.event_types (name, behavior, sort_order)
select distinct btrim(sport), 'event', 100
  from public.events
 where kind = 'event' and btrim(sport) <> ''
on conflict do nothing;

update public.events
   set event_type = btrim(sport), sport = ''
 where kind = 'event' and btrim(sport) <> '';

update public.events set event_type = 'Training' where kind = 'training' and event_type = '';
update public.events set event_type = 'Turnier'  where kind = 'tournament' and event_type = '';

-- Any sport already in use (free text from earlier builds) joins the list.
insert into public.sports (name, sort_order)
select distinct btrim(s), 100
  from (select sport as s from public.events
        union select sport from public.teams
        union select sport from public.training_favorites) used
 where btrim(s) <> ''
on conflict do nothing;

-- -------------------------------------------- older app builds (compat) ---

-- Builds before this change don't send event_type. Fill it from kind, and
-- for a plain event take the type the old picker wrote into `sport`.
create function public.fill_event_type()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if btrim(new.event_type) = '' then
    if new.kind = 'training' then
      new.event_type := 'Training';
    elsif new.kind = 'tournament' then
      new.event_type := 'Turnier';
    elsif exists (select 1 from public.event_types
                   where lower(name) = lower(btrim(new.sport)) and behavior = 'event') then
      new.event_type := btrim(new.sport);
      new.sport := '';
    end if;
  end if;
  return new;
end;
$$;

create trigger fill_event_type before insert or update on public.events
  for each row execute function public.fill_event_type();

-- ------------------------------------------------------------- rename ---

create function public.rename_sport(p_id uuid, p_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text;
  v_new text := btrim(p_name);
begin
  if not public.has_permission('club.manage') then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  select name into v_old from public.sports where id = p_id for update;
  if v_old is null then
    raise exception 'sport not found' using errcode = 'P0002';
  end if;
  if v_new = v_old then
    return;
  end if;
  update public.sports set name = v_new where id = p_id;
  update public.events set sport = v_new where sport = v_old;
  update public.teams set sport = v_new where sport = v_old;
  update public.training_favorites set sport = v_new where sport = v_old;
end;
$$;

create function public.rename_event_type(p_id uuid, p_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text;
  v_new text := btrim(p_name);
begin
  if not public.has_permission('club.manage') then
    raise exception 'permission denied' using errcode = '42501';
  end if;
  select name into v_old from public.event_types where id = p_id for update;
  if v_old is null then
    raise exception 'event type not found' using errcode = 'P0002';
  end if;
  if v_new = v_old then
    return;
  end if;
  update public.event_types set name = v_new where id = p_id;
  update public.events set event_type = v_new where event_type = v_old;
end;
$$;

revoke all on function public.rename_sport(uuid, text) from public, anon;
revoke all on function public.rename_event_type(uuid, text) from public, anon;
grant execute on function public.rename_sport(uuid, text) to authenticated;
grant execute on function public.rename_event_type(uuid, text) to authenticated;

-- The behaviour of a type in use can't change: a training can't turn into
-- a tournament (different status values, and the app models them as
-- different classes).
create function public.event_type_behavior_fixed()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.behavior <> old.behavior
     and exists (select 1 from public.events where event_type = old.name) then
    raise exception 'event type % is in use; its behavior cannot change', old.name
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger behavior_fixed before update on public.event_types
  for each row execute function public.event_type_behavior_fixed();
