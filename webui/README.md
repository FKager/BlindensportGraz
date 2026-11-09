# webui

The Blindensport Graz web UI: a **Java 21 / Quarkus / Vaadin Flow** server
on top of the club's Supabase project. It is growing into an alternative to the
iOS app for organizing the club's activities, not only an admin tool. It replaces RootCLI's Swift/Vapor
`clubmembersapi` (October 2026) and serves three things:

- **Web UI (Vaadin, German UI)**: Termine (trainings, tournaments, events)
  with attendance and PRAE, Teams and their members, Trainings-Favoriten,
  Mitglieder (incl. protected data, JSON import/export), Änderungsanträge,
  App-Konten (approve, activation codes, roles, block, delete),
  Rollen-Protokoll, Vereinsbudget, Willkommensbildschirm, Abrechnung
  (KostZ, PRAE, TeilnehmerInnenlisten, Sammelabrechnung — like the app's
  „Berichte“).
- **JSON REST API**: `/api/session`, `/api/members`, `/api/members/import`.
  The contract is unchanged from the Swift server, so existing scripts keep
  working. `/api/reports` serves the invoicing files, meant as a backend
  for the app later.
- **Calendar feed**: `/calendar/<token>.ics`, the webcal URL the app's
  account screen hands out.

## Security model: act as the signed-in admin

Admins sign in with their **own Blindensport Graz account** (same as in the
app). The server does a Supabase password grant with the **anon/publishable
key** and keeps the access and refresh tokens **server-side only**, in the
session. They are never sent to the browser and are refreshed shortly
before they expire. Every database call runs **as that admin**, so Supabase
RLS and the RPCs enforce exactly the same rules as the iOS app:

- permission checks for every table
- block checks
- the last-root guard
- refusing changes to root accounts
- the audit logs

The UI only uses permissions to decide which pages and buttons to show.

| Permission | Opens |
|---|---|
| any of `members.manage`, `events.manage`, `teams.manage`, `users.approve` | signing in at all (coach, admin, root) |
| `events.manage` | Termine, Anwesenheit/PRAE, Trainings-Favoriten |
| `teams.manage` | Teams |
| `members.manage` | Mitglieder, Änderungsanträge, `/api/members*` |
| `members.private.read` / `.write` | seeing / changing SVNR, IBAN, Geburtsdatum, letzte Untersuchung |
| `users.approve` | App-Konten: approve, revoke, activation codes |
| `roles.assign` (root) | App-Konten: roles, block/unblock, delete |
| `rolelog.read` | Rollen-Protokoll |
| `budget.manage` | Vereinsbudget |
| `club.manage` | Willkommensbildschirm, Abrechnung, `/api/reports*` (PRAE files also need `members.private.read`) |

Sessions end after 30 minutes idle or 12 hours. Every 5 minutes the role is
re-read from the database, so a role change, a block or a deletion reaches an
open browser quickly. A refused token refresh ends the session at once.
Failed sign-ins are limited to 5 per 5 minutes per client IP (the first
`X-Forwarded-For` hop, see Deployment).

The **service key** is used **only** by the calendar feed, which has no user
session: its per-user token is the credential.

Side effect worth knowing: event changes made in the web UI trigger the
`notify-schedule` push like app changes do. Service-role writes never did.

## REST API

All `/api/*` calls need a signed-in session cookie (`bsg_admin_session`,
HttpOnly, Secure, SameSite=Strict). Changing requests must also send
`X-Requested-With: blindensport-admin` (anti-CSRF). Errors are
`{"error": true, "reason": "…"}`.

| Method | Path | Body | Notes |
|---|---|---|---|
| POST | `/api/session` | `{"email","password"}` | Sign in; sets the cookie; `{email, role, permissions}`. 401 wrong credentials, 403 no web access, 429 too many failures |
| GET | `/api/session` | — | Current admin, 401 if not signed in |
| DELETE | `/api/session` | — | Sign out (also revokes the Supabase session) |
| GET | `/api/members` | — | All entries, sorted by last/first name |
| GET | `/api/members/{id}` | — | 404 if unknown |
| POST | `/api/members` | member fields, `firstName`/`lastName` required | 201 with the new `id` |
| PUT | `/api/members/{id}` | member fields | Omitted gender/title/sportId/defaultFunction/memberOfGVSC/joinedAt/protected fields keep their value; address/contact/number/notes are replaced; explicit `null` clears `birthDate` / `lastMedicalExamination` |
| DELETE | `/api/members/{id}` | — | 204, also deletes the protected row |
| POST | `/api/members/import` | JSON array (app export / `members.example.json` shape, `plz` alias for `zip`) | `{succeeded, failed, total, messages}`; bad rows are skipped one by one |

```bash
curl -c cookies.txt -H "Content-Type: application/json" -H "X-Requested-With: blindensport-admin" \
  -d '{"email":"admin@example.org","password":"…"}' https://<DOMAIN>/api/session
curl -b cookies.txt -X POST https://<DOMAIN>/api/members/import \
  -H "Content-Type: application/json" -H "X-Requested-With: blindensport-admin" \
  --data-binary @roster.json
```

### Invoicing (`/api/reports`)

All GET, `club.manage`; anything containing PRAE forms (SVNR, IBAN) also
needs `members.private.read`. Trainings are invoiced per month, tournaments
one by one, as in the app. Files come as downloads (`Content-Disposition`).

| Path | Returns |
|---|---|
| `/api/reports/months/{year}/{month}` | JSON: KostZ (betrifft, ort, period, days, total, people) and PRAE forms with cap warnings |
| `/api/reports/months/{year}/{month}/kostz.xlsx` | KostZ form |
| `/api/reports/months/{year}/{month}/prae.zip[?person=]` | PRAE + Darstellung, everyone or one person |
| `/api/reports/months/{year}/{month}/sammelabrechnung.zip` | bundle, see parameters below |
| `/api/reports/tournaments` | JSON: tournaments, latest first |
| `/api/reports/tournaments/{id}` | JSON: as a month, plus both TeilnehmerInnenlisten |
| `/api/reports/tournaments/{id}/kostz.xlsx` | KostZ form |
| `/api/reports/tournaments/{id}/teilnehmer-sportler.xlsx`, `…/teilnehmer-helfer.xlsx` | TeilnehmerInnenliste of players / of coaches and assistants |
| `/api/reports/tournaments/{id}/prae.zip[?person=]` | PRAE + Darstellung |
| `/api/reports/tournaments/{id}/sammelabrechnung.zip` | bundle |

Sammelabrechnung parameters: `kostz`, `sportler`, `helfer` (tournaments)
default to `true`; `prae` is repeated person ids (the `personId` of the
JSON), absent for everyone, `prae=none` for no one.

## Calendar feed

`GET /calendar/<token>` (with or without `.ics`) returns an RFC 5545 calendar
of trainings and tournaments. Admin/root see everything; everyone else sees
unscoped entries and those of their own teams. Blocked accounts get 404, and
so do unknown or malformed tokens. UIDs stay the uppercase ids of the
CloudKit era, so existing subscriptions keep their entries. The app builds
the URL from `ServerConfig.clubMembersAPIHost`
(`BlindensportGraz/App/ServerConfig.swift`).

## Configuration

| Variable | Meaning |
|---|---|
| `SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | anon / publishable key (every admin request) |
| `SUPABASE_SERVICE_KEY` | service-role / `sb_secret_` key — calendar feed only; keep out of git |
| `SESSION_COOKIE_SECURE` | `true` (default); `false` only for plain `http://localhost` testing |
| `PORT` | default `8080` |

## MCP server

`https://bs.a11y.it/mcp` lets MCP clients (Claude Code, for example) work with the club's data: members, teams, trainings, tournaments, attendance and PRAE forms.

Connect with a personal token. Create it in the web UI under **KI-Zugang**, confirm your password, and copy it: it is shown only once. Then, for Claude Code:

```
claude mcp add --transport http blindensport https://bs.a11y.it/mcp --header "Authorization: Bearer <token>"
```

On this Mac, `supabase/scripts/mcp-connect.sh prod` does all of that in a terminal: it asks for email and password, creates the token and registers it with Claude Code.

Coaches, admins and root can create tokens, and a client can do whatever that account may do. A token lasts 90 days and can be revoked on the same page, which takes effect within a minute. Treat it like a password: the client keeps it in its settings file.

### How it works

- **Tokens:** `McpTokens`. A token stands for one Supabase session, opened when its owner confirmed their password. The database (`mcp_tokens`) holds only a hash of the token and the session's refresh token encrypted with a key derived from the token, so neither the database nor this server can use it without the token. No service key is involved.
- **Permissions:** every call runs with that person's Supabase token, so RLS and the RPCs decide, as in the app. `McpAuthFilter` admits only accounts that may use the web UI. Signing in with Apple gives no password, so those accounts can't create a token.
- **Protected data:** SVNR, IBAN, birth date, medical exam, disability and consents never appear in a tool result and can't be written, because anything returned reaches the AI behind the client. Member results are built from an allow-list in `ClubTools`.
- **PRAE forms:** they do contain SVNR and IBAN, so `create_prae_forms` returns only a summary and a link to `/mcp-files/{token}`. The link works once, lasts 10 minutes, and the file exists in memory only. Whoever holds the link gets the file.
- **Nothing deletes:** there is no delete tool. A member can only be marked with status `delete`.

### Tools

| Area | Tools |
|---|---|
| Account | `whoami` |
| Members | `list_members`, `get_member`, `create_member`, `update_member` |
| Teams | `list_teams`, `create_team`, `add_team_member` |
| Events | `list_events`, `get_event`, `create_event`, `update_event`, `set_attendance` |
| PRAE | `preview_prae`, `create_prae_forms` |

### PRAE exists twice

`prae/` is a port of the app's `PraeCalculation.swift` and `PraeExport.swift`, since the forms are now made on the phone and on this server. A change to the rules or the form belongs in both. `src/main/resources/prae` holds copies of the app's templates, because the Docker build sees only `webui/`; `PraeExporterTest` fails if they drift apart.

The same holds for KostZ and the TeilnehmerInnenliste: `reports/` ports `KostZExport.swift`, `TeilnehmerlisteExport.swift` and `SammelabrechnungExport.swift`; their templates are copies in `src/main/resources/reports`, guarded by `ReportsTest`.

### Accounts and the public start page

Without an account, `/` shows upcoming trainings and tournaments from `public_schedule`: name, day and place, like the app's Übersicht. `/registrieren` creates an account. The confirmation email links to `/konto-bestaetigen` when someone registered here, and to the app when they registered there; `supabase/templates/confirmation.html` chooses by `redirect_to`, which must be on the auth allow list (`cutover.sh <target> signup`). Confirming takes a click, because mail scanners open links by themselves.

`/passwort-vergessen` sends a reset link, and `supabase/templates/recovery.html` chooses the same way between `/passwort-neu` and the app. The link is used up on the click that saves the new password, not on opening the page.

Any account that isn't blocked can sign in to the web pages. `AccessGuard` keeps everyone but coaches, admins and root on `/`. The REST API and MCP stay staff only.

### Rollen

The Rollen page holds the Vereinsfunktionen (Obmann, Obmann Stellvertreter, Kassier, Schriftführer) and the Admin and Root accounts, and links to the log. A function has one holder, one member may hold several, and they give no rights. They need `club.manage` to change (`set_club_function`), and a trigger writes `club_function_log`. Admin and Root can have several people, belong to accounts, and only root changes them. The app's Verein tab has the same section.

### Member status

`members.status` is `new`, `active` or `delete`. Anyone with `members.manage` sets it. Only root can remove a member, only when the status is `delete`, and only by typing the full name: `delete_member` is the only way, as the table's delete policy is gone. It also removes the member's team entries, and with them their attendance and PRAE amounts.

### Rollout order

1. Database first: `supabase/scripts/cutover.sh <target> db-push`. New app and web UI versions read `members.status`, so it must exist before them.
2. Web UI: redeploy.
3. App: release a new TestFlight build. Until then, swiping to delete a member in an old build has no effect on the server, and the member comes back on the next sync.

## Deployment

The server speaks **plain HTTP** and must only be reachable through the TLS
proxy. `docker-compose.yml` at the repository root bundles Caddy, which gets a
Let's Encrypt certificate for `DOMAIN` and is the only published service.
`webui` has no host port at all:

```bash
cp .env.example .env    # SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_KEY, DOMAIN, ACME_EMAIL
docker compose up -d --build      # or: podman-compose up -d --build
```

DNS for `DOMAIN` must point at the host, with ports 80 and 443 open (Caddy
needs 80 for the ACME challenge). The sign-in limiter trusts the first
`X-Forwarded-For` hop, which is only safe because nothing but Caddy can
reach the container. **If you run the image behind your own proxy, never
publish 8080 on a public interface.** Bind it to `127.0.0.1` or an internal
network.

**Behind an existing Traefik** (e.g. Coolify on nuc): `webui/compose.traefik.yml`
runs only the app on the proxy network (alias `blindensport-webui`, no
ports), and `webui/traefik-dynamic.yml` is a file-provider route to copy
into Traefik's dynamic directory (`docker exec -i coolify-proxy sh -c 'cat >
/traefik/dynamic/blindensport-webui.yml'`). It uses a file route rather
than Docker labels because Coolify's Traefik v3.1 can't talk to Docker 29
(API 1.24 vs. minimum 1.40).

The image (`webui/Dockerfile`, build context `webui/`) is a multi-stage
Maven build with a JRE 21 runtime and a non-root user. Vaadin runs in
production mode from its prebuilt bundle, so no Node.js is needed.

## Development

There is no JDK on the maintainer's Mac, so everything runs in Docker. The
`bsg-m2` volume caches Maven dependencies.

```bash
cd webui
docker run --rm -v "$PWD":/work -v bsg-m2:/root/.m2 -w /work maven:3.9-eclipse-temurin-21 mvn -B test
docker run --rm -v "$PWD":/work -v bsg-m2:/root/.m2 -w /work maven:3.9-eclipse-temurin-21 mvn -B package -DskipTests
```

Against a local Supabase (`supabase start` at the repository root; seed login
`root@example.test` / `localroot123`):

```bash
eval "$(supabase status -o env | grep -E '^(ANON_KEY|SECRET_KEY)=')"
docker run --rm -p 127.0.0.1:8081:8080 -v "$PWD/target/quarkus-app":/app -w /app \
  -e SUPABASE_URL=http://host.docker.internal:54321 -e SUPABASE_ANON_KEY="$ANON_KEY" \
  -e SUPABASE_SERVICE_KEY="$SECRET_KEY" -e SESSION_COOKIE_SECURE=false \
  eclipse-temurin:21-jre java -jar quarkus-run.jar
```

### Tests

- Unit tests and the REST contract (`ApiTest`) run with WireMock standing in
  for Supabase. They check, among other things, that data calls carry the
  admin's token and never the service key.
- `LiveSupabaseIT` round-trips every club table against a **local** Supabase.
  It only runs with `LIVE_SUPABASE_URL=http://host.docker.internal:54321`,
  `LIVE_SUPABASE_ANON_KEY`, `LIVE_EMAIL`, `LIVE_PASSWORD`, and the URL pattern
  refuses anything that isn't local.

## Layout

`mcp/` MCP server, `prae/` PRAE calculation and forms, `reports/` KostZ,
TeilnehmerInnenliste and Sammelabrechnung, `xlsx/` template patching (see above).

```
src/main/java/it/a11y/blindensport/webui/
  supabase/   SupabaseHttp, Postgrest, GoTrue, Supabase (factory), German DB error texts
  auth/       AdminSession (tokens, refresh), AdminSessions (sign-in, timeouts, recheck), limiter
  members/    MemberStore, MemberBulkImport, ChangeRequestStore, validation, dates
  accounts/   AccountService (approval / role / block / delete RPCs, logs)
  club/       ClubStore + models (teams, memberships, events, attendance, favourites, budget, welcome)
  calendar/   CalendarFeed + /calendar resource
  api/        REST resources, CSRF/auth filter, error mapping
  ui/         Vaadin views and dialogs, AccessGuard, Announcer (aria-live messages)
```

Accessibility matters here (many club admins use VoiceOver). Every page has
an h1, and row buttons carry names like „Anna Muster bearbeiten“. Results
are announced through Vaadin notifications (errors assertive), confirm
dialogs focus „Abbrechen“ first, and the UI uses no icon-only controls.
