-- Run with: supabase test db
-- Vereinsfunktionen (20261107000004_club_functions).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(15);

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
    json_build_object('sub', uid, 'role', 'authenticated', 'user_role', r, 'approved', a or r in ('admin','root'))::text, true);
  set local role authenticated;
end;
$$;

select pg_temp.mk_user('b1000000-0000-0000-0000-000000000001', 'admin@cf.test');
select pg_temp.mk_user('b1000000-0000-0000-0000-000000000002', 'coach@cf.test');
insert into public.user_roles (user_id, role) values
  ('b1000000-0000-0000-0000-000000000001', 'admin'),
  ('b1000000-0000-0000-0000-000000000002', 'coach');
insert into public.members (id, first_name, last_name, status) values
  ('b2000000-0000-0000-0000-000000000001', 'Anna', 'Eins', 'active'),
  ('b2000000-0000-0000-0000-000000000002', 'Bert', 'Zwei', 'delete');

select pg_temp.act_as('b1000000-0000-0000-0000-000000000001');
select lives_ok($$select public.set_club_function('obmann', 'b2000000-0000-0000-0000-000000000001')$$, 'admin assigns');
select lives_ok($$select public.set_club_function('kassier', 'b2000000-0000-0000-0000-000000000001')$$, 'one member, two functions');
select is((select count(*)::int from public.club_functions where member_id = 'b2000000-0000-0000-0000-000000000001'), 2, 'both held');
select lives_ok($$select public.set_club_function('obmann', 'b2000000-0000-0000-0000-000000000002')$$, 'assigning replaces');
select is((select member_name from public.club_functions where function_key = 'obmann'), 'Bert Zwei', 'one holder');
select lives_ok($$select public.set_club_function('obmann', 'b2000000-0000-0000-0000-000000000002')$$, 'same holder again');
select is((select count(*)::int from public.club_function_log where function_key = 'obmann'), 2, 'no log entry when nothing changed');
select is((select old_name || ' > ' || new_name from public.club_function_log where function_key = 'obmann' order by id desc limit 1),
          'Anna Eins > Bert Zwei', 'the log names both');
select is((select changed_by from public.club_function_log where function_key = 'obmann' order by id desc limit 1),
          'b1000000-0000-0000-0000-000000000001'::uuid, 'and who did it');
select lives_ok($$select public.set_club_function('kassier', null)$$, 'vacating works');
select throws_ok($$select public.set_club_function('praesident', 'b2000000-0000-0000-0000-000000000001')$$,
  '22023', null, 'unknown function refused');
select throws_ok($$insert into public.club_function_log (function_key) values ('obmann')$$, '42501', null, 'the log cannot be written');

select pg_temp.act_as('b1000000-0000-0000-0000-000000000002');
select throws_ok($$select public.set_club_function('obmann', 'b2000000-0000-0000-0000-000000000001')$$,
  '42501', 'not allowed', 'a coach cannot assign');

reset role;
delete from public.members where id = 'b2000000-0000-0000-0000-000000000002';
select is((select count(*)::int from public.club_functions where function_key = 'obmann'), 0, 'a deleted member leaves the function vacant');
select is((select old_name from public.club_function_log where function_key = 'obmann' order by id desc limit 1),
          'Bert Zwei', 'and the log still names them');

select * from finish();
rollback;
