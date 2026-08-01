# RootCLI

This Swift package holds two tools that both talk directly to the
`iCloud.it.a11y.BlindensportGraz` CloudKit container's public database —
outside the app entirely — using **Server-to-Server (S2S)** authentication
(an ECDSA key pair registered in CloudKit Dashboard, the mechanism Apple
documents for backend integrations):

- **`rootcli`** — a command-line tool to change a user's `role`/`isRoot` flag
  and bulk-import the Grazer VSC membership roster from a JSON file.
- **`clubmembersapi`** — a small web server exposing a REST API and a basic
  HTML admin page for CRUD operations on the Grazer VSC roster. See
  [Web API & admin page](#web-api--admin-page) below.

Both share the S2S auth/request-signing code (`Sources/CloudKitS2SCore`) and
the `Member` field mapping (`MemberRecord`), so the two stay in sync
instead of drifting apart the way the app's own hand-mirrored CLI input
struct historically had to be kept in lockstep with `Models.swift` on every
field change.

> The app's roster model was renamed `ClubMember` -> `Member` (2026-08-01,
> alongside a new `memberOfGVSC` flag — see cerebrum.md). The underlying
> CloudKit **record type stays "ClubMember"** everywhere in this package (CLI
> help text, `rootcli record list ClubMember`, Dashboard schema/Security
> Roles) for compatibility with already-synced production data — only
> Swift-level type names (`MemberRecord`, `MemberBulkInput`, etc.) changed.

`rootcli` exists because the app itself deliberately has no way for a user to
change their own role, and no in-app way to grant the first `admin`/root
account either — see `Models.swift`'s `User.isRoot` doc comment. It's the
out-of-band escape hatch for that, and (once you do the one-time Dashboard
step below) becomes the *only* way to write those fields at all, closing the
gap where any app client could otherwise forge a CloudKit `UserIdentity`
record.

`clubmembersapi` exists so the Grazer VSC roster can be managed from a browser
or any HTTP client instead of hand-editing a JSON file for `import-members` —
same underlying CloudKit access, just with live create/read/update/delete
instead of one-shot batch import.

## One-time setup

### 1. Generate the key pair

```bash
openssl ecparam -name prime256v1 -genkey -noout -out rootcli_private_key.pem
openssl pkcs8 -topk8 -nocrypt -in rootcli_private_key.pem -out rootcli_private_key_pkcs8.pem
openssl ec -in rootcli_private_key.pem -pubout -out rootcli_public_key.pem
rm rootcli_private_key.pem   # only the PKCS8 version is needed from here on
```

Keep `rootcli_private_key_pkcs8.pem` **outside this git repo** (e.g.
`~/.config/rootcli/`) and treat it like any other admin credential — anyone
holding it can grant themselves `admin`/root. `rootcli_public_key.pem` is safe
to share; it's what you paste into the Dashboard next.

### 2. Register the key in CloudKit Dashboard

1. Go to [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/) →
   select the `iCloud.it.a11y.BlindensportGraz` container → the environment you
   want to manage (start with **Development**).
2. **API Access** → **Server-to-Server Keys** → **Add Key**. Paste the contents
   of `rootcli_public_key.pem`.
3. Copy the generated **Key ID** — that's `CLOUDKIT_KEY_ID` below.

### 3. Restrict write access to `UserIdentity` (recommended)

By default the S2S key writes with the same permissions as any other client
("World" role), which doesn't actually close the forgery gap. Tighten it:

1. Dashboard → **Schema** → **Security Roles**.
2. Create a role (e.g. `RootAdmin`) and add your S2S key as a member of it.
3. On the `UserIdentity` record type, set the **World** role to **Read Only**,
   and grant your new `RootAdmin` role **Read/Write**. Do the same for
   `ClubMember` if you want `import-members`/`clubmembersapi` to be the only
   way roster entries get written — the app itself only ever needs to
   read/write it as an admin action, so it's a reasonable second record type
   to lock down alongside `UserIdentity`.
4. Repeat for the **Production** environment once you're ready to promote there
   (Development and Production schemas/roles are configured separately).

If `clubmembersapi` will be reachable over the network (not just run locally),
consider registering a **separate** S2S key for it and adding only that key
to the `RootAdmin` role — that way a compromised web server's key can't be
used to also call `rootcli set-root`/`set-role`, which is a strictly more
sensitive operation than roster CRUD. Reusing the same key as `rootcli` also
works and is simpler if you're the only operator of both.

If you'd rather script this than click through the UI, `cktool` (bundled with
Xcode, at `xcrun cktool`) can export/import the schema as a `.ckdb` file
(`cktool export-schema`, edit the `SECURITY ROLES` section, `cktool
import-schema`) — but hand-verify the diff before importing, a bad schema
import can lock out legitimate writes too.

### 4. Build

```bash
cd RootCLI
swift build -c release
```

Binaries land at `.build/release/rootcli` and `.build/release/clubmembersapi`.

## rootcli usage

```bash
export CLOUDKIT_KEY_ID=<key id from step 2>
export CLOUDKIT_PRIVATE_KEY_PATH=~/.config/rootcli/rootcli_private_key_pkcs8.pem
export CLOUDKIT_ENVIRONMENT=development   # or production
# CLOUDKIT_CONTAINER defaults to iCloud.it.a11y.BlindensportGraz

rootcli list
rootcli set-role "Jane Doe" admin
rootcli set-root "Jane Doe" true
rootcli import-members members.json
```

`list` prints every `UserIdentity` record as a table — name, role, whether
it's root, and an explicit note that email is *not* included, because it's
never synced to CloudKit (see the top of `CloudKitS2SClient.swift`). If you
need email addresses too, that requires deliberately publishing them
(currently not done, on purpose — ask before changing this, it's a privacy
tradeoff, not just a missing feature).

`set-role`/`set-root` match by full name (first + last) or record id
(case-insensitive) and refuse to guess if more than one account matches —
re-run with the exact id from `list` in that case.

`import-members <file.json>` reads a JSON array of members and creates
(or, if you re-run it with the same `id`, updates) matching `ClubMember`
records — see `members.example.json` for the shape. `firstName` and
`lastName` are both required; everything else defaults the way the app's own
"Neues Mitglied" form does. If you don't supply an `id`, a new UUID is
generated each run — so re-importing a file without `id`s creates duplicates
rather than updating existing entries. Bad entries (empty firstName/lastName,
non-UUID `id`) are skipped with a message rather than aborting the whole file;
the final line reports how many
succeeded/failed out of the total.

Changes made this way reach app instances the same way any other cross-device
change does: on next login or pull-to-refresh, via `CloudKitSync.syncAll`.
Newly-imported members are also matched retroactively the next time someone
creates an app account — but not against *existing* accounts, since
`Member.checkMembership` only ever runs at account-creation time (see
`cerebrum.md`'s 2026-07-16 entry on the Grazer VSC feature).

`update-members <file.json>` reads the same file shape as `import-members`
but never overwrites existing data: it matches each row against existing
`ClubMember` records by firstName+lastName and only fills fields that are
currently blank there, leaving anything already set untouched. Rows with no
existing name match are created fresh, same as `import-members`. Use this
instead of `import-members` when re-importing an updated/extended roster file
where some people already exist with data you don't want clobbered.

### Generic record insert/update (any type, not just Member)

`rootcli record` reads/writes **any** CKRecord type this app publishes —
`UserIdentity`, `ClubMember`, `Team`, `TeamMembership`, `SportEvent`,
`Training`, `Tournament`, `TrainingAttendance`, `TournamentAttendance`,
`EventParticipation` — not just the ones with a dedicated subcommand above.
`EventImage` is excluded; it carries a binary `CKAsset`, which this text/JSON
field editor doesn't handle.

```bash
rootcli record list <type>
rootcli record get <type> <id>
rootcli record set <type> <id> field=value [field:TYPE=value ...]
rootcli record delete <type> <id>
```

`set` always upserts (`createOrReplaceRecord`) — no change-tag/conflict
handling, matching the app's own push semantics. Field values default to
`STRING`; use `field:TYPE=value` for `INT64`, `DOUBLE`, `TIMESTAMP` (ISO8601
input), or `STRING_LIST` (comma-separated). Example:

```bash
rootcli record set Team 3F2504E0-4F89-11D3-9A0C-0305E82C3301 name="Herren A" sport=Torball
rootcli record set UserIdentity 3F2504E0-... isRoot:INT64=1
```

## Web API & admin page

`clubmembersapi` is a [Vapor](https://vapor.codes) server exposing a REST API
plus a single static HTML/JS page for CRUD on the Grazer VSC roster
(`Member` records, CKRecord type `ClubMember`), built on the same
`CloudKitS2SClient` as `rootcli`.

**Every request requires HTTP Basic Auth — there is no unauthenticated mode.**
This server holds an S2S key that can read/write every member's address,
phone, and email; unauthenticated CRUD over that would be a real PII exposure,
so `API_USERNAME`/`API_PASSWORD` are required environment variables and the
process refuses to start without them. This is a single shared operator
credential (like `rootcli`'s key), not a per-member login system — don't
expose this server directly to club members.

```bash
export CLOUDKIT_KEY_ID=<key id>
export CLOUDKIT_PRIVATE_KEY_PATH=~/.config/rootcli/rootcli_private_key_pkcs8.pem
export CLOUDKIT_ENVIRONMENT=development   # or production
export API_USERNAME=admin
export API_PASSWORD=<a real secret, not this>
# optional: PORT (default 8080), HOSTNAME (default 127.0.0.1)

cd RootCLI
swift run clubmembersapi serve
# or: .build/release/clubmembersapi serve
```

Open `http://127.0.0.1:8080/` (browser will prompt for the Basic Auth
credentials above) for the admin page, or call the REST API directly:

| Method | Path                | Body                              | Notes |
|--------|---------------------|------------------------------------|-------|
| GET    | `/api/members`      | —                                   | List all, sorted by last/first name |
| GET    | `/api/members/:id`  | —                                   | 404 if not found |
| POST   | `/api/members`      | `Member` fields, `firstName`/`lastName` required | 201, returns the created record with its new `id` |
| PUT    | `/api/members/:id`  | Same fields                         | 404 if not found |
| DELETE | `/api/members/:id`  | —                                   | 204, 404 if not found |
| POST   | `/api/members/import` | JSON array of `Member`-shaped objects | 200, returns `{succeeded, failed, total, messages}` |

Field names match `members.example.json` (`firstName`, `lastName`, `street`,
`zip`, `city`, `email`, `phone`, `memberNumber`, `joinedAt`, `notes`), plus
`gender`/`title`/`birthDate`/`sportId`/`svnr`/`iban`/`lastMedicalExamination`/
`defaultFunction`/`memberOfGVSC` (the last defaults to `true` when omitted);
`id` is assigned server-side on create and is otherwise read-only.

`/api/members/import` accepts exactly the same array-of-objects shape as
`rootcli import-members`/the app's own JSON export (a file on iCloud Drive,
say) — no per-record scripting needed, just post the whole file:

```bash
curl -u admin:<password> \
  -X POST https://your-host:8080/api/members/import \
  -H "Content-Type: application/json" \
  --data-binary @roster.json
```

Same rules as `rootcli import-members`: a row's `id` (if given) must be a
valid UUID and becomes the CKRecord name — re-posting a file with the same
`id`s updates those records in place, omitting `id` creates a new one every
time. `firstName`/`lastName` are required per row; rows missing them (or with
an invalid `id`) are skipped individually and reported in `messages`, not
aborted — one bad row in a spreadsheet-exported file won't sink the batch.

This server does **not** run `xcrun cktool` schema setup for you — it assumes
the `ClubMember` record type and Security Roles are already configured per
the setup steps above (the app itself, or a prior `rootcli import-members`
run, will already have created the schema in Development).

### Generic record editor (any type, not just Member)

`/api/members` above is a typed, validated CRUD layer specific to
`Member` — the one record type worth hand-modeling. For everything else
(`Team`, `SportEvent`, `Training`, `Tournament`, `TeamMembership`,
`EventParticipation`, `TrainingAttendance`, `TournamentAttendance`,
`UserIdentity`), the server also exposes a generic REST layer plus a matching
admin page at `/records.html` (linked from the main page), so you don't have
to hand-write a typed route per model to insert or update data.

| Method | Path                       | Body                     | Notes |
|--------|----------------------------|---------------------------|-------|
| GET    | `/api/records/:type`       | —                          | List all records of `:type` |
| GET    | `/api/records/:type/:id`   | —                          | 404 if not found |
| PUT    | `/api/records/:type/:id`   | JSON object of field:value | Upserts — creates if `:id` is new, updates if it exists |
| DELETE | `/api/records/:type/:id`   | —                          | 204, 404 if not found |

Field values are inferred from JSON type (number → `DOUBLE`/`INT64`, boolean,
array of strings → `STRING_LIST`, string). There's no per-type validation
here — this is deliberately a thin pass-through to CloudKit for admin/debug
use, not a replacement for the app's own field constraints. `EventImage` is
excluded (binary `CKAsset`, not representable as JSON).
