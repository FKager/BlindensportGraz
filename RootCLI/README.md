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
the `ClubMember` field mapping (`ClubMemberRecord`), so the two stay in sync
instead of drifting apart the way the app's own hand-mirrored CLI input
struct historically had to be kept in lockstep with `Models.swift` on every
field change.

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

`import-members <file.json>` reads a JSON array of club members and creates
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
`ClubMember.checkMembership` only ever runs at account-creation time (see
`cerebrum.md`'s 2026-07-16 entry on the Grazer VSC feature).

## Web API & admin page

`clubmembersapi` is a [Vapor](https://vapor.codes) server exposing a REST API
plus a single static HTML/JS page for CRUD on the Grazer VSC roster
(`ClubMember` records), built on the same `CloudKitS2SClient` as `rootcli`.

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
| POST   | `/api/members`      | `ClubMember` fields, `firstName`/`lastName` required | 201, returns the created record with its new `id` |
| PUT    | `/api/members/:id`  | Same fields                         | 404 if not found |
| DELETE | `/api/members/:id`  | —                                   | 204, 404 if not found |

Field names match `members.example.json` (`firstName`, `lastName`, `street`,
`zip`, `city`, `email`, `phone`, `memberNumber`, `joinedAt`, `notes`); `id` is
assigned server-side on create and is otherwise read-only.

This server does **not** run `xcrun cktool` schema setup for you — it assumes
the `ClubMember` record type and Security Roles are already configured per
the setup steps above (the app itself, or a prior `rootcli import-members`
run, will already have created the schema in Development).
