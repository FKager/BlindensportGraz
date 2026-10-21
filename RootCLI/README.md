# RootCLI

This Swift package holds **`rootcli`**, a command-line tool for root-only
maintenance of the Supabase backend: accounts, roles and the Grazer VSC
roster. It uses the Supabase service key, so it bypasses RLS — run it only
on a trusted machine. Shared code lives in `Sources/CloudKitS2SCore` (the
name is historical).

The web admin, REST API and calendar feed (formerly `clubmembersapi` in this
package) moved to [`../webadmin/`](../webadmin/README.md) — Java Quarkus +
Vaadin — in October 2026.

`rootcli` exists because the app deliberately has no way for a user to
change their own role, and no in-app way to grant the first `admin`/root
account either. It's the out-of-band escape hatch for that.

> CloudKit is no longer used (v0.3.0, October 2026). Its records were backed
> up and deleted on 2026-10-21; the CloudKit commands (`record`,
> `copy-records`, `cloudkit-copy-to-supabase`, `supabase-migrate`,
> `supabase-scrub-cloudkit`) were removed with them — see git history.

## Build

```bash
cd RootCLI
swift build -c release
```

The binary lands at `.build/release/rootcli`. `swift test` runs the pure
logic tests (member import/fill rules, `member_private` row format).

## Setup

```bash
export SUPABASE_URL=https://<project-ref>.supabase.co
export SUPABASE_SERVICE_KEY=<service_role or sb_secret key>   # bypasses RLS — keep out of git
```

Staging is `xlllxpmkxmcolukmcmoi`, production `dehtuoejbnunehevchtg` (see
`../supabase/`).

## Usage

```bash
rootcli list
rootcli set-role jane@example.at admin
rootcli supabase-send-resets            # dry run
rootcli import-members members.json
rootcli update-members members.json
```

`list` prints every account with its role and approval state.

`set-role <email|user id> <member|coach|admin|root>` writes `user_roles`.
Role changes are logged by the database (`role_change_log`, "System" for
RootCLI). The last `root` account cannot be removed or demoted.

`supabase-send-resets` emails every account a password-reset link (needs
SMTP configured in Supabase); a dry run unless `--apply`.

`import-members <file.json>` reads a JSON array of members and creates
(or, if you re-run it with the same `id`, updates) the matching roster
entries in `members`, `member_contacts` and `member_private` — see
`members.example.json` for the shape. `firstName` and `lastName` are both
required; everything else defaults the way the app's own "Neues Mitglied"
form does. Without an `id`, a new UUID is generated each run — so
re-importing a file without `id`s creates duplicates rather than updating
existing entries. Bad entries (empty firstName/lastName, non-UUID `id`) are
skipped with a message rather than aborting the whole file; the final line
reports how many succeeded/failed out of the total. A row without protected
fields (`svnr`, `iban`, `birthDate`, `lastMedicalExamination`) leaves that
member's stored protected data untouched.

`update-members <file.json>` reads the same file shape but never overwrites
existing data: it matches each row against existing roster entries by
firstName+lastName and only fills fields that are currently blank, leaving
anything already set untouched. Rows with no existing name match are created
fresh. Use this when re-importing an updated/extended roster file where some
people already exist with data you don't want clobbered.

Changes reach the apps on their next sync (`SupabaseSync.syncAll`, on login
or pull-to-refresh). Newly-imported members are also matched retroactively
the next time someone creates an app account — but not against *existing*
accounts, since `Member.checkMembership` only runs at account creation.

## Web admin, REST API and calendar feed

These moved out of this package in October 2026: the Swift/Vapor
`clubmembersapi` was replaced by the Java Quarkus + Vaadin server in
[`../webadmin/`](../webadmin/README.md). It covers the same REST API
(`/api/session`, `/api/members`, `/api/members/import`, unchanged contract)
and the `/calendar/<token>.ics` feed, plus the web admin for events,
teams, attendance, accounts and budget. It acts as the signed-in admin
instead of using the service key.
