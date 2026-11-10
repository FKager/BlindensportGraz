-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(7);

insert into public.teams (id, name, sport) values ('a0000000-0000-0000-0000-000000000001', 'Torball Helfer', 'Torball');
insert into public.team_memberships (id, team_id, role)
  values ('a0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'coach');
insert into public.events (id, kind, title, sport, start_date, end_date)
  values ('a0000000-0000-0000-0000-000000000003', 'training', 'Torball', 'Torball', now(), now());

insert into public.attendances (id, event_id, membership_id, attended, prae_amount)
  values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003',
          'a0000000-0000-0000-0000-000000000002', true, 20);

select lives_ok($$insert into public.attendances (id, event_id, membership_id, attended, prae_amount)
                  values ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000003',
                          'a0000000-0000-0000-0000-000000000002', true, 30)$$,
  'a second row for the same person and training is accepted');
select is((select count(*)::int from public.attendances where event_id = 'a0000000-0000-0000-0000-000000000003'),
  1, '... but merged: still one row');
select is((select prae_amount from public.attendances where id = 'b0000000-0000-0000-0000-000000000001'),
  30.00::numeric, '... the existing row took the new amount');

select lives_ok($$insert into public.attendances (id, event_id, membership_id, attended, prae_amount)
                  values ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000003',
                          'a0000000-0000-0000-0000-000000000002', true, 40)
                  on conflict (id) do update set prae_amount = excluded.prae_amount$$,
  'an app-style upsert by a new id merges too');
select is((select prae_amount from public.attendances where id = 'b0000000-0000-0000-0000-000000000001'),
  40.00::numeric, '... into the existing row');

insert into public.attendances (id, event_id, membership_id, attended, prae_amount)
  values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003',
          'a0000000-0000-0000-0000-000000000002', false, null)
  on conflict (id) do update set attended = excluded.attended, prae_amount = excluded.prae_amount;
select is((select attended from public.attendances where id = 'b0000000-0000-0000-0000-000000000001'),
  false, 'an upsert by the existing id still updates it');

select has_index('public', 'attendances', 'attendances_event_membership_key', 'unique key on event + membership');

select * from finish();
rollback;
