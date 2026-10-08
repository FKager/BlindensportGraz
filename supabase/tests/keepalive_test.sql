-- Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(2);
set local role anon;
select isnt(public.ping(), null, 'anon can call ping()');
select throws_ok('select * from public.profiles', '42501', null, 'ping grant opens nothing else for anon');
select * from finish();
rollback;
