-- Tournament invitation (Einladung): the organiser's PDF/DOCX, uploaded in
-- the tournament's Sammelabrechnung (or kept from "Turnier aus Einladung
-- erstellen") and bundled into its ZIP/print job. Admins only, like expense
-- receipts (budget.manage). The app keeps one per tournament — replacing
-- deletes the old row — but there is deliberately no unique constraint, so a
-- replacement's insert never fails when it reaches the server before the
-- delete of the previous one; the app shows the newest.

create table public.tournament_invitations (
  id            uuid primary key,
  tournament_id uuid references public.events (id) on delete cascade,
  storage_path  text not null,
  file_name     text not null default '',
  content_type  text not null default '',
  uploaded_by   text not null default '',
  uploaded_at   timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references auth.users (id) on delete set null
);
create index tournament_invitations_tournament on public.tournament_invitations (tournament_id);

create trigger touch before insert or update on public.tournament_invitations
  for each row execute function public.touch_row();
create trigger log_deletion after delete on public.tournament_invitations
  for each row execute function public.log_deletion();
create trigger clear_deletion after insert on public.tournament_invitations
  for each row execute function public.clear_deletion();
create index tournament_invitations_updated_at on public.tournament_invitations (updated_at);

alter table public.tournament_invitations enable row level security;
revoke all on public.tournament_invitations from anon, authenticated;
grant select, insert, update, delete on public.tournament_invitations to authenticated;

create policy "tournament_invitations: read" on public.tournament_invitations for select to authenticated
  using ((select public.authorize('budget.manage')));
create policy "tournament_invitations: insert" on public.tournament_invitations for insert to authenticated
  with check ((select public.has_permission('budget.manage')));
create policy "tournament_invitations: update" on public.tournament_invitations for update to authenticated
  using ((select public.has_permission('budget.manage')))
  with check ((select public.has_permission('budget.manage')));
create policy "tournament_invitations: delete" on public.tournament_invitations for delete to authenticated
  using ((select public.has_permission('budget.manage')));

-- ------------------------------------------------------------ storage ---
-- Object path: <row id>.<ext>.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('tournament-invitations', 'tournament-invitations', false, 15 * 1024 * 1024,
   array['application/pdf',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'application/msword',
         'text/plain'])
on conflict (id) do nothing;

create policy "tournament-invitations: read" on storage.objects for select to authenticated
  using (bucket_id = 'tournament-invitations' and (select public.authorize('budget.manage')));
create policy "tournament-invitations: insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'tournament-invitations' and (select public.has_permission('budget.manage')));
create policy "tournament-invitations: update" on storage.objects for update to authenticated
  using (bucket_id = 'tournament-invitations' and (select public.has_permission('budget.manage')));
create policy "tournament-invitations: delete" on storage.objects for delete to authenticated
  using (bucket_id = 'tournament-invitations' and (select public.has_permission('budget.manage')));
