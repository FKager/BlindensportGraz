# bsg — Blindensport Graz on the command line

Accounts, roles and the roster, through the web UI's REST API (`/api`) with
a **personal token**, so the same rules apply as in the app and the web UI.
Replaced the Swift `RootCLI` (which used the Supabase service key; removed 2026-11-23).

## Setup

1. Java 21. Build once: `./mvnw -q package` (makes `target/bsg.jar`).
   The `./bsg` script finds Java 21 by itself (JAVA_HOME, macOS's
   `java_home`, Homebrew's `openjdk@21`).
2. In the web UI, **Persönliche Tokens**: create a token (password
   confirmation), copy it. It is shown once and is valid for 90 days.
3. Store it so only you can read it:

   ```sh
   mkdir -p ~/.config/blindensport
   pbpaste > ~/.config/blindensport/token && chmod 600 ~/.config/blindensport/token
   ```

   Or set `BSG_TOKEN` for one session. Never pass it as an argument.

## Windows

Works the same in the Command Prompt or PowerShell, with `bsg.bat` instead
of `./bsg`. GitHub tests it on Windows on every change (workflow
*bsg Tests*).

1. Java 21, e.g. `winget install EclipseAdoptium.Temurin.21.JDK`, and
   `JAVA_HOME` pointing to it (the Temurin installer can set it).
2. Build once in the `cli` folder: `mvnw.cmd -q package`.
3. Store the token in your profile folder (only you can read it there), in
   PowerShell, right after copying it:

   ```powershell
   New-Item -ItemType Directory -Force "$HOME\.config\blindensport" | Out-Null
   Get-Clipboard | Set-Content -NoNewline "$HOME\.config\blindensport\token"
   ```

   Or for one session: `set BSG_TOKEN=bsg_mcp_…` (cmd) or
   `$env:BSG_TOKEN = "bsg_mcp_…"` (PowerShell).
4. `bsg.bat whoami`, `bsg.bat accounts list`, … as below.

Messages use only characters every Windows console code page has (umlauts
yes, typographic quotes no), so screen readers such as NVDA read them as
written.

## Commands

```sh
./bsg whoami                                   # who the token belongs to, permissions
./bsg accounts list                            # all accounts: role, approval, blocked
./bsg accounts set-role anna@example.org coach # member | coach | admin | root | none
./bsg members list [Suche] [--status new]      # roster by last name, never protected data
./bsg members import roster.json               # create or fully overwrite (by id)
./bsg members import roster.json --fill        # only fill blank fields (match by name)
```

Every command takes `--json` (the server's answer as JSON) and
`--url https://…` (default `BSG_URL`, else https://bs.a11y.it; plain http
only for localhost, e.g. a local web UI on http://127.0.0.1:8080).

Exit codes: 0 done, 1 refused or failed (the server's reason is printed),
2 setup or usage problem.

## What a token can't do

As on the token page: it never reads protected member data (SVNR, IBAN,
birth date, health) and never deletes entries. Writing protected fields in
an import still works with `members.private.write`. The role rules are the
database's: no self-change, the last root stays.

If no root account can sign in at all, `bsg` can't help either; see
`supabase/scripts/emergency-root.sql`.

## Tests

`./mvnw test` (WireMock stands in for the web UI).
