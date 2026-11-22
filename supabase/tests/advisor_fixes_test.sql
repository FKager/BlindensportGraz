-- Advisor fixes (20261122000002). Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

select ok((select proconfig::text from pg_proc where oid = 'public.custom_access_token_hook(jsonb)'::regprocedure)
            like '%search_path=%', 'the access-token hook has a fixed search_path');
select ok(not has_function_privilege('authenticated', 'public.log_deletion()', 'execute'),
  'signed-in users cannot call a trigger function');
select ok(not has_function_privilege('anon', 'public.clear_deletion()', 'execute'),
  'visitors cannot call a trigger function');
select is((select count(*)::int from pg_indexes where schemaname = 'public' and indexname in
  ('team_memberships_member', 'member_change_requests_member', 'expense_receipts_tournament',
   'member_private_requests_user')), 4, 'the four lookup indexes exist');

-- Triggers still fire for a signed-in admin (EXECUTE isn't checked when a trigger fires).
insert into auth.users (instance_id, id, aud, role, email, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '69696969-0000-0000-0000-000000000001', 'authenticated',
        'authenticated', 'admin@advisor.test', now(), now()),
       ('00000000-0000-0000-0000-000000000000', '69696969-0000-0000-0000-000000000002', 'authenticated',
        'authenticated', 'neu@advisor.test', now(), now());
insert into public.user_roles (user_id, role) values ('69696969-0000-0000-0000-000000000001', 'admin');
select set_config('request.jwt.claims', json_build_object('sub', '69696969-0000-0000-0000-000000000001',
  'role', 'authenticated', 'user_role', 'admin', 'approved', true)::text, true);
set local role authenticated;

select lives_ok($$insert into public.teams (id, name, sport) values ('49494949-0000-0000-0000-000000000001', 'Probe', 'Torball')$$,
  'an admin creates a team');
select is((select updated_by::text from public.teams where id = '49494949-0000-0000-0000-000000000001'),
  '69696969-0000-0000-0000-000000000001', 'touch_row still stamps updated_by');
select lives_ok($$delete from public.teams where id = '49494949-0000-0000-0000-000000000001'$$, 'and deletes it');
select ok((select count(*) from public.deletions where row_id = '49494949-0000-0000-0000-000000000001') = 1,
  'log_deletion still records the deletion');
select matches(public.create_activation_code('69696969-0000-0000-0000-000000000002'), '^[A-Z2-9]{4}-[A-Z2-9]{4}$',
  'create_activation_code still makes a code');

reset role;
select * from finish();
rollback;
