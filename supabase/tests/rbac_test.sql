-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(37);

-- ------------------------------------------------------------- fixtures ---
-- Users are inserted as postgres; the auth trigger creates their profiles.
create function pg_temp.mk_user(uid uuid, mail text) returns void language sql as $$
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
          mail, '{"first_name":"T","last_name":"User"}', now(), now());
$$;

-- Act as `uid`, with claims shaped like the access-token hook's output.
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

select pg_temp.mk_user('11111111-0000-0000-0000-000000000001', 'root@t.test');
select pg_temp.mk_user('11111111-0000-0000-0000-000000000002', 'admin@t.test');
select pg_temp.mk_user('11111111-0000-0000-0000-000000000003', 'coach@t.test');
select pg_temp.mk_user('11111111-0000-0000-0000-000000000004', 'member@t.test');
select pg_temp.mk_user('11111111-0000-0000-0000-000000000005', 'pending@t.test');
insert into public.user_roles (user_id, role) values
  ('11111111-0000-0000-0000-000000000001', 'root'),
  ('11111111-0000-0000-0000-000000000002', 'admin'),
  ('11111111-0000-0000-0000-000000000003', 'coach'),
  ('11111111-0000-0000-0000-000000000004', 'member');
-- The seed's local root would otherwise count as a second root.
delete from public.user_roles where user_id = '00000000-0000-0000-0000-0000000000aa';
insert into public.account_approvals (user_id, member_id) values
  ('11111111-0000-0000-0000-000000000004', '22222222-0000-0000-0000-000000000004');
insert into public.member_private (member_id, svnr, iban) values
  ('22222222-0000-0000-0000-000000000004', '1234010180', 'AT611904300234573201');

-- ------------------------------------------------------- profile trigger ---
select is((select count(*)::int from public.profiles where email like '%@t.test'), 5,
  'auth trigger creates a profile per user');
select is((select first_name from public.profiles where email = 'root@t.test'), 'T',
  'profile takes first_name from user metadata');

-- ---------------------------------------------------------------- hook ---
select is(
  public.custom_access_token_hook(jsonb_build_object(
    'user_id', '11111111-0000-0000-0000-000000000004', 'claims', '{}'::jsonb)) -> 'claims' ->> 'user_role',
  'member', 'hook adds user_role');
select is(
  (public.custom_access_token_hook(jsonb_build_object(
    'user_id', '11111111-0000-0000-0000-000000000004', 'claims', '{}'::jsonb)) -> 'claims' ->> 'approved')::boolean,
  true, 'hook: approved member');
select is(
  (public.custom_access_token_hook(jsonb_build_object(
    'user_id', '11111111-0000-0000-0000-000000000005', 'claims', '{}'::jsonb)) -> 'claims' ->> 'approved')::boolean,
  false, 'hook: pending user is not approved');
select ok(
  public.custom_access_token_hook(jsonb_build_object(
    'user_id', '11111111-0000-0000-0000-000000000005', 'claims', '{}'::jsonb)) -> 'claims' is not null,
  'hook keeps claims for users without role');
select is(
  (public.custom_access_token_hook(jsonb_build_object(
    'user_id', '11111111-0000-0000-0000-000000000002', 'claims', '{}'::jsonb)) -> 'claims' ->> 'approved')::boolean,
  true, 'hook: admin counts as approved');

-- ---------------------------------------------------------------- anon ---
set local role anon;
select throws_ok('select * from public.profiles', '42501', null, 'anon cannot read profiles');
select throws_ok('select * from public.member_private', '42501', null, 'anon cannot read member_private');
select throws_ok($$select public.set_user_role('11111111-0000-0000-0000-000000000005', 'admin')$$,
  '42501', null, 'anon cannot call set_user_role');

-- ------------------------------------------------------------- pending ---
select pg_temp.act_as('11111111-0000-0000-0000-000000000005');
select is((select count(*)::int from public.profiles), 1, 'pending sees only own profile');
select is((select count(*)::int from public.member_private), 0, 'pending sees no member_private');
select throws_ok($$select public.approve_account('11111111-0000-0000-0000-000000000005', '22222222-0000-0000-0000-000000000009')$$,
  '42501', null, 'pending cannot approve itself');
select throws_ok($$insert into public.user_roles (user_id, role) values ('11111111-0000-0000-0000-000000000005', 'root')$$,
  '42501', null, 'pending cannot insert a role row');
select is(public.redeem_activation_code('AAAA-BBBB'), false, 'unknown activation code is rejected');

-- -------------------------------------------------------------- member ---
select pg_temp.act_as('11111111-0000-0000-0000-000000000004');
select is((select count(*)::int from public.member_private), 1, 'approved member sees only own member_private row');
select is((select count(*)::int from public.user_roles), 1, 'member sees only own role');
select throws_ok($$update public.profiles set is_gvsc_member = true where id = '11111111-0000-0000-0000-000000000004'$$,
  '42501', null, 'member cannot update privileged profile columns');
update public.profiles set first_name = 'Renamed' where id = '11111111-0000-0000-0000-000000000004';
select is((select first_name from public.profiles where id = '11111111-0000-0000-0000-000000000004'),
  'Renamed', 'member can rename own profile');
update public.profiles set first_name = 'Hacked' where id = '11111111-0000-0000-0000-000000000002';
select pg_temp.act_as('11111111-0000-0000-0000-000000000002');
select is((select first_name from public.profiles where id = '11111111-0000-0000-0000-000000000002'),
  'T', 'member cannot rename someone else');

-- --------------------------------------------------------------- coach ---
select pg_temp.act_as('11111111-0000-0000-0000-000000000003');
select is((select count(*)::int from public.member_private), 0, 'coach sees no member_private');
select throws_ok($$select public.create_activation_code('11111111-0000-0000-0000-000000000005')$$,
  '42501', null, 'coach cannot create activation codes');

-- --------------------------------------------------------------- admin ---
select pg_temp.act_as('11111111-0000-0000-0000-000000000002');
select is((select count(*)::int from public.member_private), 1, 'admin reads member_private');
select is((select count(*)::int from public.profiles where email like '%@t.test'), 5, 'admin reads all profiles');
select ok((select count(*) from public.role_change_log) > 0, 'admin can read role_change_log');
select throws_ok($$select public.set_user_role('11111111-0000-0000-0000-000000000003', 'admin')$$,
  '42501', null, 'admin cannot assign roles');
select throws_ok('select code_hash from public.activation_codes', '42501', null,
  'code_hash is not readable');

-- Activation code round trip: admin issues, pending user redeems.
create temp table issued (code text);
grant all on issued to authenticated;
insert into issued select public.create_activation_code(
  '11111111-0000-0000-0000-000000000005', '22222222-0000-0000-0000-000000000005');
select pg_temp.act_as('11111111-0000-0000-0000-000000000004');
select is(public.redeem_activation_code((select code from issued)), false,
  'a code only works for the user it was issued to');
select pg_temp.act_as('11111111-0000-0000-0000-000000000005');
select is(public.redeem_activation_code(lower((select code from issued))), true,
  'issued code redeems (case-insensitive)');
select is(public.redeem_activation_code((select code from issued)), false,
  'a code redeems only once');
reset role;
select ok(exists (select 1 from public.account_approvals where user_id = '11111111-0000-0000-0000-000000000005'),
  'redeeming a code with a roster entry approves the account');

-- ---------------------------------------------------------------- root ---
select pg_temp.act_as('11111111-0000-0000-0000-000000000001');
select lives_ok($$select public.set_user_role('11111111-0000-0000-0000-000000000003', 'admin')$$,
  'root can assign roles');
select throws_ok($$select public.set_user_role('11111111-0000-0000-0000-000000000001', 'member')$$,
  '42501', null, 'root cannot change own role');
reset role;
select is((select new_role::text from public.role_change_log
            where user_id = '11111111-0000-0000-0000-000000000003' order by id desc limit 1),
  'admin', 'role change is logged by trigger');
select is((select changed_by from public.role_change_log
            where user_id = '11111111-0000-0000-0000-000000000003' order by id desc limit 1),
  '11111111-0000-0000-0000-000000000001'::uuid, 'log records who changed the role');

-- ----------------------------------------------------- last-root guard ---
select throws_ok($$delete from public.user_roles where user_id = '11111111-0000-0000-0000-000000000001'$$,
  'P0001', 'cannot remove the last root account', 'last root cannot be removed');
select throws_ok($$delete from auth.users where id = '11111111-0000-0000-0000-000000000001'$$,
  'P0001', 'cannot remove the last root account', 'last root cannot be deleted via cascade');

select * from finish();
rollback;
