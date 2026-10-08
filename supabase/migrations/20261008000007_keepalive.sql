-- Keep-alive target for the weekly GitHub Action (Free plan projects pause
-- after 7 days without traffic). Reads no data; callable with the anon key.
create function public.ping()
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$
  select now();
$$;
revoke execute on function public.ping from public;
grant execute on function public.ping to anon, authenticated;
