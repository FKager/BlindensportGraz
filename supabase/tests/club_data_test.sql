-- Run with: supabase test db
-- Access rules for the club data moved from CloudKit (20261013000001/2).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(31);

-- ------------------------------------------------------------- fixtures ---
create function pg_temp.mk_user(uid uuid, mail text) returns void language sql as $$
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
          mail, '{"first_name":"T","last_name":"User"}', now(), now());
$$;

-- Claims shaped like the access-token hook's output (user_role, approved).
create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
declare r text; a boolean;
begin
  reset role;
  select role::text into r from public.user_roles where user_id = uid;
  a := exists (select 1 from public.account_approvals where user_id = uid);
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated', 'user_role', r, 'approved', a)::text, true);
  set local role authenticated;
end;
$$;

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
end;
$$;

select pg_temp.mk_user('55555555-0000-0000-0000-000000000001', 'admin@cd.test');
select pg_temp.mk_user('55555555-0000-0000-0000-000000000002', 'coach@cd.test');
select pg_temp.mk_user('55555555-0000-0000-0000-000000000003', 'member@cd.test');
select pg_temp.mk_user('55555555-0000-0000-0000-000000000004', 'pending@cd.test');
insert into public.user_roles (user_id, role) values
  ('55555555-0000-0000-0000-000000000001', 'admin'),
  ('55555555-0000-0000-0000-000000000002', 'coach'),
  ('55555555-0000-0000-0000-000000000003', 'member');

insert into public.members (id, first_name, last_name) values
  ('66666666-0000-0000-0000-000000000001', 'Mia', 'Member'),
  ('66666666-0000-0000-0000-000000000002', 'Carl', 'Coach');
insert into public.member_contacts (id, street, phone) values
  ('66666666-0000-0000-0000-000000000001', 'Gasse 1', '0664 1'),
  ('66666666-0000-0000-0000-000000000002', 'Gasse 2', '0664 2');
insert into public.account_approvals (user_id, member_id) values
  ('55555555-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000002'),
  ('55555555-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000001');

insert into public.teams (id, name, sport) values ('77777777-0000-0000-0000-000000000001', 'Test Team', 'Torball');
insert into public.team_memberships (id, team_id, member_id, user_id) values
  ('77777777-0000-0000-0000-000000000002', '77777777-0000-0000-0000-000000000001',
   '66666666-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000003');
insert into public.events (id, kind, title, start_date, end_date, notes, status, team_ids) values
  ('88888888-0000-0000-0000-000000000001', 'training', 'Torball Training',
   now() + interval '1 day', now() + interval '1 day 2 hours', 'internal note', 'open',
   array['77777777-0000-0000-0000-000000000001'::uuid]);
insert into public.attendances (id, event_id, membership_id, attended) values
  ('88888888-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001',
   '77777777-0000-0000-0000-000000000002', true);
insert into public.budget_entries (id, category, amount, date) values
  ('99999999-0000-0000-0000-000000000001', 'membershipFees', 50, now());
insert into public.welcome_content (id, markdown, is_enabled) values
  ('99999999-0000-0000-0000-000000000002', 'Willkommen', true);

-- ------------------------------------------------------------ anonymous ---
select pg_temp.act_as_anon();
select is((select count(*)::int from public.public_schedule), 1, 'anon sees the schedule');
select throws_ok($$select * from public.events$$, '42501', null, 'anon cannot read events directly');
select throws_ok($$select * from public.members$$, '42501', null, 'anon cannot read the roster');
select is((select count(*)::int from public.welcome_content), 1, 'anon reads the welcome text');

reset role;
select hasnt_column('public', 'public_schedule', 'notes', 'schedule view hides notes');
select hasnt_column('public', 'public_schedule', 'street', 'schedule view hides the address');

-- -------------------------------------------------------------- pending ---
select pg_temp.act_as('55555555-0000-0000-0000-000000000004');
select is((select count(*)::int from public.events), 0, 'pending account sees no events');
select is((select count(*)::int from public.public_schedule), 1, 'pending account sees the schedule');
select is((select count(*)::int from public.members), 0, 'pending account sees no roster');

-- --------------------------------------------------------------- member ---
select pg_temp.act_as('55555555-0000-0000-0000-000000000003');
select is((select count(*)::int from public.events), 1, 'member reads events');
select is((select count(*)::int from public.members), 2, 'member reads roster names');
select is((select count(*)::int from public.attendances), 1, 'member reads attendance');
select is((select array_agg(street) from public.member_contacts), array['Gasse 1'],
  'member reads only own contact details');
select is((select count(*)::int from public.budget_entries), 0, 'member sees no budget');
select throws_ok($$insert into public.events (id, kind, title, start_date, end_date)
                   values (gen_random_uuid(), 'training', 'x', now(), now())$$,
  '42501', null, 'member cannot create events');
select lives_ok($$insert into public.event_participations (id, event_id, user_id)
                  values (gen_random_uuid(), '88888888-0000-0000-0000-000000000001',
                          '55555555-0000-0000-0000-000000000003')$$,
  'member registers themself for an event');
select throws_ok($$insert into public.event_participations (id, event_id, user_id)
                   values (gen_random_uuid(), '88888888-0000-0000-0000-000000000001',
                           '55555555-0000-0000-0000-000000000002')$$,
  '42501', null, 'member cannot register someone else');
select lives_ok($$insert into public.member_change_requests (id, member_id, user_id, street)
                  values (gen_random_uuid(), '66666666-0000-0000-0000-000000000001',
                          '55555555-0000-0000-0000-000000000003', 'Neue Gasse 3')$$,
  'member proposes a change to their own entry');
select throws_ok($$insert into public.member_change_requests (id, member_id, user_id)
                   values (gen_random_uuid(), '66666666-0000-0000-0000-000000000002',
                           '55555555-0000-0000-0000-000000000003')$$,
  '42501', null, 'member cannot propose changes to someone else''s entry');

-- ---------------------------------------------------------------- coach ---
select pg_temp.act_as('55555555-0000-0000-0000-000000000002');
select lives_ok($$insert into public.events (id, kind, title, start_date, end_date)
                  values ('88888888-0000-0000-0000-000000000009', 'tournament', 'Cup', now(), now())$$,
  'coach creates an event');
select is((select count(*)::int from public.member_contacts), 1, 'coach reads only own contact details');
select throws_ok($$insert into public.budget_entries (id, category, amount, date)
                   values (gen_random_uuid(), 'x', 1, now())$$,
  '42501', null, 'coach cannot write the budget');
select lives_ok($$delete from public.events where id = '88888888-0000-0000-0000-000000000001'$$,
  'coach deletes an event');

reset role;
select is((select updated_by from public.events where id = '88888888-0000-0000-0000-000000000009'),
  '55555555-0000-0000-0000-000000000002'::uuid, 'updated_by records the coach');
select is((select array_agg(table_name::text order by table_name) from public.deletions
            where row_id in ('88888888-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000002')),
  array['attendances', 'events'], 'deleting an event logs it and its cascaded attendance');
select throws_ok($$insert into public.teams (id, name) values (gen_random_uuid(), ' test team')$$,
  '23505', null, 'team names are unique (case and spaces ignored)');

insert into public.events (id, kind, title, start_date, end_date, team_ids) values
  ('88888888-0000-0000-0000-000000000003', 'training', 'T2', now(), now(),
   array['77777777-0000-0000-0000-000000000001'::uuid]);
delete from public.teams where id = '77777777-0000-0000-0000-000000000001';
select is((select team_ids from public.events where id = '88888888-0000-0000-0000-000000000003'),
  '{}'::uuid[], 'a deleted team is removed from event team lists');

-- ---------------------------------------------------------------- admin ---
select pg_temp.act_as('55555555-0000-0000-0000-000000000001');
select is((select count(*)::int from public.member_contacts), 2, 'admin reads all contact details');
select is((select count(*)::int from public.budget_entries), 1, 'admin reads the budget');

-- -------------------------------------------------------------- storage ---
select pg_temp.act_as('55555555-0000-0000-0000-000000000003');
select throws_ok($$insert into storage.objects (bucket_id, name) values ('event-images', 'x.jpg')$$,
  '42501', null, 'member cannot upload event images');
select pg_temp.act_as('55555555-0000-0000-0000-000000000002');
select lives_ok($$insert into storage.objects (bucket_id, name) values ('event-images', 'y.jpg')$$,
  'coach uploads an event image');

select * from finish();
rollback;
