-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(13);

create function pg_temp.mk_user(uid uuid, mail text) returns void language sql as $$
  insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', mail, now(), now());
$$;

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
declare r text;
begin
  reset role;
  select role::text into r from public.user_roles where user_id = uid;
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated', 'user_role', r)::text, true);
  set local role authenticated;
end;
$$;

select pg_temp.mk_user('33333333-0000-0000-0000-000000000001', 'a@mp.test');
select pg_temp.mk_user('33333333-0000-0000-0000-000000000002', 'm@mp.test');
select pg_temp.mk_user('33333333-0000-0000-0000-000000000003', 'o@mp.test');
insert into public.user_roles (user_id, role) values
  ('33333333-0000-0000-0000-000000000001', 'admin'),
  ('33333333-0000-0000-0000-000000000002', 'member'),
  ('33333333-0000-0000-0000-000000000003', 'member');
insert into public.account_approvals (user_id, member_id) values
  ('33333333-0000-0000-0000-000000000002', '44444444-0000-0000-0000-000000000002'),
  ('33333333-0000-0000-0000-000000000003', '44444444-0000-0000-0000-000000000003');
insert into public.member_private (member_id, svnr) values
  ('44444444-0000-0000-0000-000000000002', 'mine'),
  ('44444444-0000-0000-0000-000000000003', 'other');

select pg_temp.act_as('33333333-0000-0000-0000-000000000002');
select is((select array_agg(svnr) from public.member_private), array['mine'],
  'member reads only own private row');
update public.member_private set svnr = 'x' where member_id = '44444444-0000-0000-0000-000000000002';
select is((select svnr from public.member_private where member_id = '44444444-0000-0000-0000-000000000002'),
  'mine', 'member cannot write private data directly (RLS filters the update)');
select lives_ok($$insert into public.member_private_requests (member_id, svnr) values ('44444444-0000-0000-0000-000000000002', 'proposed')$$,
  'member proposes a change for own entry');
select throws_ok($$insert into public.member_private_requests (member_id, svnr) values ('44444444-0000-0000-0000-000000000003', 'evil')$$,
  '42501', null, 'member cannot propose for someone else');
select throws_ok($$select public.apply_member_private_request('44444444-0000-0000-0000-000000000002')$$,
  '42501', null, 'member cannot apply proposals');

select pg_temp.act_as('33333333-0000-0000-0000-000000000003');
select ok((select count(*) from public.account_directory()) >= 3, 'approved member sees the name directory');
select is((select count(*)::int from public.member_private_requests), 0,
  'other members do not see the proposal');

select pg_temp.act_as('33333333-0000-0000-0000-000000000001');
select is((select count(*)::int from public.member_private_requests), 1, 'admin sees the proposal');
select lives_ok($$select public.apply_member_private_request('44444444-0000-0000-0000-000000000002')$$,
  'admin applies the proposal');
select is((select svnr from public.member_private where member_id = '44444444-0000-0000-0000-000000000002'),
  'proposed', 'applied value is stored and request removed');

reset role;
select pg_temp.mk_user('33333333-0000-0000-0000-000000000009', 'p@mp.test');
select pg_temp.act_as('33333333-0000-0000-0000-000000000009');
select is((select count(*)::int from public.account_directory()), 0, 'pending account sees no directory');

-- updated_by: the service role (clubmembersapi) may name the admin it acts
-- for; an app user always gets their own id, whatever they send.
reset role;
select set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
set local role service_role;
update public.member_private set updated_by = '33333333-0000-0000-0000-000000000001'
  where member_id = '44444444-0000-0000-0000-000000000003';
reset role;
select is((select updated_by from public.member_private where member_id = '44444444-0000-0000-0000-000000000003'),
  '33333333-0000-0000-0000-000000000001'::uuid, 'service role keeps the supplied updated_by');

select pg_temp.act_as('33333333-0000-0000-0000-000000000001');
update public.member_private set svnr = 'x', updated_by = '33333333-0000-0000-0000-000000000002'
  where member_id = '44444444-0000-0000-0000-000000000003';
reset role;
select is((select updated_by from public.member_private where member_id = '44444444-0000-0000-0000-000000000003'),
  '33333333-0000-0000-0000-000000000001'::uuid, 'an app user cannot set someone else as updated_by');
select * from finish();
rollback;
