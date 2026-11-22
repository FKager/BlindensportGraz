-- Fixes from Supabase's database advisors (splinter) and plpgsql lint,
-- 2026-11-22. The CI step "Database advisors" (database-test.yml) fails on
-- any new warning that isn't listed in supabase/advisors-accepted.txt.

-- 1. The access-token hook was the only function without a fixed
--    search_path. Its body already names everything with its schema.
alter function public.custom_access_token_hook(jsonb) set search_path = '';

-- 2. Trigger functions can't be called usefully through /rest/v1/rpc (Postgres
--    refuses a direct call), but they shouldn't be callable at all. Firing a
--    trigger doesn't check EXECUTE, so the triggers keep working.
do $$
declare
  f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_catalog.pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.prorettype = 'trigger'::regtype
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
  end loop;
end;
$$;

-- 3. Lookup columns without an index (joins and RLS checks use them).
create index if not exists team_memberships_member on public.team_memberships (member_id);
create index if not exists member_change_requests_member on public.member_change_requests (member_id);
create index if not exists expense_receipts_tournament on public.expense_receipts (tournament_id);
create index if not exists member_private_requests_user on public.member_private_requests (user_id);

-- 4. create_activation_code declared a loop variable the FOR loop shadows.
create or replace function public.create_activation_code(target uuid, p_member_id uuid default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  bytes bytea := extensions.gen_random_bytes(8);
  raw text := '';
begin
  if not public.has_permission('users.approve') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  for i in 0..7 loop
    raw := raw || substr(alphabet, (get_byte(bytes, i) % length(alphabet)) + 1, 1);
  end loop;
  -- Only one open code per user.
  delete from public.activation_codes where user_id = target and used_at is null;
  insert into public.activation_codes (user_id, member_id, code_hash, created_by)
  values (target, p_member_id,
          encode(extensions.digest(raw, 'sha256'), 'hex'), auth.uid());
  return substr(raw, 1, 4) || '-' || substr(raw, 5, 4);
end;
$$;
