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

If `clubmembersapi` will be reachable over the network (not just run locally),
consider registering a **separate** S2S key for it and adding only that key
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

`clubmembersapi` (see [Web API & admin page](#web-api--admin-page) below)
speaks plain HTTP by default — Vapor does not terminate TLS for you. **This
server must never be run as a bare, unencrypted origin server reachable from
outside `localhost`.** Sign-in passwords, session cookies and every club member's PII
(address, phone, email, and for some entries SVNR/IBAN) travel in the clear
over an unencrypted connection; deploy it behind a TLS-terminating reverse
proxy or load balancer (nginx, Caddy, a cloud provider's managed load
balancer, etc.) and only expose the proxy's HTTPS endpoint, keeping
`clubmembersapi` itself bound to `127.0.0.1`/an internal network the proxy
forwards from. TLS is a **deployment responsibility**, not something this
package does for you — audit.md Security Finding 8. This still applies
verbatim when running the container below — publish the container's port to
`127.0.0.1` (or an internal Docker/Podman network) and put the proxy in
front of that, never publish 8080 straight to a public interface.

#### Running as a container (Docker or Podman)

`RootCLI/Dockerfile` builds `clubmembersapi` as a container image (multi-stage
Swift build, non-root runtime user, `Public/` webui baked in). Because
`RootCLI/Package.swift` depends on the sibling `../Shared/ClubSchema`
package, **the build context must be the repository root**, not `RootCLI/`:

```bash
# from the repository root
docker build -f RootCLI/Dockerfile -t clubmembersapi .
# or, identically, with Podman:
podman build -f RootCLI/Dockerfile -t clubmembersapi .
```

**Recommended: `docker-compose.yml` at the repository root**, which bundles a
[Caddy](https://caddyserver.com) reverse proxy that terminates TLS and is the
only thing this deployment actually exposes to the internet — `clubmembersapi`
itself has no published host port at all, reachable only from the `caddy`
container over a compose-internal Docker network:

```bash
cp .env.example .env
# edit .env: real SUPABASE_URL/SUPABASE_SERVICE_KEY, plus DOMAIN (a real
# hostname whose DNS A/AAAA record points at this host) and ACME_EMAIL
# make sure ports 80 and 443 both reach this host from the internet — Caddy
# needs 80 for the ACME HTTP-01 challenge, not just for the HTTP->HTTPS redirect
docker compose up -d --build
# or: podman-compose up -d --build
```

Caddy then automatically obtains and renews a real Let's Encrypt certificate
for `DOMAIN` — no manual certificate handling. The webui is reachable at
`https://<DOMAIN>/` once DNS + ports are correctly pointed at the host.
`Caddyfile` (repository root) is the whole proxy config, three lines; edit it
directly for anything beyond a single-domain reverse proxy (path-based
routing to other services, etc.).

Verified end-to-end (2026-09-28): built the image, ran the full compose stack
with `DOMAIN=localhost` (Caddy falls back to its own internal CA for that
one hostname, so this only proves the reverse-proxy wiring — real deployment
still needs a real `DOMAIN` for a browser-trusted Let's Encrypt cert) and
confirmed via `curl` that unauthenticated requests get 401, valid credentials
(then: Basic Auth; since v0.2.0: Supabase sign-in) reach `/` with 200, wrong credentials get 401, and
`clubmembersapi`'s own port is genuinely unreachable from the host directly
(connection refused — only `caddy` can reach it).

**Standalone, without the bundled Caddy** (e.g. you already run your own
nginx/Traefik/cloud load balancer elsewhere and just want the bare
container): same required env vars as
[`clubmembersapi` usage](#web-api--admin-page) below:

```bash
docker run -d --name clubmembersapi \
  -p 127.0.0.1:8080:8080 \
  -e SUPABASE_URL=https://<project-ref>.supabase.co \
  -e SUPABASE_SERVICE_KEY=<sb_secret key> \
  clubmembersapi

# Podman: identical, `podman run` accepts the same flags.
```

**Never publish 8080 (or any of clubmembersapi's ports) with a `0.0.0.0`
binding directly** — it speaks plain HTTP only; see the mandatory-TLS rule
above. `127.0.0.1` here means "your own external proxy on this same host can
reach it"; point that proxy's HTTPS endpoint at it instead of exposing 8080
itself.

Notes specific to the container deployment:

- The image sets `HOSTNAME=0.0.0.0` so the server listens on all interfaces
  *inside* the container (Vapor's own default, `127.0.0.1`, would be
  unreachable across the container network namespace) — this is not the same
  as exposing it publicly; only the published-port/network config controls
  that, and neither the bundled `docker-compose.yml` nor the standalone
  `docker run` example above publish `clubmembersapi`'s own port to a public
  interface.
- `LoginAttemptLimiter` (sign-in rate limiting) keys on the client IP.
  Behind the bundled Caddy setup, `Auth.swift`'s `AdminLogin.clientAddress(for:)` reads
  the real client IP from `X-Forwarded-For` (which Caddy's `reverse_proxy`
  sets automatically) instead of `request.remoteAddress` (which would
  otherwise always be Caddy's own container IP, collapsing every real client
  into one shared failure-count bucket). This is only trustworthy because
  `docker-compose.yml` gives `clubmembersapi` no other reachable network path
  — **if you run the standalone `docker run` form behind your OWN proxy
  instead, and that proxy is on a network `clubmembersapi` shares with
  anything untrusted, `X-Forwarded-For` becomes attacker-forgeable and this
  logic should not be trusted as-is.**
- `.dockerignore` (repository root) excludes `.build/`, the iOS app target,
  and anything matching `*.pem`/`.env*` from the build context — double
  check it if you add new files that might contain secrets.

### 5. Build

```bash
cd RootCLI
swift build -c release
```

Binaries land at `.build/release/rootcli` and `.build/release/clubmembersapi`.

## Supabase (accounts, roles, protected member data)

Since October 2026, accounts, roles, approvals and the protected roster
fields (`svnr`, `iban`, `birthDate`, `lastMedicalExamination`) live in
Supabase (EU, project defined in `../supabase/`), not in CloudKit. `rootcli
list`/`set-role` and the webcal feed of `clubmembersapi` use the Supabase
admin API with:

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
> CloudKit's Web Services REST API (what `rootcli`/`clubmembersapi` use)
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

## Web API & admin page

`clubmembersapi` is a [Vapor](https://vapor.codes) server exposing a REST API
plus a single static HTML/JS page for CRUD on the Grazer VSC roster. Since
v0.3.0 it reads and writes Supabase only (`members`, `member_contacts`,
`member_private`; the calendar feed reads `events` and `team_memberships`)
and needs no CloudKit key. The generic CloudKit editor (`records.html`,
`/api/records`) is gone — use the Supabase dashboard's table editor.

**Every API call requires a signed-in admin — there is no shared password and
no unauthenticated mode.** Admins sign in on the web pages (or via
`POST /api/session`) with their own Blindensport Graz account — the same
Supabase account they use in the app. The server checks the password with
Supabase Auth and reads the account's role and permissions from the database:

| Permission (`app_permission`) | Allows |
|---|---|
| `members.manage` | signing in at all; list/create/edit/delete roster entries, import |
| `members.private.read` | seeing `svnr`, `iban`, `birthDate`, `lastMedicalExamination` |
| `members.private.write` | changing them (also needed for imports that contain them) |

Admins and root have all three; coaches and members can't sign in. The session
is an opaque random token in an `HttpOnly`, `Secure`, `SameSite=Strict`
cookie, held in memory (a restart signs everyone out). It ends after 30
minutes idle or 12 hours, and the role is re-read every 5 minutes, so a role
change or removal takes effect quickly. Changing requests must also send
`X-Requested-With: blindensport-admin` (anti-CSRF; the pages do this).

**Protected member data lives only in Supabase** (`member_private`, since app
v0.2.0). The API reads and writes it there with the service key — never in
CloudKit, whose public database every app install can read — and records the
signed-in admin as `updated_by`. Deleting a member also deletes their
protected row. The generic records API rejects those fields and the retired
account record types (`UserIdentity`, `RoleAssignment`, `AccountApproval`).

Failed sign-ins from the same client IP are rate-limited (audit.md Security
Finding 9): after 5 failures within a 5-minute sliding window, that client
gets `429 Too Many Requests` until the window clears; a successful sign-in
resets the count. See `LoginAttemptLimiter.swift` — in-memory only, by
design. Supabase Auth applies its own rate limits on top.

```bash
export CLOUDKIT_KEY_ID=<key id>
export CLOUDKIT_PRIVATE_KEY_PATH=~/.config/rootcli/rootcli_private_key_pkcs8.pem
export CLOUDKIT_ENVIRONMENT=development   # or production
export SUPABASE_URL=https://<project-ref>.supabase.co
export SUPABASE_SERVICE_KEY=<sb_secret key>   # keep out of git
export SESSION_COOKIE_SECURE=false            # only for plain http://127.0.0.1 testing
# optional: PORT (default 8080), HOSTNAME (default 127.0.0.1)

cd RootCLI
swift run clubmembersapi serve
# or: .build/release/clubmembersapi serve
```

Open `http://127.0.0.1:8080/` and sign in with an admin account, or call
the REST API directly (sign in with `POST /api/session` first and keep the
cookie). The
webui (`RootCLI/Public/index.html`) covers full CRUD on the roster, a
live search/filter over the loaded list, a "JSON exportieren" button that
downloads the current list as a file, and a JSON file-upload form for
`/api/members/import` (results — succeeded/failed/messages — shown inline);
`records.html`, linked from its nav bar, is the generic editor for every
other record type (also with a live search/filter) — see
[Generic record editor](#generic-record-editor-any-type-not-just-member)
below.

| Method | Path                | Body                              | Notes |
|--------|---------------------|------------------------------------|-------|
| POST   | `/api/session`      | `{"email", "password"}`             | Sign in; sets the session cookie, returns `{email, role, permissions}`. 401 wrong credentials, 403 no `members.manage` |
| GET    | `/api/session`      | —                                   | Current admin, 401 if not signed in |
| DELETE | `/api/session`      | —                                   | Sign out |
| GET    | `/api/members`      | —                                   | List all, sorted by last/first name |
| GET    | `/api/members/:id`  | —                                   | 404 if not found |
| POST   | `/api/members`      | `Member` fields, `firstName`/`lastName` required | 201, returns the created record with its new `id` |
| PUT    | `/api/members/:id`  | Same fields                         | 404 if not found |
| DELETE | `/api/members/:id`  | —                                   | 204, 404 if not found |
| POST   | `/api/members/import` | JSON array of `Member`-shaped objects | 200, returns `{succeeded, failed, total, messages}` |

Field names match `members.example.json` (`firstName`, `lastName`, `street`,
`zip`, `city`, `country`, `email`, `phone`, `memberNumber`, `joinedAt`, `notes`), plus
`gender`/`title`/`birthDate`/`sportId`/`svnr`/`iban`/`lastMedicalExamination`/
`defaultFunction`/`memberOfGVSC` (the last defaults to `true` when omitted);
`id` is assigned server-side on create and is otherwise read-only. The
protected fields (`svnr`, `iban`, `birthDate`, `lastMedicalExamination`) are
returned empty without `members.private.read`, and sending them needs
`members.private.write`; on `PUT`, an omitted field keeps its stored value.

`/api/members/import` accepts exactly the same array-of-objects shape as
`rootcli import-members`/the app's own JSON export (a file on iCloud Drive,
say) — no per-record scripting needed, just post the whole file:

```bash
curl -c cookies.txt -H "Content-Type: application/json" -H "X-Requested-With: blindensport-admin" \
  -d '{"email":"admin@example.org","password":"…"}' https://your-host/api/session
curl -b cookies.txt -X POST https://your-host/api/members/import \
  -H "Content-Type: application/json" -H "X-Requested-With: blindensport-admin" \
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

### Calendar feed (webcal) — the one unauthenticated route

`GET /calendar/:token` (`:token` may carry a literal `.ics` suffix, e.g.
`/calendar/AbC123.ics` — both forms work) returns one member's
training/tournament schedule as a single RFC 5545 `.ics` file
(`Content-Type: text/calendar`), for subscribing from a system calendar app
via `webcal://your-host/calendar/<token>.ics`.

This is the **only** data route in this server that doesn't require a signed-in
admin — a webcal subscription can't sign in, so each member's own opaque,
unguessable, regenerable calendar token (`profiles.calendar_token` in
Supabase, set from the app's Account tab → "Kalender-Abo") is the credential
instead, checked inside the route handler. See `Auth.swift`'s
`RequireAdminForAPI` and `CloudKitS2SCore/CalendarFeed.swift`'s
doc comments for the full reasoning. The feed only ever includes
title/time/venue — the same data that member could already see in the app —
filtered by the same admin-sees-everything / everyone-else-sees-their-own-
teams rule the app itself uses; never any roster PII.

**Deployment note:** the app's Account tab builds the subscription URL
against `ServerConfig.clubMembersAPIHost` (`BlindensportGraz/ServerConfig.swift`),
which is `nil` until this server is actually deployed somewhere with a real
hostname (see "Deployment / TLS" above) — point it there and rebuild once
you have one.

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
