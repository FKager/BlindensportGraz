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
2. Check whether local `main` is ahead of `origin/main`:
   `git rev-list origin/main..main --count`.
   - If it's ahead, push (`git push origin main`) and rely on that push to
     trigger the workflow — do NOT also call `gh workflow run` afterward.
     The workflow's `on: push: branches: [main]` trigger already fires for
     every push, so triggering it again manually spawns a second, redundant
     concurrent run against the same physical device (confirmed 2026-08-07:
     this produced two near-simultaneous runs that both failed for the same
     reason — a locked phone screen — generating two separate GitHub
     failure-notification emails for what was really one issue). The user
     explicitly asked to stop double-triggering; don't reintroduce it.
   - If it's NOT ahead (nothing new to push, e.g. redeploying the exact same
     already-pushed commit), a push won't happen and so won't trigger
     anything — in that case `gh workflow run "iOS Device Deploy"` is the
     only way to fire a new run, so use it.
3. Find the run that just started and watch it to completion:
   `gh run list --workflow "iOS Device Deploy" --limit 1`
   `gh run watch <run-id> --exit-status`
   (Give the push-triggered run a few seconds to register in the run list
   before querying — it's not instantaneous.)
4. Report pass/fail to the user. On failure, pull the failing step's log
   (`gh run view <run-id> --log-failed`) and summarize the actual error —
   don't just say "it failed."

If `gh run watch` shows the job stuck in "queued" for more than a minute or two,
the self-hosted runner's launchd service may be down — check with
`launchctl list | grep actions.runner` before assuming a workflow problem.
