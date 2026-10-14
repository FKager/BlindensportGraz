-- Run with: supabase test db
-- Root blocks / unblocks / deletes accounts (20261014000002_account_admin).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(17);

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

select pg_temp.mk_user('e0000000-0000-0000-0000-000000000001', 'root@admin.test');
select pg_temp.mk_user('e0000000-0000-0000-0000-000000000002', 'admin@admin.test');
select pg_temp.mk_user('e0000000-0000-0000-0000-000000000003', 'member@admin.test');
select pg_temp.mk_user('e0000000-0000-0000-0000-000000000004', 'gone@admin.test');
insert into public.user_roles (user_id, role) values
  ('e0000000-0000-0000-0000-000000000001', 'root'),
  ('e0000000-0000-0000-0000-000000000002', 'admin'),
  ('e0000000-0000-0000-0000-000000000003', 'member'),
  ('e0000000-0000-0000-0000-000000000004', 'member');
insert into public.members (id, first_name, last_name) values
  ('f0000000-0000-0000-0000-000000000003', 'Mia', 'Member');
insert into public.account_approvals (user_id, member_id) values
  ('e0000000-0000-0000-0000-000000000003', 'f0000000-0000-0000-0000-000000000003');
insert into auth.sessions (id, user_id, created_at, updated_at) values
  ('a1000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-000000000003', now(), now());
insert into public.device_tokens (token, user_id, apns_env) values
  ('tok-member', 'e0000000-0000-0000-0000-000000000003', 'sandbox');

-- -------------------------------------------------------- permissions ---
select pg_temp.act_as('e0000000-0000-0000-0000-000000000002');
select throws_ok($$ select public.set_account_blocked('e0000000-0000-0000-0000-000000000003', true) $$,
  '42501', null, 'an admin cannot block');
select throws_ok($$ select public.delete_account('e0000000-0000-0000-0000-000000000003') $$,
  '42501', null, 'an admin cannot delete');
select throws_ok($$ select * from public.blocked_accounts() $$, '42501', null,
  'an admin cannot list blocks');

select pg_temp.act_as('e0000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.set_account_blocked('e0000000-0000-0000-0000-000000000001', true) $$,
  '42501', null, 'root cannot block themselves');
select throws_ok($$ select public.delete_account('e0000000-0000-0000-0000-000000000001') $$,
  '42501', null, 'root cannot delete themselves here');

-- ------------------------------------------------------------- block ---
select lives_ok($$ select public.set_account_blocked('e0000000-0000-0000-0000-000000000003', true) $$,
  'root blocks a member');
select results_eq($$ select user_id from public.blocked_accounts() $$,
  $$ values ('e0000000-0000-0000-0000-000000000003'::uuid) $$, 'the block is listed');
reset role;
select ok((select banned_until > now() + interval '50 years' from auth.users
            where id = 'e0000000-0000-0000-0000-000000000003'), 'banned_until is set');
select is((select count(*)::int from auth.sessions where user_id = 'e0000000-0000-0000-0000-000000000003'), 0,
  'sessions are ended');
select is((select count(*)::int from public.device_tokens where user_id = 'e0000000-0000-0000-0000-000000000003'), 0,
  'device tokens are removed');

-- The still-valid access token of the blocked account no longer works.
select pg_temp.act_as('e0000000-0000-0000-0000-000000000003');
select ok(not public.is_approved(), 'a blocked account is not approved');
select is((select count(*)::int from public.members), 0, 'a blocked account sees no roster');
select pg_temp.act_as('e0000000-0000-0000-0000-000000000002');
select ok(not public.is_blocked(), 'is_blocked only answers for the caller');

select pg_temp.act_as('e0000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.set_account_blocked('e0000000-0000-0000-0000-000000000003', false) $$,
  'root unblocks');
select is((select count(*)::int from public.blocked_accounts()), 0, 'no blocks left');

-- ------------------------------------------------------------ delete ---
select lives_ok($$ select public.delete_account('e0000000-0000-0000-0000-000000000004') $$,
  'root deletes an account');
reset role;
select is((select count(*)::int from public.profiles where id = 'e0000000-0000-0000-0000-000000000004'), 0,
  'its profile cascades');

select * from finish();
rollback;
