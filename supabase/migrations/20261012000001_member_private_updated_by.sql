-- clubmembersapi writes member_private with the service key on behalf of a
-- signed-in admin and passes that admin as updated_by. auth.uid() is null for
-- the service role, so the touch trigger used to erase it. Keep the supplied
-- value only for the service role; app users still always get their own id
-- (they cannot set someone else's).
create or replace function public.touch_member_private()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.updated_by := case
    when auth.uid() is not null then auth.uid()
    when coalesce(auth.role(), '') = 'service_role' then new.updated_by
    else null
  end;
  return new;
end;
$$;
