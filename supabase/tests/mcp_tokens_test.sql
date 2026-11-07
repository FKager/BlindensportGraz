-- Run with: supabase test db
-- Personal MCP tokens (20261107000002_mcp_tokens).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(11);

create function pg_temp.mk_user(uid uuid, mail text) returns void language sql as $$
  insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
          mail, '{"first_name":"T","last_name":"User"}', now(), now());
$$;

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  set local role authenticated;
end;
$$;

select pg_temp.mk_user('a1000000-0000-0000-0000-000000000001', 'a@token.test');
select pg_temp.mk_user('a1000000-0000-0000-0000-000000000002', 'b@token.test');

select pg_temp.act_as('a1000000-0000-0000-0000-000000000001');
select lives_ok($$insert into public.mcp_tokens (user_id, label, token_hash, sealed_session, expires_at)
  values ('a1000000-0000-0000-0000-000000000001', 'Laptop', 'hash-a', 'sealed-a', now() + interval '1 day')$$,
  'an account creates its own token');
select throws_ok($$insert into public.mcp_tokens (user_id, label, token_hash, sealed_session, expires_at)
  values ('a1000000-0000-0000-0000-000000000002', 'X', 'hash-x', 's', now() + interval '1 day')$$,
  '42501', null, 'not for someone else');
select is((select label from public.mcp_tokens), 'Laptop', 'the owner sees the list');
select throws_ok($$select sealed_session from public.mcp_tokens$$, '42501', null, 'not the sealed session');
select throws_ok($$select token_hash from public.mcp_tokens$$, '42501', null, 'not the hash');

select pg_temp.act_as('a1000000-0000-0000-0000-000000000002');
select is((select count(*)::int from public.mcp_tokens), 0, 'others see nothing');
delete from public.mcp_tokens;

reset role;
select is((select count(*)::int from public.mcp_tokens), 1, 'others cannot delete it');

set local role anon;
select is((select sealed_session from public.mcp_token_session('hash-a')), 'sealed-a', 'the hash finds the session');
select throws_ok($$select id from public.mcp_tokens$$, '42501', null, 'anon cannot read the table');
select public.mcp_token_update('hash-a', 'sealed-b');
reset role;
select is((select sealed_session from public.mcp_tokens), 'sealed-b', 'a refreshed session is saved');

update public.mcp_tokens set expires_at = now() - interval '1 minute';
set local role anon;
select is((select count(*)::int from public.mcp_token_session('hash-a')), 0, 'an expired token finds nothing');

select * from finish();
rollback;
