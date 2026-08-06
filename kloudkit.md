# Getting CLOUDKIT_KEY_ID

Apple doesn't expose Server-to-Server key management (creating/listing/
retrieving Key IDs) through any CLI, including `xcrun cktool`. Its full
subcommand list is `export-schema`, `import-schema`, `validate-schema`,
`reset-schema`, `create-record`, `query-records`, `delete-record(s)`,
`get-teams`, `save-token`/`remove-token` — nothing for API Access /
Server-to-Server keys. That part is Dashboard-only.

## Getting `CLOUDKIT_KEY_ID` (web UI, no CLI shortcut)

1. Go to the [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)
   and sign in with the Apple ID on team `5Q57Y9YT8J` (per `fastlane/Appfile`).
2. Select container **`iCloud.it.a11y.BlindensportGraz`**.
3. Pick the environment at the top — use **Development** (the app on the
   iPhone is a Debug build installed directly via Xcode/devicectl, which
   talks to Development, not Production).
4. Left sidebar → **API Access** → **Server-to-Server Keys**.
5. If a key is already listed there, click it — the **Key ID** is shown on
   its detail page. If none exists yet, **Add Key** and paste the contents
   of `~/.config/rootcli/rootcli_public_key.pem` (already generated on this
   Mac per `RootCLI/README.md` step 1 — the matching private key is at
   `~/.config/rootcli/rootcli_private_key_pkcs8.pem`). Submitting generates
   the Key ID immediately.

That Key ID is what goes in `CLOUDKIT_KEY_ID`, used like:

```bash
export CLOUDKIT_KEY_ID=<key id from step 5>
export CLOUDKIT_PRIVATE_KEY_PATH=~/.config/rootcli/rootcli_private_key_pkcs8.pem
export CLOUDKIT_ENVIRONMENT=development
cd RootCLI && .build/release/rootcli record list ClubMember
```

## Faster alternative for a one-off lookup: `cktool query-records`

`cktool` has its own `query-records` command that skips the whole
RootCLI/S2S-key setup entirely. It uses a different, simpler credential — an
interactive **management token**, not a registered key pair:

```bash
xcrun cktool save-token --type management
```
(prompts for a token generated at the CloudKit Dashboard → account menu →
**CloudKit Console Tokens** — this token is scoped to your Apple ID, not
per-container)

```bash
xcrun cktool get-teams
```
gives the `--team-id` (should resolve to `5Q57Y9YT8J`), then:

```bash
xcrun cktool query-records \
    --team-id 5Q57Y9YT8J \
    --container-id iCloud.it.a11y.BlindensportGraz \
    --environment development \
    --database-type public \
    --record-type ClubMember
```

This prints every `ClubMember` record directly — no `CLOUDKIT_KEY_ID`, no
rebuilding `rootcli` needed.
