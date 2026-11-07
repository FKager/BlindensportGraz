-- Vereinsfunktionen: who is Obmann, Obmann Stellvertreter, Kassier and
-- Schriftführer. One holder each, and one member may hold several. They record
-- a position and give no rights: rights stay with user_roles. Roster entries,
-- not accounts, so a holder needs no login.

create table public.club_functions (
  function_key text primary key
    check (function_key in ('obmann', 'obmann_stellvertreter', 'kassier', 'schriftfuehrer')),
  member_id    uuid not null references public.members (id) on delete cascade,
  -- Kept here so the log can still name them when the member is deleted.
  member_name  text not null,
  updated_by   uuid references auth.users (id) on delete set null,
  updated_at   timestamptz not null default now()
);
create index club_functions_member on public.club_functions (member_id);

-- Append-only, written by trigger only.
create table public.club_function_log (
  id           bigint generated always as identity primary key,
  function_key text not null,
  old_name     text,
  new_name     text,
  changed_by   uuid,
  changed_at   timestamptz not null default now()
);

alter table public.club_functions enable row level security;
alter table public.club_function_log enable row level security;
revoke all on public.club_functions, public.club_function_log from anon, authenticated;
grant select on public.club_functions, public.club_function_log to authenticated;

create policy "club_functions: approved read" on public.club_functions
  for select to authenticated using ((select public.is_approved()));
create policy "club_function_log: read with permission" on public.club_function_log
  for select to authenticated using ((select public.authorize('rolelog.read')));

create function public.log_club_function()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.club_function_log (function_key, old_name, new_name, changed_by)
  values (
    coalesce(new.function_key, old.function_key),
    case when tg_op = 'INSERT' then null else old.member_name end,
    case when tg_op = 'DELETE' then null else new.member_name end,
    auth.uid()
  );
  return null;
end;
$$;

create trigger club_functions_log
  after insert or update or delete on public.club_functions
  for each row execute function public.log_club_function();

-- p_member null leaves the function vacant. Assigning replaces the holder.
create function public.set_club_function(p_function text, p_member uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry public.members%rowtype;
begin
  if not public.has_permission('club.manage') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_function not in ('obmann', 'obmann_stellvertreter', 'kassier', 'schriftfuehrer') then
    raise exception 'unknown club function' using errcode = '22023';
  end if;
  if p_member is null then
    delete from public.club_functions where function_key = p_function;
    return;
  end if;
  select * into entry from public.members where id = p_member;
  if not found then
    raise exception 'unknown member' using errcode = 'P0002';
  end if;
  insert into public.club_functions (function_key, member_id, member_name, updated_by)
  values (p_function, p_member, btrim(entry.first_name || ' ' || entry.last_name), auth.uid())
  on conflict (function_key) do update
    set member_id = excluded.member_id, member_name = excluded.member_name,
        updated_by = excluded.updated_by, updated_at = now()
    where public.club_functions.member_id is distinct from excluded.member_id;
end;
$$;

revoke execute on function public.set_club_function(text, uuid) from public, anon;
grant execute on function public.set_club_function(text, uuid) to authenticated;
