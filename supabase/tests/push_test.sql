-- Run with: supabase test db
-- Schedule pushes and device tokens (20261014000001_push).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(18);

-- ------------------------------------------------------------- fixtures ---
create function pg_temp.mk_user(uid uuid, mail text) returns void language sql as $$
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
          mail, '{"first_name":"T","last_name":"User"}', now(), now());
$$;

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

-- A training row to feed schedule_change, with overrides.
create function pg_temp.ev(kind text default 'training', title text default 'Training',
                           status text default 'open', notes text default '',
                           starts timestamptz default now() + interval '1 day',
                           teams uuid[] default array['a0000000-0000-0000-0000-000000000001'::uuid])
returns public.events language sql as $$
  select row('b0000000-0000-0000-0000-000000000001'::uuid, kind, title, '', 'Halle', '', '', '', '',
             starts, starts + interval '2 hours', notes, status, null, null, null, teams,
             '', now(), now(), null)::public.events;
$$;

select pg_temp.mk_user('c0000000-0000-0000-0000-000000000001', 'coach@push.test');
select pg_temp.mk_user('c0000000-0000-0000-0000-000000000002', 'member@push.test');
insert into public.user_roles (user_id, role) values
  ('c0000000-0000-0000-0000-000000000001', 'coach'),
  ('c0000000-0000-0000-0000-000000000002', 'member');
insert into public.members (id, first_name, last_name) values
  ('d0000000-0000-0000-0000-000000000001', 'Carl', 'Coach');
insert into public.account_approvals (user_id, member_id) values
  ('c0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001');
insert into public.teams (id, name, sport) values ('a0000000-0000-0000-0000-000000000001', 'Push Team', 'Torball');

-- ------------------------------------------------------- schedule_change ---
select is(schedule_change(null, pg_temp.ev()), 'created', 'new training pushes "created"');
select is(schedule_change(null, pg_temp.ev(kind => 'tournament')), 'created', 'new tournament pushes');
select is(schedule_change(null, pg_temp.ev(kind => 'event')), null, 'plain events never push');
select is(schedule_change(null, pg_temp.ev(teams => '{}')), null, 'no teams, no recipients');
select is(schedule_change(null, pg_temp.ev(starts => now() - interval '1 day')), null,
  'nothing pushes for an event already over');
select is(schedule_change(pg_temp.ev(), pg_temp.ev(title => 'Neu')), 'updated', 'title change pushes "updated"');
select is(schedule_change(pg_temp.ev(), pg_temp.ev(starts => now() + interval '2 days')), 'updated',
  'moving the date pushes "updated"');
select is(schedule_change(pg_temp.ev(), pg_temp.ev(notes => 'intern')), null, 'a notes-only edit stays quiet');
select is(schedule_change(pg_temp.ev(), pg_temp.ev()), null, 'a re-save without changes stays quiet');
select is(schedule_change(pg_temp.ev(), pg_temp.ev(status => 'cancelled')), 'cancelled',
  'cancelling a training pushes "cancelled"');
select is(schedule_change(pg_temp.ev(status => 'cancelled'), pg_temp.ev(status => 'cancelled', title => 'x')),
  null, 'edits to a cancelled training stay quiet');

-- -------------------------------------------------------------- trigger ---
select vault.create_secret('http://127.0.0.1:9/notify-schedule', 'notify_schedule_url');
select vault.create_secret('test-secret', 'notify_schedule_secret');
create temp table queued_before as select count(*) as n from net.http_request_queue;
grant select on queued_before to authenticated;

insert into public.events (id, kind, title, start_date, end_date, team_ids) values
  ('b0000000-0000-0000-0000-000000000002', 'training', 'Service-Training', now() + interval '1 day',
   now() + interval '1 day 2 hours', array['a0000000-0000-0000-0000-000000000001'::uuid]);
select is((select count(*) from net.http_request_queue) - (select n from queued_before), 0::bigint,
  'service-role writes (rootcli copy) never push');

select pg_temp.act_as('c0000000-0000-0000-0000-000000000001');
insert into public.events (id, kind, title, start_date, end_date, team_ids) values
  ('b0000000-0000-0000-0000-000000000003', 'training', 'Coach-Training', now() + interval '1 day',
   now() + interval '1 day 2 hours', array['a0000000-0000-0000-0000-000000000001'::uuid]);
reset role;
select is((select count(*) from net.http_request_queue) - (select n from queued_before), 1::bigint,
  'a coach creating a training queues one call');
select is((select convert_from(body, 'utf8')::jsonb from net.http_request_queue order by id desc limit 1)
            - 'team_ids' - 'event_id' - 'location',
  jsonb_build_object('kind', 'training', 'change', 'created', 'title', 'Coach-Training',
                     'actor', 'c0000000-0000-0000-0000-000000000001'),
  'the call names the change and who made it');
select is((select headers ->> 'X-Notify-Secret' from net.http_request_queue order by id desc limit 1),
  'test-secret', 'the call carries the shared secret');

-- --------------------------------------------------------- device tokens ---
select pg_temp.act_as('c0000000-0000-0000-0000-000000000002');
select register_device_token('tok-1', 'sandbox');
select pg_temp.act_as('c0000000-0000-0000-0000-000000000001');
select register_device_token('tok-1', 'production');
select is((select user_id from public.device_tokens where token = 'tok-1'),
  'c0000000-0000-0000-0000-000000000001'::uuid, 'the same phone moves to the account now signed in');
select pg_temp.act_as('c0000000-0000-0000-0000-000000000002');
select is((select count(*)::int from public.device_tokens), 0, 'other accounts'' tokens are not readable');
select throws_ok($$insert into public.device_tokens (token, user_id, apns_env)
                   values ('tok-2', 'c0000000-0000-0000-0000-000000000002', 'sandbox')$$,
  '42501', null, 'tokens are written only through register_device_token');

select * from finish();
rollback;
