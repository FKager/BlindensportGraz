-- One attendance row per event and team membership.
--
-- Clients upsert attendances by their own row id. A device whose local copy
-- lacked the server's row (the CloudKit handover on 2026-10-17) inserted a
-- second row for the same person and training, and KostZ/PRAE then counted
-- the PRAE amount twice. From now on:
--   1. existing duplicates are merged (the most recently updated row stays),
--   2. an insert for a pair that already has a row updates that row instead
--      and is skipped — so app versions already installed keep working
--      (they upsert with return=minimal and see a normal success; their
--      local row is pruned and the server's row pulled on the next sync),
--   3. a unique constraint guarantees it.

delete from public.attendances a
 using public.attendances b
 where a.event_id = b.event_id
   and a.membership_id = b.membership_id
   and (a.updated_at, a.id) < (b.updated_at, b.id);

create or replace function public.attendances_merge_duplicate()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  update public.attendances
     set attended = new.attended,
         prae_amount = new.prae_amount,
         recorded_at = new.recorded_at
   where event_id = new.event_id
     and membership_id = new.membership_id
     and id <> new.id;
  if found then
    return null;
  end if;
  return new;
end;
$$;

create trigger attendances_merge_duplicate
  before insert on public.attendances
  for each row execute function public.attendances_merge_duplicate();

alter table public.attendances
  add constraint attendances_event_membership_key unique (event_id, membership_id);
