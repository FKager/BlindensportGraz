-- Schedule pushes (v0.3.0; replaces the CloudKit query subscriptions):
-- "Neues Training", "Training geändert", "Training abgesagt", "Neues Turnier",
-- "Turnier geändert" for everyone in one of the event's teams.
--
-- The app registers its APNs token in device_tokens. A trigger on events
-- queues an HTTP call (pg_net, asynchronous, outside the writing
-- transaction) to the Edge Function notify-schedule, which picks the
-- recipients and talks to APNs.
--
-- The function URL and a shared secret come from Vault, so the migration is
-- the same on every project:
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1/notify-schedule', 'notify_schedule_url');
--   select vault.create_secret('<random>', 'notify_schedule_secret');
-- (the secret also goes to the function: supabase secrets set NOTIFY_SCHEDULE_SECRET=<random>).
-- Without them the trigger does nothing — local databases and tests send no pushes.

create extension if not exists pg_net;

-- ------------------------------------------------------- device tokens ---

create table public.device_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  apns_env   text not null check (apns_env in ('sandbox', 'production')),
  updated_at timestamptz not null default now()
);
create index device_tokens_user on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

create policy device_tokens_select on public.device_tokens for select to authenticated
  using (user_id = (select auth.uid()));
create policy device_tokens_delete on public.device_tokens for delete to authenticated
  using (user_id = (select auth.uid()));
-- Writes go through register_device_token: a phone that changes accounts
-- keeps its token, and RLS would not let the new account take over the
-- previous account's row.

-- Binds this device's token to the caller (moving it from any previous
-- account on the same phone).
create function public.register_device_token(p_token text, p_apns_env text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if p_apns_env not in ('sandbox', 'production') then
    raise exception 'invalid apns_env %', p_apns_env using errcode = '22023';
  end if;
  insert into public.device_tokens (token, user_id, apns_env)
  values (p_token, auth.uid(), p_apns_env)
  on conflict (token) do update
    set user_id = excluded.user_id, apns_env = excluded.apns_env, updated_at = now();
end;
$$;
revoke execute on function public.register_device_token from public, anon;
grant execute on function public.register_device_token to authenticated;

-- ------------------------------------------------------------- trigger ---

-- Which push an event change is, or null for none. Trainings: created,
-- cancelled (status becomes cancelled), updated (anything a member would
-- act on, while not cancelled). Tournaments: created, updated. Plain
-- events never pushed under CloudKit either; nor does anything already over.
create function public.schedule_change(old_row public.events, new_row public.events)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when new_row.kind not in ('training', 'tournament') or cardinality(new_row.team_ids) = 0
         or new_row.end_date < now() then null
    when old_row is null then 'created'
    when new_row.kind = 'training' and new_row.status = 'cancelled'
         and old_row.status is distinct from 'cancelled' then 'cancelled'
    when new_row.kind = 'training' and new_row.status = 'cancelled' then null
    when (old_row.title, old_row.location, old_row.street, old_row.city, old_row.start_date,
          old_row.end_date, old_row.status, old_row.team_ids)
         is distinct from
         (new_row.title, new_row.location, new_row.street, new_row.city, new_row.start_date,
          new_row.end_date, new_row.status, new_row.team_ids) then 'updated'
    else null
  end;
$$;

create function public.notify_schedule()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  change text := public.schedule_change(old, new);  -- old is null on insert
  url text;
  secret text;
begin
  -- Only changes made by a person in the app push; service-role writes
  -- (rootcli copy, admin scripts) never do.
  if auth.uid() is null or change is null then
    return null;
  end if;
  select decrypted_secret into url from vault.decrypted_secrets where name = 'notify_schedule_url';
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'notify_schedule_secret';
  if url is null or secret is null then
    return null;
  end if;
  perform net.http_post(
    url := url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'X-Notify-Secret', secret),
    body := jsonb_build_object(
      'event_id', new.id,
      'kind', new.kind,
      'change', change,
      'title', new.title,
      'location', new.location,
      'team_ids', to_jsonb(new.team_ids),
      -- The person who saved it doesn't need to be told.
      'actor', auth.uid()
    )
  );
  return null;
end;
$$;
revoke execute on function public.notify_schedule from public, anon, authenticated;

create trigger events_notify_schedule
  after insert or update on public.events
  for each row execute function public.notify_schedule();
