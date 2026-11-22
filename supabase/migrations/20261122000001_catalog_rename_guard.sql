-- A sport's or event type's name only changes through rename_sport /
-- rename_event_type, which also rename every event, team and training
-- favourite that uses it (references are by name). A direct UPDATE of the
-- name through the API would leave those with the old name, so it's refused.
-- The two functions mark their own update with a transaction-local setting;
-- a REST call can't set it and update the table in the same transaction.

create function public.guard_catalog_rename()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.name is distinct from old.name
     and coalesce(current_setting('bsg.catalog_rename', true), '') <> 'on' then
    raise exception 'rename % only with %', tg_table_name,
      case tg_table_name when 'sports' then 'rename_sport' else 'rename_event_type' end
      using errcode = '42501',
            hint = 'The function also renames the events, teams and favourites that use the old name.';
  end if;
  return new;
end;
$$;

create trigger guard_rename before update of name on public.sports
  for each row execute function public.guard_catalog_rename();
create trigger guard_rename before update of name on public.event_types
  for each row execute function public.guard_catalog_rename();

create or replace function public.rename_sport(p_id uuid, p_name text)
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
  perform set_config('bsg.catalog_rename', 'on', true);
  update public.sports set name = v_new where id = p_id;
  perform set_config('bsg.catalog_rename', '', true);
  update public.events set sport = v_new where sport = v_old;
  update public.teams set sport = v_new where sport = v_old;
  update public.training_favorites set sport = v_new where sport = v_old;
end;
$$;

create or replace function public.rename_event_type(p_id uuid, p_name text)
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
  perform set_config('bsg.catalog_rename', 'on', true);
  update public.event_types set name = v_new where id = p_id;
  perform set_config('bsg.catalog_rename', '', true);
  update public.events set event_type = v_new where event_type = v_old;
end;
$$;
