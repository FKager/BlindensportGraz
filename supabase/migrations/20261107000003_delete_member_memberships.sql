-- Removing a member now also removes their team entries, and with them (by
-- cascade) their attendance and PRAE amounts. The foreign key alone would only
-- blank the member, which left nameless entries on the team.
create or replace function public.delete_member(target uuid, confirm_name text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  entry public.members%rowtype;
  normalized text;
begin
  -- roles.assign is the root-only permission (role_permissions).
  if not public.has_permission('roles.assign') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into entry from public.members where id = target;
  if not found then
    raise exception 'unknown member' using errcode = 'P0002';
  end if;
  if entry.status <> 'delete' then
    raise exception 'member is not marked for deletion'
      using errcode = '42501', hint = 'member_not_marked';
  end if;
  normalized := lower(regexp_replace(btrim(coalesce(confirm_name, '')), '\s+', ' ', 'g'));
  if normalized <> lower(regexp_replace(btrim(entry.first_name || ' ' || entry.last_name), '\s+', ' ', 'g')) then
    raise exception 'confirmation does not match the member name'
      using errcode = '42501', hint = 'member_confirm_mismatch';
  end if;
  delete from public.team_memberships where member_id = target;
  -- member_private predates members and has no foreign key to it.
  delete from public.member_private where member_id = target;
  delete from public.members where id = target;
end;
$$;
