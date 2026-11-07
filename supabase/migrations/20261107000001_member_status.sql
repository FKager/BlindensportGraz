-- Member status: new (just added), active, delete (flagged for removal).
-- Anyone with members.manage sets the status; removing an entry is a second,
-- deliberate step that only root can take, and only on an entry flagged
-- 'delete'. The MCP server can flag but has no way to remove.

alter table public.members
  add column status text not null default 'new'
  check (status in ('new', 'active', 'delete'));

-- Everyone already on the roster is established.
update public.members set status = 'active';

-- No client deletes the table directly any more: delete_member is the only way.
drop policy "members: delete" on public.members;

-- confirm_name is the person's full name, typed by the root user, so a stale
-- id or a mis-tap can't remove the wrong entry.
create function public.delete_member(target uuid, confirm_name text)
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
  -- member_private predates members and has no foreign key to it.
  delete from public.member_private where member_id = target;
  delete from public.members where id = target;
end;
$$;

revoke execute on function public.delete_member(uuid, text) from public, anon;
grant execute on function public.delete_member(uuid, text) to authenticated;
