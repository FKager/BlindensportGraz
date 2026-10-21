-- LOCAL DEVELOPMENT ONLY (`supabase db reset`). Never pushed to the hosted
-- project — production accounts and roles were migrated from CloudKit (v0.2.0).
-- Local root login: root@example.test / localroot123

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, recovery_token,
  email_change_token_new, email_change
) values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-0000-0000-0000000000aa',
  'authenticated', 'authenticated', 'root@example.test',
  extensions.crypt('localroot123', extensions.gen_salt('bf')),
  now(), '{"provider":"email","providers":["email"]}',
  '{"first_name":"Local","last_name":"Root"}',
  now(), now(), '', '', '', ''
);

insert into auth.identities (
  id, user_id, provider_id, identity_data, provider, created_at, updated_at, last_sign_in_at
) values (
  gen_random_uuid(),
  '00000000-0000-0000-0000-0000000000aa',
  '00000000-0000-0000-0000-0000000000aa',
  '{"sub":"00000000-0000-0000-0000-0000000000aa","email":"root@example.test"}',
  'email', now(), now(), now()
);

insert into public.user_roles (user_id, role)
values ('00000000-0000-0000-0000-0000000000aa', 'root');
