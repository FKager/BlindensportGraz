# Fixing the CI provisioning profile (Push Notifications capability)

Context: `iOS Device Deploy` (`.github/workflows/ios-device-deploy.yml`) fails
at the "Build for device" step with:

```
error: Provisioning profile "iOS Team Provisioning Profile: it.a11y.BlindensportGraz"
       doesn't include the Push Notifications capability.
error: Provisioning profile "iOS Team Provisioning Profile: it.a11y.BlindensportGraz"
       doesn't include the aps-environment entitlement.
```

Root cause: `BlindensportGraz.entitlements` gained `aps-environment` (Push
Notifications) in commit `8d3e500` ("Push notifications for team members when
a Training/Tournament is created"). That requires the App ID's Push
Notifications capability to be enabled in the Apple Developer Portal, plus a
provisioning profile that includes it. The CI workflow signs with a static,
pre-harvested `.mobileprovision` stored in the `IOS_CI_PROVISIONING_PROFILE_BASE64`
GitHub secret — it predates the push-notification feature and was never
regenerated, so it's now stale. See `.wolf/buglog.json` bug-198.

Both steps below can be done from a **Windows terminal** — the Developer
Portal is just a website (any browser, any OS), and `gh` + PowerShell handle
the encode-and-upload step natively on Windows too. No Mac/Xcode required.

## Part 1 — Apple Developer Portal (browser, any OS)

**1. Confirm/enable the capability on the App ID**
- Go to https://developer.apple.com/account/resources/identifiers/list, sign in.
- Click `it.a11y.BlindensportGraz`.
- Scroll to Capabilities, make sure **Push Notifications** is checked. (It may
  already be checked if it was turned on when the push-notification code was
  written — only the *profile* is stale. Check anyway.)
- Save if you changed anything.

**2. Generate a fresh Development provisioning profile**
- Go to https://developer.apple.com/account/resources/profiles/list.
- Click **+** to create a new profile → under Development, choose **iOS App
  Development** → Continue.
- App ID: `it.a11y.BlindensportGraz` → Continue.
- Certificates: select the **Apple Development** certificate this project
  already uses (the one whose `.p12` was harvested onto the CI keychain —
  same one Xcode shows locally as "Apple Development: `<your name>` (…)").
  If unsure, select all available Apple Development certs.
- Devices: make sure **iPhone von Franz** is checked (it should already be
  registered, since deploys worked before).
- Name it something identifiable, e.g. `BlindensportGraz CI Development` →
  **Generate**.
- **Download** the `.mobileprovision` file.

## Part 2 — Windows terminal (PowerShell)

Requires the `gh` CLI installed and authenticated
(`winget install GitHub.cli` then `gh auth login`, if not already set up).

**Two gotchas hit on the first attempt (2026-08-04, see `.wolf/buglog.json`
bug-198 update) — both are fixed by the command below, worth knowing why:**

1. `gh secret set` has **no `--body-file` flag** (only `-b/--body <string>`
   or reading from stdin) — despite it looking like the obvious option, it
   doesn't exist and errors out on Windows' `gh`.
2. PowerShell's `Set-Content` defaults to UTF-8 **with a BOM** (3 extra bytes
   at the start of the file). Those bytes aren't valid base64, and macOS's
   `base64 --decode` (which the CI workflow runs) fails immediately with
   `base64: stdin: (null): error decoding base64 input stream`.

Piping the base64 string straight into `gh secret set`'s stdin — never
writing it to a file at all — sidesteps both:

```powershell
$bytes = [System.IO.File]::ReadAllBytes("C:\Users\<you>\Downloads\BlindensportGraz_CI_Development.mobileprovision")
[Convert]::ToBase64String($bytes) | gh secret set IOS_CI_PROVISIONING_PROFILE_BASE64 --repo FKager/BlindensportGraz
```

No macOS, no Xcode, no local build tools required for either step.

## After updating the secret

Re-trigger the workflow to confirm the fix:

```powershell
gh workflow run "iOS Device Deploy" --repo FKager/BlindensportGraz
```

or ask Claude Code (on the Mac session) to trigger and watch it.
