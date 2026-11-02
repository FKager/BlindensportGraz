-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(14);

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

-- admin, applicant (own entry 0002), other member (entry 0003, already GVSC)
select pg_temp.mk_user('55555555-0000-0000-0000-000000000001', 'a@ga.test');
select pg_temp.mk_user('55555555-0000-0000-0000-000000000002', 'm@ga.test');
select pg_temp.mk_user('55555555-0000-0000-0000-000000000003', 'o@ga.test');
insert into public.user_roles (user_id, role) values
  ('55555555-0000-0000-0000-000000000001', 'admin'),
  ('55555555-0000-0000-0000-000000000002', 'member'),
  ('55555555-0000-0000-0000-000000000003', 'member');
insert into public.members (id, first_name, last_name, member_of_gvsc) values
  ('66666666-0000-0000-0000-000000000002', 'Anna', 'Antrag', false),
  ('66666666-0000-0000-0000-000000000003', 'Otto', 'Other', true),
  ('66666666-0000-0000-0000-000000000004', 'Kein', 'Konto', false);
insert into public.account_approvals (user_id, member_id) values
  ('55555555-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000002'),
  ('55555555-0000-0000-0000-000000000003', '66666666-0000-0000-0000-000000000003');

-- ------------------------------------------------ mark_gvsc_application
select pg_temp.act_as('55555555-0000-0000-0000-000000000003');
select throws_ok($$select public.mark_gvsc_application('66666666-0000-0000-0000-000000000002')$$,
  '42501', null, 'a member cannot apply for someone else''s entry');
select throws_ok($$select public.mark_gvsc_application('66666666-0000-0000-0000-000000000003')$$,
  '22023', null, 'an existing GVSC member cannot apply again');

select pg_temp.act_as('55555555-0000-0000-0000-000000000002');
select is(public.mark_gvsc_application('66666666-0000-0000-0000-000000000002'),
  '55555555-0000-0000-0000-000000000002'::uuid, 'member applies for own entry; returns the linked account');
select throws_ok($$select public.mark_gvsc_application('66666666-0000-0000-0000-000000000002')$$,
  '22023', null, 'a second mail within 5 minutes is refused');

reset role;
select isnt((select gvsc_applied_at from public.members where id = '66666666-0000-0000-0000-000000000002'),
  null, 'applied date is set');

select pg_temp.act_as('55555555-0000-0000-0000-000000000001');
select is(public.mark_gvsc_application('66666666-0000-0000-0000-000000000004'),
  null::uuid, 'admin applies for an entry without account; no linked account');
select throws_ok($$select public.mark_gvsc_application('66666666-0000-0000-0000-00000000ffff')$$,
  'P0002', null, 'unknown entry');

-- ----------------------------------------------------- new private fields
select pg_temp.act_as('55555555-0000-0000-0000-000000000002');
select lives_ok($$insert into public.member_private_requests (member_id, disability_type, consent_photos)
                  values ('66666666-0000-0000-0000-000000000002', 'blind', true)$$,
  'member proposes disability data and consent');
select pg_temp.act_as('55555555-0000-0000-0000-000000000001');
select lives_ok($$select public.apply_member_private_request('66666666-0000-0000-0000-000000000002')$$,
  'admin applies the proposal');
reset role;
select is((select disability_type || '/' || consent_photos::text from public.member_private
            where member_id = '66666666-0000-0000-0000-000000000002'),
  'blind/true', 'disability and consent fields are copied');
select throws_ok($$insert into public.member_contacts (id, membership_type) values ('66666666-0000-0000-0000-000000000002', 'vip')$$,
  '23514', null, 'membership_type only allows active/supporting');

-- ------------------------------------------------------- profile photos
select pg_temp.act_as('55555555-0000-0000-0000-000000000002');
select lives_ok($$insert into storage.objects (bucket_id, name, owner_id)
                  values ('profile-photos', '55555555-0000-0000-0000-000000000002.jpg', '55555555-0000-0000-0000-000000000002')$$,
  'account uploads its own photo');
select throws_ok($$insert into storage.objects (bucket_id, name, owner_id)
                   values ('profile-photos', '55555555-0000-0000-0000-000000000003.jpg', '55555555-0000-0000-0000-000000000002')$$,
  '42501', null, 'account cannot upload someone else''s photo');
select pg_temp.act_as('55555555-0000-0000-0000-000000000003');
select is((select count(*)::int from storage.objects where bucket_id = 'profile-photos'), 0,
  'other members cannot see the photo');

select * from finish();
rollback;
