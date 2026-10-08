-- Name-only directory of accounts for approved users (participant lists,
-- team rosters link to accounts by id). No email, no tokens.
create function public.account_directory()
returns table (id uuid, first_name text, last_name text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.first_name, p.last_name, p.created_at
    from public.profiles p
   where exists (select 1 from public.account_approvals a where a.user_id = (select auth.uid()))
      or exists (select 1 from public.user_roles r where r.user_id = (select auth.uid())
                                                     and r.role in ('coach', 'admin', 'root'));
$$;
revoke execute on function public.account_directory from anon, public;
grant execute on function public.account_directory to authenticated;
