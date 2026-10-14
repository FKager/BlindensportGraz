-- Run with: supabase test db
-- Account administration hardening (20261014000003_account_admin_hardening):
-- root targets, audit log, calendar link, blocked callers, last-root guard.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(26);

-- ------------------------------------------------------------- fixtures ---
create function pg_temp.mk_user(uid uuid, mail text, first text default 'T', last text default 'User')
returns void language sql as $$
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
          mail, json_build_object('first_name', first, 'last_name', last), now(), now());
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

-- Root 1 and root 2, an admin, a member, an account to delete.
select pg_temp.mk_user('aa000000-0000-0000-0000-000000000001', 'root1@hard.test', 'Rita', 'Root');
select pg_temp.mk_user('aa000000-0000-0000-0000-000000000002', 'root2@hard.test', 'Rolf', 'Root');
select pg_temp.mk_user('aa000000-0000-0000-0000-000000000003', 'admin@hard.test', 'Anna', 'Admin');
select pg_temp.mk_user('aa000000-0000-0000-0000-000000000004', 'member@hard.test', 'Max', 'Member');
select pg_temp.mk_user('aa000000-0000-0000-0000-000000000005', 'gone@hard.test', 'Gerd', 'Gone');
insert into public.user_roles (user_id, role) values
  ('aa000000-0000-0000-0000-000000000001', 'root'),
  ('aa000000-0000-0000-0000-000000000002', 'root'),
  ('aa000000-0000-0000-0000-000000000003', 'admin'),
  ('aa000000-0000-0000-0000-000000000004', 'member'),
  ('aa000000-0000-0000-0000-000000000005', 'member');
-- The seed's local root would otherwise count as another root.
delete from public.user_roles where user_id = '00000000-0000-0000-0000-0000000000aa';
insert into public.members (id, first_name, last_name) values
  ('bb000000-0000-0000-0000-000000000004', 'Max', 'Member');
insert into public.account_approvals (user_id, member_id) values
  ('aa000000-0000-0000-0000-000000000004', 'bb000000-0000-0000-0000-000000000004');
insert into auth.refresh_tokens (instance_id, token, user_id, revoked, created_at, updated_at) values
  ('00000000-0000-0000-0000-000000000000', 'legacy-token', 'aa000000-0000-0000-0000-000000000004', false, now(), now());
insert into public.activation_codes (user_id, code_hash) values
  ('aa000000-0000-0000-0000-000000000004', encode(extensions.digest('ABCDEFGH', 'sha256'), 'hex'));
create temp table old_token on commit drop as
  select calendar_token from public.profiles where id = 'aa000000-0000-0000-0000-000000000004';
grant select on old_token to authenticated;

-- ----------------------------------------------------------- root targets ---
select pg_temp.act_as('aa000000-0000-0000-0000-000000000001');
select throws_ok($$ select public.set_account_blocked('aa000000-0000-0000-0000-000000000002', true) $$,
  '42501', 'demote the root account first', 'another root cannot be blocked');
select throws_ok($$ select public.delete_account('aa000000-0000-0000-0000-000000000002') $$,
  '42501', 'demote the root account first', 'another root cannot be deleted');
select throws_ok($$ select public.delete_account('aa000000-0000-0000-0000-0000000000ff') $$,
  'P0002', null, 'unknown account is reported');

-- ------------------------------------------------------------ block member ---
select lives_ok($$ select public.set_account_blocked('aa000000-0000-0000-0000-000000000004', true) $$,
  'root blocks the member');
reset role;
select is((select count(*)::int from auth.refresh_tokens where user_id = 'aa000000-0000-0000-0000-000000000004'), 0,
  'legacy refresh tokens are removed');
select isnt((select calendar_token from public.profiles where id = 'aa000000-0000-0000-0000-000000000004'),
  (select calendar_token from old_token), 'the calendar link is replaced');
select results_eq(
  $$ select action, target_email, target_name, actor from public.account_admin_log order by id $$,
  $$ values ('block'::text, 'member@hard.test'::text, 'Max Member'::text,
             'aa000000-0000-0000-0000-000000000001'::uuid) $$,
  'the block is logged with a snapshot and the actor');
select results_eq($$ select * from public.unblocked_user_ids(array[
    'aa000000-0000-0000-0000-000000000003', 'aa000000-0000-0000-0000-000000000004']::uuid[]) $$,
  $$ values ('aa000000-0000-0000-0000-000000000003'::uuid) $$,
  'unblocked_user_ids drops the blocked account');

-- ----------------------------------------- the blocked member's live token ---
select pg_temp.act_as('aa000000-0000-0000-0000-000000000004');
select throws_ok($$ select public.register_device_token('tok-blocked', 'sandbox') $$,
  '42501', null, 'a blocked account cannot register a device token');
select throws_ok($$ select public.redeem_activation_code('ABCD-EFGH') $$,
  '42501', null, 'a blocked account cannot redeem a code');
select is(public.rotate_calendar_token(), null, 'a blocked account gets no new calendar link');
update public.profiles set first_name = 'Hacked' where id = 'aa000000-0000-0000-0000-000000000004';
reset role;
select is((select first_name from public.profiles where id = 'aa000000-0000-0000-0000-000000000004'), 'Max',
  'a blocked account cannot rename itself');
select pg_temp.act_as('aa000000-0000-0000-0000-000000000004');
select throws_ok($$ select public.unblocked_user_ids(array['aa000000-0000-0000-0000-000000000004'::uuid]) $$,
  '42501', null, 'unblocked_user_ids is service-role only');
select is((select count(*)::int from public.account_admin_log), 0, 'a member cannot read the log');

-- ------------------------------------------------------------ the log ---
select pg_temp.act_as('aa000000-0000-0000-0000-000000000003');
select is((select count(*)::int from public.account_admin_log), 1, 'an admin (rolelog.read) reads the log');
select throws_ok($$ insert into public.account_admin_log (action, target) values ('block', gen_random_uuid()) $$,
  '42501', null, 'nobody writes the log directly');

-- --------------------------------------------------------- unblock ---
select pg_temp.act_as('aa000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.set_account_blocked('aa000000-0000-0000-0000-000000000004', false) $$,
  'root unblocks the member');
select pg_temp.act_as('aa000000-0000-0000-0000-000000000004');
select ok(public.is_approved(), 'after unblocking the account is approved again');
select lives_ok($$ select public.register_device_token('tok-back', 'sandbox') $$,
  'and can register its phone again');

-- ------------------------------------------------- blocked admin caller ---
reset role;
update auth.users set banned_until = now() + interval '1 day' where id = 'aa000000-0000-0000-0000-000000000003';
select pg_temp.act_as('aa000000-0000-0000-0000-000000000003');
select ok(not public.has_permission('users.approve'), 'a blocked admin loses its permissions at once');
select throws_ok($$ select public.approve_account('aa000000-0000-0000-0000-000000000005',
                                                 'bb000000-0000-0000-0000-000000000004') $$,
  '42501', null, 'a blocked admin cannot approve accounts');
reset role;
update auth.users set banned_until = null where id = 'aa000000-0000-0000-0000-000000000003';

-- --------------------------------------------------------- delete ---
select pg_temp.act_as('aa000000-0000-0000-0000-000000000001');
select lives_ok($$ select public.delete_account('aa000000-0000-0000-0000-000000000005') $$,
  'root deletes an account');
reset role;
select results_eq(
  $$ select action, target_email, target_name from public.account_admin_log
      where target = 'aa000000-0000-0000-0000-000000000005' $$,
  $$ values ('delete'::text, 'gone@hard.test'::text, 'Gerd Gone'::text) $$,
  'the deletion log keeps email and name');

-- ---------------------------------------------------- last-root guard ---
-- Root 2 blocked outside the app (service role / dashboard).
update auth.users set banned_until = now() + interval '1 day' where id = 'aa000000-0000-0000-0000-000000000002';
select throws_ok($$ delete from public.user_roles where user_id = 'aa000000-0000-0000-0000-000000000001' $$,
  'P0001', 'cannot remove the last root account', 'a blocked root does not count as a remaining root');
select throws_ok($$ delete from auth.users where id = 'aa000000-0000-0000-0000-000000000001' $$,
  'P0001', 'cannot remove the last root account', 'nor does it let the last usable root delete itself');
update auth.users set banned_until = null where id = 'aa000000-0000-0000-0000-000000000002';
select lives_ok($$ delete from public.user_roles where user_id = 'aa000000-0000-0000-0000-000000000001' $$,
  'with an unblocked second root the role can go');

select * from finish();
rollback;
