# Build & deploy commands used (iPhone von Franz)

What I actually ran to get the current build onto your iPhone, and what those
commands trigger under the hood.

## What I ran

```bash
# 1. Trigger a fresh run of the iOS Device Deploy workflow for the current
#    HEAD on main (self-hosted runner on this Mac, not GitHub's cloud runners
#    — see .github/workflows/ios-device-deploy.yml's header comment for why).
gh workflow run "iOS Device Deploy"

# 2. Find the run that was just triggered.
gh run list --workflow "iOS Device Deploy" --limit 1

# 3. Watch it to completion (blocks until success/failure).
gh run watch <run-id> --exit-status
```

That's the whole deploy skill's flow (`.claude/commands/deploy.md` /
`/deploy`): I don't build or install anything locally myself — no local
`xcodebuild`, no Xcode Run button, no `xcrun devicectl` from this session.
Those were the old approach and turned out fragile (sandboxed `xcodebuild`
hits `errSecInternalComponent` codesigning failures in this environment,
Xcode's Cmd+R can silently not reach the device). The workflow's ephemeral
CI keychain avoids both.

## What the workflow itself runs (on the self-hosted runner)

`.github/workflows/ios-device-deploy.yml`, step by step:

```bash
# Regenerate the Xcode project from project.yml
xcodegen generate

# Build an ephemeral CI keychain (not the Mac's login keychain) and import
# the signing cert into it — details in the workflow file's own comments
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" -P "$IOS_CI_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# Install the .mobileprovision for it.a11y.BlindensportGraz
security cms -D -i "$PP_PATH" > "$RUNNER_TEMP/decoded_profile.plist"
cp "$PP_PATH" ~/Library/MobileDevice/"Provisioning Profiles"/"$PROFILE_UUID".mobileprovision

# Force Manual signing + the freshly-installed profile on just the app
# target (via a small `xcodeproj` Ruby script, not a plain xcodebuild flag)

# The actual build
xcodebuild build \
  -project BlindensportGraz.xcodeproj \
  -scheme BlindensportGraz \
  -configuration Debug \
  -destination "id=BD764E6D-F84C-5BC9-B52C-BB372A7B3190" \
  -derivedDataPath "$RUNNER_TEMP/build" \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM="5Q57Y9YT8J" \
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH"

# Install + launch on your iPhone
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE_ID" it.a11y.BlindensportGraz

# Delete the ephemeral keychain again
security delete-keychain "$KEYCHAIN_PATH"
```

`BD764E6D-F84C-5BC9-B52C-BB372A7B3190` is the CoreDevice id for "iPhone von
Franz" (`env.DEVICE_ID` in the workflow file).

## This run

- Trigger: https://github.com/FKager/BlindensportGraz/actions/runs/31128418944
- Result: all steps succeeded (`Build for device` and `Install and launch on
  device` both green), total run time 29s.
