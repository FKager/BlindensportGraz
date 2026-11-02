-- GVSC Beitrittserklärung: the remaining fields of the club's application
-- form, the "beantragt" date, and account profile photos (attached to the
-- application mail by the send-membership-application Edge Function).

-- ------------------------------------------------------------ roster ---
-- Set by mark_gvsc_application(); cleared by an admin confirming the
-- membership (member_of_gvsc = true).
alter table public.members add column gvsc_applied_at timestamptz;

-- Contact-level form fields (members.manage, or the member's own entry).
-- membership_type: 'active' (aktiv) | 'supporting' (fördernd) | ''.
alter table public.member_contacts
  add column membership_type     text not null default ''
    check (membership_type in ('', 'active', 'supporting')),
  add column citizenship         text not null default '',
  add column mobile              text not null default '',
  add column guardian_first_name text not null default '',
  add column guardian_last_name  text not null default '',
  add column guardian_street     text not null default '',
  add column guardian_zip        text not null default '',
  add column guardian_city       text not null default '',
  add column guardian_phone      text not null default '',
  add column guardian_mobile     text not null default '',
  add column guardian_email      text not null default '';

alter table public.member_change_requests
  add column membership_type     text not null default ''
    check (membership_type in ('', 'active', 'supporting')),
  add column citizenship         text not null default '',
  add column mobile              text not null default '',
  add column guardian_first_name text not null default '',
  add column guardian_last_name  text not null default '',
  add column guardian_street     text not null default '',
  add column guardian_zip        text not null default '',
  add column guardian_city       text not null default '',
  add column guardian_phone      text not null default '',
  add column guardian_mobile     text not null default '',
  add column guardian_email      text not null default '';

-- Health data and consents are protected (members.private.*, or own entry).
-- Consents: null = not answered, true = JA, false = NEIN.
alter table public.member_private
  add column disability_type       text not null default '',
  add column disability_class      text not null default '',
  add column disability_cause      text not null default '',
  add column consent_data_transfer boolean,
  add column consent_photos        boolean;

alter table public.member_private_requests
  add column disability_type       text not null default '',
  add column disability_class      text not null default '',
  add column disability_cause      text not null default '',
  add column consent_data_transfer boolean,
  add column consent_photos        boolean;

create or replace function public.apply_member_private_request(p_member_id uuid)
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
  insert into public.member_private (member_id, svnr, iban, birth_date, last_medical_examination,
                                     disability_type, disability_class, disability_cause,
                                     consent_data_transfer, consent_photos)
  values (req.member_id, req.svnr, req.iban, req.birth_date, req.last_medical_examination,
          req.disability_type, req.disability_class, req.disability_cause,
          req.consent_data_transfer, req.consent_photos)
  on conflict (member_id) do update
    set svnr = excluded.svnr,
        iban = excluded.iban,
        birth_date = excluded.birth_date,
        last_medical_examination = excluded.last_medical_examination,
        disability_type = excluded.disability_type,
        disability_class = excluded.disability_class,
        disability_cause = excluded.disability_cause,
        consent_data_transfer = excluded.consent_data_transfer,
        consent_photos = excluded.consent_photos;
  delete from public.member_private_requests where member_id = p_member_id;
end;
$$;

-- ------------------------------------------------------- application ---
-- Called (with the caller's JWT) by the send-membership-application Edge
-- Function before it sends the mail: members.manage for any entry, or the
-- caller's own approved entry. Marks the entry as applied and returns the
-- account linked to it (for the profile photo), or null.
create function public.mark_gvsc_application(p_member_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.members;
begin
  if not (public.has_permission('members.manage')
          or p_member_id = public.my_member_id()) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select * into m from public.members where id = p_member_id for update;
  if not found then
    raise exception 'member not found' using errcode = 'P0002';
  end if;
  if m.member_of_gvsc then
    raise exception 'already a member' using errcode = '22023';
  end if;
  -- One mail per entry every 5 minutes (double taps, retries).
  if m.gvsc_applied_at > now() - interval '5 minutes' then
    raise exception 'application just sent' using errcode = '22023';
  end if;
  update public.members set gvsc_applied_at = now() where id = p_member_id;
  return (select user_id from public.account_approvals
           where member_id = p_member_id
           order by approved_at desc limit 1);
end;
$$;
revoke execute on function public.mark_gvsc_application from anon, public;
grant execute on function public.mark_gvsc_application to authenticated;

-- ----------------------------------------------------- profile photos ---
-- One JPEG per account at <user id>.jpg. The owner manages it; admins with
-- members.manage may view it (Benutzerverwaltung, application mail).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('profile-photos', 'profile-photos', false, 5 * 1024 * 1024, array['image/jpeg'])
on conflict (id) do nothing;

create policy "profile-photos: own or admin read" on storage.objects for select to authenticated
  using (bucket_id = 'profile-photos'
         and (name = (select auth.uid())::text || '.jpg'
              or (select public.has_permission('members.manage'))));
create policy "profile-photos: own insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'profile-photos' and name = (select auth.uid())::text || '.jpg');
create policy "profile-photos: own update" on storage.objects for update to authenticated
  using (bucket_id = 'profile-photos' and name = (select auth.uid())::text || '.jpg')
  with check (bucket_id = 'profile-photos' and name = (select auth.uid())::text || '.jpg');
create policy "profile-photos: own delete" on storage.objects for delete to authenticated
  using (bucket_id = 'profile-photos' and name = (select auth.uid())::text || '.jpg');
