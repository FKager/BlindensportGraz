-- Tournament documents (Dokumente): the single admin-only invitation of
-- 20261104000001 becomes a list of documents per tournament (invitation,
-- schedule, results, …). Table and bucket keep their names so existing rows,
-- files and older app builds keep working.
--
-- Every approved account reads them (like event photos); events.manage
-- uploads and deletes. The Sammelabrechnung bundles all of a tournament's
-- documents.

drop policy "tournament_invitations: read" on public.tournament_invitations;
drop policy "tournament_invitations: insert" on public.tournament_invitations;
drop policy "tournament_invitations: update" on public.tournament_invitations;
drop policy "tournament_invitations: delete" on public.tournament_invitations;

create policy "tournament_invitations: approved read" on public.tournament_invitations for select to authenticated
  using ((select public.is_approved()));
create policy "tournament_invitations: insert" on public.tournament_invitations for insert to authenticated
  with check ((select public.has_permission('events.manage')));
create policy "tournament_invitations: update" on public.tournament_invitations for update to authenticated
  using ((select public.has_permission('events.manage')))
  with check ((select public.has_permission('events.manage')));
create policy "tournament_invitations: delete" on public.tournament_invitations for delete to authenticated
  using ((select public.has_permission('events.manage')));

-- ------------------------------------------------------------ storage ---
update storage.buckets
   set allowed_mime_types = array[
         'application/pdf',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'application/msword',
         'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
         'application/vnd.ms-excel',
         'text/plain',
         'image/jpeg', 'image/png', 'image/heic', 'image/heif']
 where id = 'tournament-invitations';

drop policy "tournament-invitations: read" on storage.objects;
drop policy "tournament-invitations: insert" on storage.objects;
drop policy "tournament-invitations: update" on storage.objects;
drop policy "tournament-invitations: delete" on storage.objects;

create policy "tournament-invitations: approved read" on storage.objects for select to authenticated
  using (bucket_id = 'tournament-invitations' and (select public.is_approved()));
create policy "tournament-invitations: insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'tournament-invitations' and (select public.has_permission('events.manage')));
create policy "tournament-invitations: update" on storage.objects for update to authenticated
  using (bucket_id = 'tournament-invitations' and (select public.has_permission('events.manage')));
create policy "tournament-invitations: delete" on storage.objects for delete to authenticated
  using (bucket_id = 'tournament-invitations' and (select public.has_permission('events.manage')));
