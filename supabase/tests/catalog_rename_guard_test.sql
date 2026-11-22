-- Names of sports and event types change only through the rename functions
-- (20261122000001). Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(7);

insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '68686868-0000-0000-0000-000000000001', 'authenticated',
        'authenticated', 'admin@guard.test', now(), now());
insert into public.user_roles (user_id, role) values ('68686868-0000-0000-0000-000000000001', 'admin');
insert into public.events (id, kind, title, sport, start_date, end_date)
values ('58585858-0000-0000-0000-000000000001', 'training', 'T', 'Goalball', now(), now());

select set_config('request.jwt.claims', json_build_object('sub', '68686868-0000-0000-0000-000000000001',
  'role', 'authenticated', 'user_role', 'admin', 'approved', true)::text, true);
set local role authenticated;

select throws_ok($$update public.sports set name = 'Goalball (neu)' where name = 'Goalball'$$,
  '42501', null, 'a sport cannot be renamed by a direct update');
select throws_ok($$update public.event_types set name = 'Kurse' where name = 'Kurs'$$,
  '42501', null, 'an event type cannot be renamed by a direct update');
select lives_ok($$update public.sports set is_active = false, sort_order = 5 where name = 'Goalball'$$,
  'other columns still change directly');
select lives_ok($$select public.rename_sport((select id from public.sports where name = 'Goalball'), 'Goalball (neu)')$$,
  'rename_sport still renames');
select is((select sport from public.events where id = '58585858-0000-0000-0000-000000000001'), 'Goalball (neu)',
  'and the events follow');
select lives_ok($$select public.rename_event_type((select id from public.event_types where name = 'Kurs'), 'Kurse')$$,
  'rename_event_type still renames');
select is(coalesce(current_setting('bsg.catalog_rename', true), ''), '',
  'the functions leave no rename permission behind in the transaction');

reset role;
select * from finish();
rollback;
