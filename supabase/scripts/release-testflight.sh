#!/bin/zsh
# Tags main as <version>, waits for the TestFlight upload (iOS Build and
# Deploy workflow), then gives the build German What-to-Test notes and assigns
# it to the Internal group — the workflow uploads but does not distribute.
#
# Usage: supabase/scripts/release-testflight.sh v0.3.1 "What-to-Test text (de)"
set -euo pipefail
cd "$(dirname "$0")/../.."

VERSION=${1:?usage: $0 <vX.Y.Z> "<notes>"}; NOTES=${2:?missing notes}
GROUP=d1482359-274f-4cb2-95c3-cefbc4a67b95   # TestFlight group "Internal"

git fetch -q origin main --tags
if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
  echo "Tag $VERSION exists already — not re-tagging." >&2
else
  git tag -a "$VERSION" origin/main -m "$VERSION"
  git push -q origin "$VERSION"
  echo "Tagged $VERSION at $(git rev-parse --short origin/main)." >&2
fi

find_run() {
  gh run list --workflow "iOS Build and Deploy" --limit 10 \
    --json databaseId,headBranch -q ".[] | select(.headBranch == \"$VERSION\") | .databaseId" | head -1
}
echo "Waiting for the workflow run…" >&2
run=""
for _ in {1..12}; do
  run=$(find_run); [[ -n $run ]] && break
  sleep 5
done
if [[ -z $run ]]; then
  # A tag on a commit whose message contains [skip ci] triggers nothing on
  # push — start the workflow on the tag by hand (deploy job: refs/tags/v*).
  echo "No push-triggered run (e.g. [skip ci] in the commit message) — dispatching on $VERSION." >&2
  gh workflow run "iOS Build and Deploy" --ref "$VERSION"
  for _ in {1..24}; do
    sleep 5; run=$(find_run); [[ -n $run ]] && break
  done
fi
[[ -n $run ]] || { echo "No workflow run for $VERSION found." >&2; exit 1; }
echo "Run $run" >&2
gh run watch "$run" --exit-status >/dev/null || {
  echo "Run $run failed:" >&2; gh run view "$run" --log-failed | tail -30 >&2; exit 1; }

build=$(gh run view "$run" --log | grep -oE "Delivery UUID: [0-9a-f-]{36}" | head -1 | awk '{print $3}')
[[ -n $build ]] || { echo "No Delivery UUID in the run log — assign by hand (asc builds list --app 6807475637)." >&2; exit 1; }
echo "Build $build uploaded; waiting for App Store Connect processing…" >&2

# The group needs a VALID build: notes are accepted earlier, while it's still
# processing, so they can't be the signal to go ahead. Waits by build number
# (the workflow's run number): right after the upload the Delivery UUID isn't a
# build yet, so waiting on it fails at once.
number=$(gh run view "$run" --json number -q .number)
if ! asc builds wait --app 6807475637 --build-number "$number" --platform IOS \
    --timeout 30m --poll-interval 30s >/dev/null; then
  echo "Build still processing or failed — re-run this script later (it won't re-tag)." >&2
  exit 1
fi
# Fails on a re-run, when the notes are there already.
asc builds test-notes create --build-id "$build" --locale de-DE --whats-new "$NOTES" >/dev/null 2>&1 \
  || echo "Notes not created — they may exist already." >&2
asc builds add-groups --build-id "$build" --group "$GROUP"
echo "$VERSION (build $build) is in the Internal group with notes." >&2
