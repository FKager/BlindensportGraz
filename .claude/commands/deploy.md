---
description: Deploy BlindensportGraz to the iPhone via the self-hosted GitHub Actions workflow (never local Xcode/devicectl)
---

Deploy to "iPhone von Franz" using the **`iOS Device Deploy`** GitHub Actions workflow
(`.github/workflows/ios-device-deploy.yml`), which runs on the self-hosted runner
registered on this same Mac. This is the user's explicitly preferred deploy path —
do NOT build/install locally via Xcode's Run action, raw `xcodebuild`, or
`xcrun devicectl device install/process launch` as a substitute. Those were used
before this command existed and turned out fragile (Xcode's Cmd+R silently not
reaching the device, sandboxed `xcodebuild` hitting `errSecInternalComponent`
codesigning failures) — the workflow's ephemeral CI keychain avoids both problems.

Steps:

1. `git status` — if there are uncommitted changes, STOP and tell the user to
   commit first. Do not auto-commit (only commit when explicitly asked).
2. Make sure what you want on the phone is pushed, then start the run. The
   workflow is manual only (2026-11-07): a push never deploys, because the
   Debug build talks to staging and would replace the TestFlight app. For
   `main`: `gh workflow run "iOS Device Deploy"`. For a branch:
   `gh workflow run "iOS Device Deploy" --ref <branch>`. Start it once.
3. Find the run that just started and watch it to completion:
   `gh run list --workflow "iOS Device Deploy" --limit 1`
   `gh run watch <run-id> --exit-status`
   (Give the run a few seconds to register in the run list before querying —
   it's not instantaneous.)
4. Report pass/fail to the user. On failure, pull the failing step's log
   (`gh run view <run-id> --log-failed`) and summarize the actual error —
   don't just say "it failed."

If `gh run watch` shows the job stuck in "queued" for more than a minute or two,
the self-hosted runner's launchd service may be down — check with
`launchctl list | grep actions.runner` before assuming a workflow problem.
