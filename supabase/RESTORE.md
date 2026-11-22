# Restoring a production backup

The workflow **Supabase Maintenance** (`.github/workflows/supabase-maintenance.yml`)
makes an encrypted backup every Monday (and on manual start), kept 30 days as a
GitHub artifact `supabase-prod-<date>`:

- `backup/roles.sql`, `backup/schema.sql`, `backup/data.sql`: the database
  (roles, schema, data of `auth` and `public`).
- `backup/storage/<bucket>/…`: the files in Supabase Storage (tournament
  documents, event photos, receipts, profile photos), once the S3 access key
  secrets are set (see below). Without them the workflow warns and backs up
  only the database.

Encrypted with [age](https://age-encryption.org) for the public key in the
GitHub secret `AGE_RECIPIENT`. The private key is
`~/.config/blindensport/supabase-backup-age.key` on Franz's Mac — keep a copy
in the password manager: without it no backup can be read.

The database part was restored successfully into a scratch local Supabase on
2026-11-22 (backup of 2026-11-16: all tables, 86 policies, RLS on everywhere,
anonymous reads behave as in production).

## 1. Get and decrypt a backup

```sh
mkdir -p ~/restore && chmod 700 ~/restore && cd ~/restore
gh run download --repo FKager/BlindensportGraz -n supabase-prod-2026-11-16 -D .
age -d -i ~/.config/blindensport/supabase-backup-age.key supabase-prod-2026-11-16.tar.gz.age | tar xzf -
```

The plain files contain everything (SVNR, IBAN, …): delete them when done
(`rm -P backup/*.sql; rm -rf backup`).

## 2. Restore the database

Into a **new, empty** project (a fresh Supabase project, or a scratch local one
— never over a database that still has data). The order and the
`session_replication_role` line are Supabase's documented restore:

```sh
psql "$TARGET_DB_URL" --single-transaction -v ON_ERROR_STOP=1 \
  -f backup/roles.sql -f backup/schema.sql \
  -c 'SET session_replication_role = replica' -f backup/data.sql
```

For a hosted project, `TARGET_DB_URL` is the session pooler URL from the
dashboard (Connect). For a local scratch stack, run it in the database
container as `supabase_admin` (the `postgres` user may not change Supabase's
reserved roles in `roles.sql`):

```sh
docker cp backup/. supabase_db_<project_id>:/tmp/restore/
docker exec supabase_db_<project_id> psql -U supabase_admin -d postgres --single-transaction -v ON_ERROR_STOP=1 \
  -f /tmp/restore/roles.sql -f /tmp/restore/schema.sql \
  -c 'SET session_replication_role = replica' -f /tmp/restore/data.sql
```

A scratch local stack next to the normal one: `supabase init` in an empty
folder, a different `project_id` and ports (e.g. 554xx) in its `config.toml`,
copy the `*-version` files from this repo's `supabase/.temp/` so no new
images are downloaded, then `supabase start -x studio,imgproxy,logflare,vector,supavisor,realtime,edge-runtime,postgres-meta,mailpit`.
Remove it afterwards with `supabase stop --no-backup`.

## 3. Restore the files

The buckets themselves (names, size limits, types) come back with the schema
(the migrations create them). Upload the files with the target project's
Storage S3 access key (dashboard: Project Settings → Storage → S3 Access Keys):

```sh
export AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=… AWS_DEFAULT_REGION=eu-central-1
endpoint=https://<target-ref>.storage.supabase.co/storage/v1/s3
for dir in backup/storage/*/; do
  aws s3 sync "$dir" "s3://$(basename "$dir")" --endpoint-url "$endpoint"
done
```

## 4. Check

- `select count(*)` on `members`, `events`, `attendances`, `auth.users`
  matches what you expect; `select count(*) from public.user_roles where role = 'root'` > 0.
- No table without RLS: `select tablename from pg_tables t join pg_class c on c.relname = t.tablename and c.relnamespace = 'public'::regnamespace where schemaname = 'public' and not c.relrowsecurity` returns nothing.
- Signed out, `GET /rest/v1/public_schedule` works and `GET /rest/v1/members` returns `[]`.
- Then point the web UI (`cutover.sh <env> webui`) and the app at the new project.

## Setting up the file backup (once)

1. Supabase dashboard → blindensport-prod → Project Settings → Storage →
   **S3 Access Keys** → New access key (description e.g. "GitHub backup").
2. Store both values as GitHub secrets (the values are shown once):

   ```sh
   gh secret set SUPABASE_PROD_S3_ACCESS_KEY_ID
   gh secret set SUPABASE_PROD_S3_SECRET_ACCESS_KEY
   ```

   (`gh secret set` asks for the value, so it doesn't end up in the shell history.)
3. Start the workflow by hand once (`gh workflow run "Supabase Maintenance"`)
   and check its log: one line per bucket with the number of files.
