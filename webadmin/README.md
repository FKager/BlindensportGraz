# webadmin

The Blindensport Graz web admin: a **Java 21 / Quarkus / Vaadin Flow** server
on top of the club's Supabase project. It replaces RootCLI's Swift/Vapor
`clubmembersapi` (October 2026) and serves three things:

- **Web admin (Vaadin, German UI)**: Termine (trainings, tournaments, events)
  with attendance and PRAE, Teams and their members, Trainings-Favoriten,
  Mitglieder (incl. protected data, JSON import/export), Änderungsanträge,
  App-Konten (approve, activation codes, roles, block, delete),
  Rollen-Protokoll, Vereinsbudget, Willkommensbildschirm.
- **JSON REST API**: `/api/session`, `/api/members`, `/api/members/import`.
  The contract is unchanged from the Swift server, so existing scripts keep
  working.
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
| `club.manage` | Willkommensbildschirm |

Sessions end after 30 minutes idle or 12 hours. Every 5 minutes the role is
re-read from the database, so a role change, a block or a deletion reaches an
open browser quickly. A refused token refresh ends the session at once.
Failed sign-ins are limited to 5 per 5 minutes per client IP (the first
`X-Forwarded-For` hop, see Deployment).

The **service key** is used **only** by the calendar feed, which has no user
session: its per-user token is the credential.

Side effect worth knowing: event changes made in the web admin trigger the
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

## Deployment

The server speaks **plain HTTP** and must only be reachable through the TLS
proxy. `docker-compose.yml` at the repository root bundles Caddy, which gets a
Let's Encrypt certificate for `DOMAIN` and is the only published service.
`webadmin` has no host port at all:

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

**Behind an existing Traefik** (e.g. Coolify on nuc): `webadmin/compose.traefik.yml`
runs only the app on the proxy network (alias `blindensport-webadmin`, no
ports), and `webadmin/traefik-dynamic.yml` is a file-provider route to copy
into Traefik's dynamic directory (`docker exec -i coolify-proxy sh -c 'cat >
/traefik/dynamic/blindensport-webadmin.yml'`). It uses a file route rather
than Docker labels because Coolify's Traefik v3.1 can't talk to Docker 29
(API 1.24 vs. minimum 1.40).

The image (`webadmin/Dockerfile`, build context `webadmin/`) is a multi-stage
Maven build with a JRE 21 runtime and a non-root user. Vaadin runs in
production mode from its prebuilt bundle, so no Node.js is needed.

## Development

There is no JDK on the maintainer's Mac, so everything runs in Docker. The
`bsg-m2` volume caches Maven dependencies.

```bash
cd webadmin
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

```
src/main/java/it/a11y/blindensport/webadmin/
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
