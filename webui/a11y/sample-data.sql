-- Sample club data for the web UI accessibility check (webui/a11y), so the
-- tables, lists and reports have rows to check. LOCAL Supabase only
-- (applied by .github/workflows/webui-a11y.yml and scripts/a11y-audit.sh as
-- the postgres user after the seed). Fixed ids: running it again changes
-- nothing. Dates are relative to now, so there is always something upcoming.

begin;

insert into public.teams (id, name, sport, description_text) values
  ('a11a0000-0000-4000-8000-000000000001', 'Torball Herren', 'Torball', 'Training jeden Montag'),
  ('a11a0000-0000-4000-8000-000000000002', 'Blindenfußball', 'Blindenfußball', '')
on conflict (id) do nothing;

insert into public.members (id, first_name, last_name, member_number, sport_id, member_of_gvsc, joined_at, status) values
  ('a11a0000-0000-4000-8000-000000000011', 'Max', 'Muster', '101', 'TB-101', true, now() - interval '400 days', 'active'),
  ('a11a0000-0000-4000-8000-000000000012', 'Anna', 'Beispiel', '102', 'TB-102', true, now() - interval '200 days', 'active'),
  ('a11a0000-0000-4000-8000-000000000013', 'Lukas', 'Neumann', '', '', false, now() - interval '5 days', 'new')
on conflict (id) do nothing;

insert into public.member_contacts (id, street, zip, city, country, email, phone, gender) values
  ('a11a0000-0000-4000-8000-000000000011', 'Hauptplatz 1', '8010', 'Graz', 'Österreich', 'max@example.org', '+43 316 000000', 'm'),
  ('a11a0000-0000-4000-8000-000000000012', 'Annenstraße 2', '8020', 'Graz', 'Österreich', 'anna@example.org', '', 'f'),
  ('a11a0000-0000-4000-8000-000000000013', '', '', 'Wien', '', 'lukas@example.org', '', '')
on conflict (id) do nothing;

insert into public.team_memberships (id, team_id, member_id, user_id, role) values
  ('a11a0000-0000-4000-8000-000000000021', 'a11a0000-0000-4000-8000-000000000001', 'a11a0000-0000-4000-8000-000000000011', null, 'player'),
  ('a11a0000-0000-4000-8000-000000000022', 'a11a0000-0000-4000-8000-000000000001', 'a11a0000-0000-4000-8000-000000000012', null, 'coach'),
  ('a11a0000-0000-4000-8000-000000000023', 'a11a0000-0000-4000-8000-000000000002', 'a11a0000-0000-4000-8000-000000000013', null, 'player')
on conflict (id) do nothing;

insert into public.events (id, kind, title, sport, location, city, start_date, end_date, duration_minutes, status, max_teams, team_ids) values
  ('a11a0000-0000-4000-8000-000000000031', 'training', 'Torballtraining', 'Torball', 'Sporthalle', 'Graz',
     now() + interval '1 day', now() + interval '1 day 90 minutes', 90, 'open', default, array['a11a0000-0000-4000-8000-000000000001']::uuid[]),
  ('a11a0000-0000-4000-8000-000000000032', 'training', 'Torballtraining', 'Torball', 'Sporthalle', 'Graz',
     now() - interval '6 days', now() - interval '6 days' + interval '90 minutes', 90, 'held', default, array['a11a0000-0000-4000-8000-000000000001']::uuid[]),
  ('a11a0000-0000-4000-8000-000000000033', 'tournament', 'Torballturnier', 'Torball', 'Stadthalle', 'Wien',
     now() + interval '8 days', now() + interval '9 days', default, 'planned', 8, array['a11a0000-0000-4000-8000-000000000001']::uuid[]),
  ('a11a0000-0000-4000-8000-000000000034', 'tournament', 'Herbstturnier', 'Torball', 'Halle Süd', 'Linz',
     now() - interval '20 days', now() - interval '19 days', default, 'finished', 6, array['a11a0000-0000-4000-8000-000000000001']::uuid[]),
  ('a11a0000-0000-4000-8000-000000000035', 'event', 'Vereinsfeier', '', 'Vereinslokal', 'Graz',
     now() + interval '15 days', now() + interval '15 days 3 hours', default, default, default, '{}')
on conflict (id) do nothing;

insert into public.attendances (id, event_id, membership_id, attended, prae_amount) values
  ('a11a0000-0000-4000-8000-000000000041', 'a11a0000-0000-4000-8000-000000000032', 'a11a0000-0000-4000-8000-000000000021', true, default),
  ('a11a0000-0000-4000-8000-000000000042', 'a11a0000-0000-4000-8000-000000000032', 'a11a0000-0000-4000-8000-000000000022', true, 30),
  ('a11a0000-0000-4000-8000-000000000043', 'a11a0000-0000-4000-8000-000000000034', 'a11a0000-0000-4000-8000-000000000021', true, 60)
on conflict (id) do nothing;

insert into public.budget_entries (id, category, amount, date, note, event_id) values
  ('a11a0000-0000-4000-8000-000000000051', 'fixedSubsidy', 1200, now() - interval '30 days', 'Jahresförderung', null),
  ('a11a0000-0000-4000-8000-000000000052', 'eventCost', 240.50, now() - interval '19 days', 'Startgeld Herbstturnier', 'a11a0000-0000-4000-8000-000000000034'),
  ('a11a0000-0000-4000-8000-000000000053', 'otherExpense', 35, now() - interval '3 days', 'Bälle', null)
on conflict (id) do nothing;

insert into public.member_change_requests (id, member_id, requested_by, requested_at, status, first_name, last_name, city, email) values
  ('a11a0000-0000-4000-8000-000000000061', 'a11a0000-0000-4000-8000-000000000012', 'anna@example.org', now() - interval '2 days', 'pending',
     'Anna', 'Beispiel', 'Graz', 'anna.neu@example.org')
on conflict (id) do nothing;

insert into public.training_favorites (id, title, sport, weekday, start_hour, start_minute, end_hour, end_minute, location, city, team_ids, last_used_at) values
  ('a11a0000-0000-4000-8000-000000000071', 'Torballtraining', 'Torball', 2, 18, 0, 19, 30, 'Sporthalle', 'Graz',
     array['a11a0000-0000-4000-8000-000000000001']::uuid[], now() - interval '6 days')
on conflict (id) do nothing;

commit;
