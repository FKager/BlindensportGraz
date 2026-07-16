# RootCLI

A command-line tool that talks directly to the `iCloud.it.a11y.BlindensportGraz`
CloudKit container's public database — outside the app entirely — to change a
user's `role` or `isRoot` flag. It authenticates as a **Server-to-Server (S2S)**
client using an ECDSA key pair registered in CloudKit Dashboard, the same
mechanism Apple documents for backend integrations.

This exists because the app itself deliberately has no way for a user to change
their own role, and no in-app way to grant the first `admin`/root account either
— see `Models.swift`'s `User.isRoot` doc comment. RootCLI is the out-of-band
escape hatch for that, and (once you do the one-time Dashboard step below) it
becomes the *only* way to write those fields at all, closing the gap where any
app client could otherwise forge a CloudKit `UserIdentity` record.

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
   and grant your new `RootAdmin` role **Read/Write**.
4. Repeat for the **Production** environment once you're ready to promote there
   (Development and Production schemas/roles are configured separately).

If you'd rather script this than click through the UI, `cktool` (bundled with
Xcode, at `xcrun cktool`) can export/import the schema as a `.ckdb` file
(`cktool export-schema`, edit the `SECURITY ROLES` section, `cktool
import-schema`) — but hand-verify the diff before importing, a bad schema
import can lock out legitimate writes too.

### 4. Build RootCLI

```bash
cd RootCLI
swift build -c release
```

The binary is at `.build/release/rootcli`.

## Usage

```bash
export CLOUDKIT_KEY_ID=<key id from step 2>
export CLOUDKIT_PRIVATE_KEY_PATH=~/.config/rootcli/rootcli_private_key_pkcs8.pem
export CLOUDKIT_ENVIRONMENT=development   # or production
# CLOUDKIT_CONTAINER defaults to iCloud.it.a11y.BlindensportGraz

rootcli list
rootcli set-role someuser admin
rootcli set-root someuser true
```

`list` prints every `UserIdentity` record as a table — name, username, role,
whether it's root, and an explicit note that email is *not* included, because
it's never synced to CloudKit (see the top of `CloudKitS2SClient.swift`). If
you need email addresses too, that requires deliberately publishing them
(currently not done, on purpose — ask before changing this, it's a privacy
tradeoff, not just a missing feature).

`set-role`/`set-root` match by username, display name, or record id
(case-insensitive) and refuse to guess if more than one account matches —
re-run with the exact id from `list` in that case.

Changes made this way reach app instances the same way any other cross-device
change does: on next login or pull-to-refresh, via `CloudKitSync.syncAll`.
