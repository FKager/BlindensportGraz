-- Personal access tokens for MCP clients. The token itself is never stored:
-- only its hash, plus the account's Supabase session encrypted with a key
-- derived from the token. So nothing here can be used without the token.
-- Deleting a row revokes the token within a minute.

create table public.mcp_tokens (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  label          text not null check (length(btrim(label)) between 1 and 80),
  token_hash     text not null unique,
  sealed_session text not null,
  created_at     timestamptz not null default now(),
  last_used_at   timestamptz,
  expires_at     timestamptz not null
);
create index mcp_tokens_user on public.mcp_tokens (user_id);

alter table public.mcp_tokens enable row level security;

revoke all on public.mcp_tokens from anon, authenticated;
-- Owners see the list, never the hash or the sealed session.
grant select (id, user_id, label, created_at, last_used_at, expires_at) on public.mcp_tokens to authenticated;
grant insert (user_id, label, token_hash, sealed_session, expires_at) on public.mcp_tokens to authenticated;
grant delete on public.mcp_tokens to authenticated;

create policy "mcp_tokens: read own" on public.mcp_tokens for select to authenticated
  using (user_id = (select auth.uid()));
create policy "mcp_tokens: create own" on public.mcp_tokens for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "mcp_tokens: delete own" on public.mcp_tokens for delete to authenticated
  using (user_id = (select auth.uid()));

-- Called before any user is known, hence anon: the caller proves itself by
-- knowing the hash of a 256-bit random token, and what comes back is only
-- readable with the token.
create function public.mcp_token_session(p_token_hash text)
returns table (user_id uuid, sealed_session text)
language sql
stable
security definer
set search_path = ''
as $$
  select t.user_id, t.sealed_session from public.mcp_tokens t
   where t.token_hash = p_token_hash and t.expires_at > now();
$$;

-- Supabase rotates refresh tokens, so the sealed session changes on each refresh.
create function public.mcp_token_update(p_token_hash text, p_sealed_session text)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.mcp_tokens set sealed_session = p_sealed_session, last_used_at = now()
   where token_hash = p_token_hash and expires_at > now();
$$;

revoke execute on function public.mcp_token_session(text) from public;
revoke execute on function public.mcp_token_update(text, text) from public;
grant execute on function public.mcp_token_session(text) to anon;
grant execute on function public.mcp_token_update(text, text) to anon;
