-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(7);

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
    json_build_object('sub', uid, 'role', 'authenticated', 'user_role', r, 'approved', true)::text, true);
  set local role authenticated;
end;
$$;

-- admin, coach, member
select pg_temp.mk_user('77777777-0000-0000-0000-000000000001', 'a@ti.test');
select pg_temp.mk_user('77777777-0000-0000-0000-000000000002', 'c@ti.test');
select pg_temp.mk_user('77777777-0000-0000-0000-000000000003', 'm@ti.test');
insert into public.user_roles (user_id, role) values
  ('77777777-0000-0000-0000-000000000001', 'admin'),
  ('77777777-0000-0000-0000-000000000002', 'coach'),
  ('77777777-0000-0000-0000-000000000003', 'member');
insert into public.events (id, kind, title, sport, start_date, end_date)
  values ('88888888-0000-0000-0000-000000000001', 'tournament', 'Cup', 'Torball', now(), now());

select pg_temp.act_as('77777777-0000-0000-0000-000000000001');
select lives_ok($$insert into public.tournament_invitations (id, tournament_id, storage_path, file_name, content_type)
                  values ('99999999-0000-0000-0000-000000000001', '88888888-0000-0000-0000-000000000001',
                          '99999999-0000-0000-0000-000000000001.pdf', 'Einladung.pdf', 'application/pdf')$$,
  'admin uploads an invitation');
select is((select count(*)::int from public.tournament_invitations where id = '99999999-0000-0000-0000-000000000001'), 1, 'admin reads it');
select lives_ok($$insert into storage.objects (bucket_id, name, owner_id)
                  values ('tournament-invitations', '99999999-0000-0000-0000-000000000001.pdf',
                          '77777777-0000-0000-0000-000000000001')$$,
  'admin uploads the file');

select pg_temp.act_as('77777777-0000-0000-0000-000000000002');
select is((select count(*)::int from public.tournament_invitations), 0, 'coach cannot read invitations');
select throws_ok($$insert into public.tournament_invitations (id, tournament_id, storage_path)
                   values ('99999999-0000-0000-0000-000000000002', '88888888-0000-0000-0000-000000000001', 'x.pdf')$$,
  '42501', null, 'coach cannot upload');

select pg_temp.act_as('77777777-0000-0000-0000-000000000003');
select is((select count(*)::int from storage.objects where bucket_id = 'tournament-invitations'), 0,
  'member cannot see the file');

reset role;
delete from public.events where id = '88888888-0000-0000-0000-000000000001';
select is((select count(*)::int from public.tournament_invitations), 0, 'deleting the tournament removes its invitation');

select * from finish();
rollback;
