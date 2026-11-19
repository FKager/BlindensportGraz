-- Sports and event types (20261119000001). Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(20);

create function pg_temp.mk_user(uid uuid, mail text) returns void language sql as $$
  insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', mail, now(), now());
$$;

create function pg_temp.act_as(uid uuid, approved boolean default true) returns void language plpgsql as $$
declare r text;
begin
  reset role;
  select role::text into r from public.user_roles where user_id = uid;
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated', 'user_role', r, 'approved', approved)::text, true);
  set local role authenticated;
end;
$$;

-- admin, coach, pending (no role, not approved)
select pg_temp.mk_user('66666666-0000-0000-0000-000000000001', 'a@st.test');
select pg_temp.mk_user('66666666-0000-0000-0000-000000000002', 'c@st.test');
select pg_temp.mk_user('66666666-0000-0000-0000-000000000003', 'p@st.test');
insert into public.user_roles (user_id, role) values
  ('66666666-0000-0000-0000-000000000001', 'admin'),
  ('66666666-0000-0000-0000-000000000002', 'coach');

-- seed
select ok((select count(*) from public.sports where name in ('Torball', 'Blindenfußball')) = 2,
  'seed has the sports in use');
select is((select behavior from public.event_types where name = 'Turnier'), 'tournament',
  'Turnier behaves like a tournament');

-- older builds: event_type filled from kind / from the type in sport
insert into public.events (id, kind, title, sport, start_date, end_date) values
  ('55555555-0000-0000-0000-000000000001', 'training', 'T', 'Torball', now(), now()),
  ('55555555-0000-0000-0000-000000000002', 'event', 'Kurs am See', 'Langlaufkurs', now(), now()),
  ('55555555-0000-0000-0000-000000000003', 'event', 'Irgendwas', 'Unbekannt', now(), now());
select is((select event_type from public.events where id = '55555555-0000-0000-0000-000000000001'),
  'Training', 'old-build training gets event_type Training');
select is((select event_type || '|' || sport from public.events where id = '55555555-0000-0000-0000-000000000002'),
  'Langlaufkurs|', 'old-build plain event: type moves from sport to event_type');
select is((select event_type || '|' || sport from public.events where id = '55555555-0000-0000-0000-000000000003'),
  '|Unbekannt', 'unknown text stays in sport');

insert into public.teams (id, name, sport) values ('44444444-0000-0000-0000-000000000001', 'Torball A', 'Torball');

-- coach: reads, cannot change
select pg_temp.act_as('66666666-0000-0000-0000-000000000002');
select ok((select count(*) from public.sports) >= 9, 'coach reads sports');
select ok((select count(*) from public.event_types) >= 9, 'coach reads event types');
select throws_ok($$insert into public.sports (name) values ('Tischtennis')$$,
  '42501', null, 'coach cannot add a sport');
select throws_ok($$select public.rename_sport((select id from public.sports where name = 'Torball'), 'X')$$,
  '42501', null, 'coach cannot rename a sport');
update public.sports set is_active = false where name = 'Torball';
select ok((select is_active from public.sports where name = 'Torball'), 'coach cannot deactivate a sport');

-- pending account reads nothing
select pg_temp.act_as('66666666-0000-0000-0000-000000000003', false);
select is((select count(*)::int from public.sports), 0, 'pending account reads no sports');

-- admin manages both lists
select pg_temp.act_as('66666666-0000-0000-0000-000000000001');
select lives_ok($$insert into public.sports (name, sort_order) values ('Tischtennis', 200)$$, 'admin adds a sport');
select throws_ok($$insert into public.sports (name) values ('torball')$$,
  '23505', null, 'names are unique, ignoring case');
select lives_ok($$insert into public.event_types (name, behavior) values ('Trainingslager', 'training')$$,
  'admin adds an event type with training behaviour');
select lives_ok($$update public.sports set is_active = false where name = 'Tischtennis'$$, 'admin deactivates a sport');

select lives_ok($$select public.rename_sport((select id from public.sports where name = 'Torball'), ' Torball (Halle) ')$$,
  'admin renames a sport');
reset role;
select is((select sport from public.events where id = '55555555-0000-0000-0000-000000000001'), 'Torball (Halle)',
  'rename reaches the events');
select is((select sport from public.teams where id = '44444444-0000-0000-0000-000000000001'), 'Torball (Halle)',
  'rename reaches the teams');

select pg_temp.act_as('66666666-0000-0000-0000-000000000001');
select lives_ok($$select public.rename_event_type((select id from public.event_types where name = 'Langlaufkurs'), 'Langlauf-Kurs')$$,
  'admin renames an event type');
select throws_ok($$update public.event_types set behavior = 'tournament' where name = 'Training'$$,
  '23514', null, 'behaviour of a type in use is fixed');

reset role;
select * from finish();
rollback;
