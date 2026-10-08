-- Members see their own protected data (via their approval's roster entry)
-- and propose changes to it. Proposals replace the svnr/iban/date fields of
-- the CloudKit MemberChangeRequest, which must not carry them any more.

-- The caller's approved roster entry, or null.
create function public.my_member_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select member_id from public.account_approvals where user_id = (select auth.uid());
$$;
revoke execute on function public.my_member_id from anon, public;
grant execute on function public.my_member_id to authenticated;

create policy "member_private: read own"
  on public.member_private for select to authenticated
  using (member_id = (select public.my_member_id()));

-- --------------------------------------------------- change proposals ---
create table public.member_private_requests (
  member_id                uuid primary key,
  user_id                  uuid not null default auth.uid()
                             references auth.users (id) on delete cascade,
  svnr                     text not null default '',
  iban                     text not null default '',
  birth_date               date,
  last_medical_examination date,
  created_at               timestamptz not null default now()
);

alter table public.member_private_requests enable row level security;
revoke all on public.member_private_requests from anon, authenticated;
grant select, insert, update, delete on public.member_private_requests to authenticated;

create policy "member_private_requests: own proposal"
  on public.member_private_requests for all to authenticated
  using (user_id = (select auth.uid()) and member_id = (select public.my_member_id()))
  with check (user_id = (select auth.uid()) and member_id = (select public.my_member_id()));

create policy "member_private_requests: reviewers read"
  on public.member_private_requests for select to authenticated
  using ((select public.authorize('members.private.write')));

create policy "member_private_requests: reviewers delete"
  on public.member_private_requests for delete to authenticated
  using ((select public.authorize('members.private.write')));

-- Reviewer applies a proposal atomically.
create function public.apply_member_private_request(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  req public.member_private_requests;
begin
  if not public.has_permission('members.private.write') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into req from public.member_private_requests where member_id = p_member_id for update;
  if not found then
    raise exception 'no pending request' using errcode = 'P0002';
  end if;
  insert into public.member_private (member_id, svnr, iban, birth_date, last_medical_examination)
  values (req.member_id, req.svnr, req.iban, req.birth_date, req.last_medical_examination)
  on conflict (member_id) do update
    set svnr = excluded.svnr,
        iban = excluded.iban,
        birth_date = excluded.birth_date,
        last_medical_examination = excluded.last_medical_examination;
  delete from public.member_private_requests where member_id = p_member_id;
end;
$$;
revoke execute on function public.apply_member_private_request from anon, public;
grant execute on function public.apply_member_private_request to authenticated;
