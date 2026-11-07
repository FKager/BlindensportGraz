-- Run with: supabase test db
-- Member status and root-only deletion (20261107000001_member_status).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(13);

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

select pg_temp.mk_user('f0000000-0000-0000-0000-000000000001', 'root@status.test');
select pg_temp.mk_user('f0000000-0000-0000-0000-000000000002', 'admin@status.test');
insert into public.user_roles (user_id, role) values
  ('f0000000-0000-0000-0000-000000000001', 'root'),
  ('f0000000-0000-0000-0000-000000000002', 'admin');
insert into public.members (id, first_name, last_name) values
  ('f1000000-0000-0000-0000-000000000001', 'Anna', 'Muster');
insert into public.member_private (member_id, svnr) values
  ('f1000000-0000-0000-0000-000000000001', '1234');

select is((select status from public.members where id = 'f1000000-0000-0000-0000-000000000001'),
          'new', 'a new entry starts as new');
select throws_ok(
  $$update public.members set status = 'gone' where id = 'f1000000-0000-0000-0000-000000000001'$$,
  '23514', null, 'unknown status refused');

-- admin: flags, can't remove -------------------------------------------------
select pg_temp.act_as('f0000000-0000-0000-0000-000000000002');
select lives_ok(
  $$update public.members set status = 'active' where id = 'f1000000-0000-0000-0000-000000000001'$$,
  'admin sets active');
delete from public.members where id = 'f1000000-0000-0000-0000-000000000001';
select is((select count(*)::int from public.members where id = 'f1000000-0000-0000-0000-000000000001'),
          1, 'admin cannot delete the table row directly');
update public.members set status = 'delete' where id = 'f1000000-0000-0000-0000-000000000001';
select throws_ok(
  $$select public.delete_member('f1000000-0000-0000-0000-000000000001', 'Anna Muster')$$,
  '42501', 'not allowed', 'admin cannot call delete_member');

-- root: direct delete closed too --------------------------------------------
select pg_temp.act_as('f0000000-0000-0000-0000-000000000001');
delete from public.members where id = 'f1000000-0000-0000-0000-000000000001';
select is((select count(*)::int from public.members where id = 'f1000000-0000-0000-0000-000000000001'),
          1, 'root cannot delete the table row directly either');
update public.members set status = 'active' where id = 'f1000000-0000-0000-0000-000000000001';
select throws_ok(
  $$select public.delete_member('f1000000-0000-0000-0000-000000000001', 'Anna Muster')$$,
  '42501', 'member is not marked for deletion', 'an active entry cannot be deleted');
update public.members set status = 'delete' where id = 'f1000000-0000-0000-0000-000000000001';
select throws_ok(
  $$select public.delete_member('f1000000-0000-0000-0000-000000000001', 'Anna Mustermann')$$,
  '42501', 'confirmation does not match the member name', 'wrong name refused');
select throws_ok(
  $$select public.delete_member('f1000000-0000-0000-0000-000000000001', null)$$,
  '42501', 'confirmation does not match the member name', 'missing confirmation refused');
select throws_ok(
  $$select public.delete_member('f1000000-0000-0000-0000-00000000000f', 'Anna Muster')$$,
  'P0002', 'unknown member', 'unknown id refused');
select lives_ok(
  $$select public.delete_member('f1000000-0000-0000-0000-000000000001', '  anna   MUSTER ')$$,
  'root deletes with the name, spacing and case forgiven');

reset role;
select is((select count(*)::int from public.members where id = 'f1000000-0000-0000-0000-000000000001'),
          0, 'entry gone');
select is((select count(*)::int from public.member_private where member_id = 'f1000000-0000-0000-0000-000000000001'),
          0, 'protected row gone too');

select * from finish();
rollback;
