# RootCLI

This Swift package holds **`rootcli`**, a command-line tool for root-only
maintenance: roles, roster import/update, the CloudKit → Supabase copy and
migration commands. It talks to Supabase with the service key and to the
`iCloud.it.a11y.BlindensportGraz` CloudKit container's public database with
**Server-to-Server (S2S)** authentication (an ECDSA key pair registered in
CloudKit Dashboard). Shared code lives in `Sources/CloudKitS2SCore`.

The web admin, REST API and calendar feed (formerly `clubmembersapi` in this
package) moved to [`../webadmin/`](../webadmin/README.md) — Java Quarkus +
Vaadin — in October 2026.

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

> **Development and Production each need their OWN key pair.** CloudKit
> Dashboard will not let the same public key be registered under both
> environments — repeat step 1 (with a different output filename, e.g.
> `rootcli_private_key_development_pkcs8.pem` / `..._production_pkcs8.pem`)
> and step 2 once per environment, and keep both `CLOUDKIT_KEY_ID`/
> `CLOUDKIT_PRIVATE_KEY_PATH` pairs on hand — you'll switch between them via
> `CLOUDKIT_ENVIRONMENT`. Confirmed live 2026-08-22: a key registered only
> under Production returns `HTTP 401 Authentication failed` when used with
> `CLOUDKIT_ENVIRONMENT=development`, and vice versa.

### 3. Restrict access via CloudKit Security Roles (recommended)

By default every CKRecord type in a public database grants the **World**
role full Read/Write — i.e. anyone who knows the container ID, not even
signed into iCloud, can read or write any record (audit.md Security
Finding 2). This app currently publishes **13 CKRecord types** (verified
against `CloudKitSync.swift`/`Models.swift` directly, not just the
2 previously documented here):

`UserIdentity`, `ClubMember`, `Team`, `TeamMembership`, `SportEvent`,
`Tournament`, `Training`, `TrainingAttendance`, `TournamentAttendance`
(one local `Attendance` model, two CKRecord types — see `pushAttendance`),
`EventParticipation`, `EventImage`, `TrainingFavorite`, `RoleChangeLog`.

**Important architectural constraint**: the app's own write paths (creating
a Team, RSVPing to an event, an admin editing the roster or another user's
role in `UserListView`/`MembersViews.swift`) all go through the *signed-in
user's own Apple ID* via `CKContainer`/`CKDatabase`, not through this
package's S2S key. Any role locked down to `RootAdmin`-only (see Tier 2
below) stops working from *inside the app* for that record type — this
isn't a gap to "fix", it's a real tradeoff that has to be a deliberate
choice per type, not a blanket lockdown.

**Tier 1 — apply to all 13 types, safe, breaks nothing:**

1. Dashboard → **Schema** → **Security Roles**.
2. For every record type: set **World** to no access, and grant
   **Authenticated Users** Read + Write instead.
3. This alone closes Finding 2's literal gap (anonymous, not-signed-into-
   iCloud access to club data over the open internet) without touching any
   app behavior — every real user of this app is already signed into some
   iCloud account just to make CloudKit requests at all, "Authenticated
   Users" is not club-membership-scoped but it is a real, meaningful floor
   above "anyone on the internet".

**Tier 2 — optional, per-type judgment call, WILL break in-app write paths
if applied without also changing app code:**

| Record type | Recommendation |
|---|---|
| `UserIdentity` | Contains `role`/`isRoot` — the account-escalation surface Security Finding 1 was about. Locking **Write** to a custom `RootAdmin` role (S2S key only) fully closes "any app client could forge an admin grant" — but also breaks `UserListView`'s existing in-app role-editing feature (`AccountView.swift`), which pushes via the acting root user's own Apple ID. Only apply this tier if that in-app feature is intentionally retired in favor of RootCLI/`clubmembersapi`-only role management (not decided by this phase — flagged for a future decision). |
| `ClubMember` | Roster PII — address, phone, email, and (for helpers/coaches) SVNR/IBAN. Same constraint as `UserIdentity`: `MembersViews.swift` lets admin-role app users create/edit roster entries via their own Apple ID. Locking Write to `RootAdmin`-only would make `import-members`/`clubmembersapi`/`update-members` the *only* way roster entries get written, at the cost of removing the in-app roster-editing screens' ability to save. |
| `RoleChangeLog` | The Phase 2 audit trail — written both by the app (`CloudKitSync.logRoleChange`, same in-app Apple-ID path as above) and by RootCLI's S2S key. Same constraint: don't lock past Tier 1 unless the in-app role/root-grant write paths above are also retired. |
| `Team`, `TeamMembership`, `SportEvent`, `Tournament`, `Training`, `EventParticipation`, `TrainingAttendance`, `TournamentAttendance`, `EventImage` | Club-shared operational data, written by any admin/coach app user through their own Apple ID as part of normal app use (creating trainings, marking attendance, uploading event photos). Tier 1 (Authenticated Users) is the realistic ceiling here — a `RootAdmin`-only Write lock would break these features entirely for every non-RootCLI admin. |
| `TrainingFavorite` | Despite the name suggesting per-user data, this is actually **team-scoped**, not per-account-private (see `Models.swift` — it holds a `teams: [Team]` relationship, no per-user ownership field at all). Treat it the same as the other club-shared types above, not as personal data. |

If a web server ever needs CloudKit S2S access again (the current web admin
doesn't — it only talks to Supabase), consider registering a **separate** S2S key for it and adding only that key
to any `RootAdmin` role you do create — that way a compromised web server's
key can't be used to also call `rootcli set-root`/`set-role`, which is a
strictly more sensitive operation than roster CRUD. Reusing the same key as
`rootcli` also works and is simpler if you're the only operator of both.

**Development and Production are separate CloudKit environments with
independently-configured schemas AND Security Roles** — nothing done in one
applies to the other. Repeat every step above for **both** environments;
this app's data has historically only been verified/discussed for one
environment at a time (see cerebrum.md's 2026-08-22 entries), so don't
assume "we hardened CloudKit" without explicitly checking both tabs in
Dashboard.

If you'd rather script this than click through the UI, `cktool` (bundled with
Xcode, at `xcrun cktool`) can export/import the schema as a `.ckdb` file
(`cktool export-schema`, edit the `SECURITY ROLES` section, `cktool
import-schema`) — but hand-verify the diff before importing, a bad schema
import can lock out legitimate writes too.

### 4. Deployment / TLS

Only relevant for the web admin, which now lives in `../webadmin/` — see
its README's "Deployment" section and `docker-compose.yml` / `Caddyfile` at
the repository root. `rootcli` is a local command-line tool and is never
deployed.

### 5. Build

```bash
cd RootCLI
swift build -c release
```

The binary lands at `.build/release/rootcli`.

## Supabase (accounts, roles, protected member data)

Since October 2026, accounts, roles, approvals and the protected roster
fields (`svnr`, `iban`, `birthDate`, `lastMedicalExamination`) live in
Supabase (EU, project defined in `../supabase/`), not in CloudKit. `rootcli
list`/`set-role` use the Supabase admin API with:

```bash
export SUPABASE_URL=https://<project-ref>.supabase.co
export SUPABASE_SERVICE_KEY=<service_role or sb_secret key>   # bypasses RLS — keep out of git
```

One-time migration from CloudKit (each step is a dry run without `--apply`):

```bash
rootcli supabase-migrate            # review: accounts, roles, approvals, skipped rows
rootcli supabase-migrate --apply    # same user ids, email confirmed, roles + approvals + member_private
rootcli supabase-send-resets --apply   # password-reset email to every account (needs SMTP in Supabase)
# after the new app build is installed on every device:
rootcli supabase-scrub-cloudkit --apply   # remove protected fields + delete UserIdentity/RoleAssignment/AccountApproval
```

Role changes are logged by the database (`role_change_log`, "System" for
RootCLI). The last `root` account cannot be removed or demoted.

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

Since v0.3.0 both commands write Supabase only (`members`,
`member_contacts`, `member_private`) and need `SUPABASE_URL`/
`SUPABASE_SERVICE_KEY`, not a CloudKit key. A row without protected fields
(`svnr`, `iban`, `birthDate`, `lastMedicalExamination`) leaves that member's
stored protected data untouched.

Changes made this way reach app instances the same way any other cross-device
change does: on next login or pull-to-refresh, via `SupabaseSync.syncAll`.
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
Protected fields are filled the same way, in Supabase.

`rootcli record set` refuses protected member fields and the retired account
record types (`UserIdentity`, `RoleAssignment`, `AccountApproval`) — those
live in Supabase now.

### Generic record insert/update (any type, not just Member)

`rootcli record` reads/writes **any** CKRecord type this app publishes —
`UserIdentity`, `ClubMember`, `Team`, `TeamMembership`, `SportEvent`,
`Training`, `Tournament`, `TrainingAttendance`, `TournamentAttendance`,
`EventParticipation` — not just the ones with a dedicated subcommand above.
`EventImage`/`ExpenseReceipt` carry a binary `CKAsset`; use `field:ASSET=path`
(below) for that one field, everything else works the same as any other type.

```bash
rootcli record list <type>
rootcli record get <type> <id>
rootcli record set <type> <id> field=value [field:TYPE=value ...]
rootcli record delete <type> <id>
```

`set` always upserts (`createOrReplaceRecord`) — no change-tag/conflict
handling, matching the app's own push semantics. Field values default to
`STRING`; use `field:TYPE=value` for `INT64`, `DOUBLE`, `TIMESTAMP` (ISO8601
input), `STRING_LIST` (comma-separated), or `ASSET` (a local file path —
uploaded via CloudKit's asset-upload flow before the record is saved).
Examples:

```bash
rootcli record set Team 3F2504E0-4F89-11D3-9A0C-0305E82C3301 name="Herren A" sport=Torball
rootcli record set UserIdentity 3F2504E0-... isRoot:INT64=1
rootcli record set ExpenseReceipt 3F2504E0-... uploadedBy=admin note="Fahrtkosten" asset:ASSET=/path/to/receipt.jpg
```

> **The record type must already exist in schema before `set` can create the
> first record of that type.** Unlike the app's own native-SDK writes,
> CloudKit's Web Services REST API (what `rootcli` uses)
> does NOT auto-create a record type's schema on first write — a write to an
> undefined type fails with `NOT_FOUND — could not find record_type with
> name '...'`. Define new types via `xcrun cktool import-schema` first (see
> Apple's CloudKit Web Services / `cktool` documentation), or use them from
> the app itself once, which does auto-create Development schema via the
> native SDK. Confirmed live 2026-08-22, alongside a real bug this exposed:
> every write path in this package used to silently ignore this class of
> per-operation failure (CloudKit's `records/modify` returns HTTP 200 for
> the whole batch even when an individual operation inside it fails) — now
> fixed, every write throws a real, visible error when this happens.

## Web admin, REST API and calendar feed

These moved out of this package in October 2026: the Swift/Vapor
`clubmembersapi` was replaced by the Java Quarkus + Vaadin server in
[`../webadmin/`](../webadmin/README.md). It covers the same REST API
(`/api/session`, `/api/members`, `/api/members/import`, unchanged contract)
and the `/calendar/<token>.ics` feed, plus the web admin for events,
teams, attendance, accounts and budget. It acts as the signed-in admin
instead of using the service key.
