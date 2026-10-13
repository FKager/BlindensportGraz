-- Files formerly stored as CKAssets: event photos and expense receipts.
-- Private buckets; access follows the matching tables (event_images,
-- expense_receipts). Object paths: <row id>.<ext>.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('event-images', 'event-images', false, 15 * 1024 * 1024,
   array['image/jpeg', 'image/png', 'image/heic', 'image/heif']),
  ('receipts', 'receipts', false, 15 * 1024 * 1024,
   array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'application/pdf'])
on conflict (id) do nothing;

create policy "event-images: approved read" on storage.objects for select to authenticated
  using (bucket_id = 'event-images' and (select public.is_approved()));
create policy "event-images: insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'event-images' and (select public.has_permission('events.manage')));
create policy "event-images: update" on storage.objects for update to authenticated
  using (bucket_id = 'event-images' and (select public.has_permission('events.manage')));
create policy "event-images: delete" on storage.objects for delete to authenticated
  using (bucket_id = 'event-images' and (select public.has_permission('events.manage')));

create policy "receipts: read" on storage.objects for select to authenticated
  using (bucket_id = 'receipts' and (select public.authorize('budget.manage')));
create policy "receipts: insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'receipts' and (select public.has_permission('budget.manage')));
create policy "receipts: update" on storage.objects for update to authenticated
  using (bucket_id = 'receipts' and (select public.has_permission('budget.manage')));
create policy "receipts: delete" on storage.objects for delete to authenticated
  using (bucket_id = 'receipts' and (select public.has_permission('budget.manage')));
