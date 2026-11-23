#!/bin/bash
# Accessibility audits for what changed, used by two hooks:
#   .githooks/pre-push            → scripts/a11y-audit.sh --pre-push
#   Claude Code Stop hook         → scripts/a11y-audit.sh --claude
# and by hand:                      scripts/a11y-audit.sh [--ios] [--web] [--force]
#
# iOS (BlindensportGraz/, BlindensportGrazUITests/, project.yml changed):
#   the XCUITest accessibility audits (BlindensportGrazUITests) in the
#   Simulator, light AND dark mode, German / Austria / Vienna time like CI.
# Web UI (webui/, supabase/migrations, supabase/seed.sql changed):
#   axe-core over every page (webui/a11y/axe_check.py) against local
#   Supabase (seed root + webui/a11y/sample-data.sql, which stays in the
#   local database) and the web UI container on port 8091.
#
# "Changed" = differs from origin/main (commits, uncommitted and untracked
# files). A passing state is remembered (.git/a11y-audit/), so the second
# hook doesn't repeat an audit the first already passed for the same files.
#
# Exit codes: 0 passed / nothing to do; 1 findings (pre-push, by hand);
# 2 findings in --claude mode (stderr goes back to Claude to fix).
# Skip once: git push --no-verify, or A11Y_AUDIT_SKIP=1.

set -uo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT" || exit 0
STATE="$(git rev-parse --git-dir)/a11y-audit"
mkdir -p "$STATE"

MODE=manual WANT_IOS=0 WANT_WEB=0 FORCE=0
for arg in "$@"; do
    case "$arg" in
        --claude) MODE=claude ;;
        --pre-push) MODE=pre-push ;;
        --ios) WANT_IOS=1 ;;
        --web) WANT_WEB=1 ;;
        --force) FORCE=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 64 ;;
    esac
done
# Hooks get JSON (Claude) or ref lines (git) on stdin; not needed here.
[ "$MODE" != manual ] && cat >/dev/null

[ "${A11Y_AUDIT_SKIP:-0}" = 1 ] && exit 0

IOS_PATHS=(BlindensportGraz BlindensportGrazUITests project.yml)
WEB_PATHS=(webui supabase/migrations supabase/seed.sql)

log() { echo "[a11y-audit] $*" >&2; }

# Files that differ from origin/main: committed, uncommitted or untracked.
changed_files() {
    local base
    base=$(git merge-base origin/main HEAD 2>/dev/null || echo HEAD)
    { git diff --name-only "$base" -- "$@"; git ls-files -o --exclude-standard -- "$@"; } | sort -u
}

# Content hash of the area's files as they are on disk now.
area_hash() {
    git ls-files -z -co --exclude-standard -- "$@" | xargs -0 shasum 2>/dev/null | shasum | cut -c1-40
}

# Decide per area: run if asked, or if it changed and this state hasn't passed yet.
decide() { # name, paths...
    local name=$1; shift
    local hash; hash=$(area_hash "$@")
    echo "$hash" > "$STATE/$name.current"
    if [ "$FORCE" = 0 ] && [ -f "$STATE/$name.pass" ] && [ "$(cat "$STATE/$name.pass")" = "$hash" ]; then
        return 1
    fi
    return 0
}

RUN_IOS=0 RUN_WEB=0
if [ "$WANT_IOS" = 1 ] || [ "$WANT_WEB" = 1 ]; then
    [ "$WANT_IOS" = 1 ] && RUN_IOS=1
    [ "$WANT_WEB" = 1 ] && RUN_WEB=1
else
    [ -n "$(changed_files "${IOS_PATHS[@]}")" ] && RUN_IOS=1
    [ -n "$(changed_files "${WEB_PATHS[@]}")" ] && RUN_WEB=1
fi
[ "$RUN_IOS" = 1 ] && { decide ios "${IOS_PATHS[@]}" || RUN_IOS=0; }
[ "$RUN_WEB" = 1 ] && { decide web "${WEB_PATHS[@]}" || RUN_WEB=0; }
[ "$RUN_IOS" = 0 ] && [ "$RUN_WEB" = 0 ] && exit 0

# Claude: a state that already failed once is not reported again (no endless
# Stop loop); the user sees a note instead, and the pre-push hook still gates.
if [ "$MODE" = claude ]; then
    repeat=1
    for a in ios web; do
        var="RUN_$(echo $a | tr a-z A-Z)"
        if [ "${!var}" = 1 ]; then
            if [ ! -f "$STATE/$a.fail" ] || [ "$(cat "$STATE/$a.fail")" != "$(cat "$STATE/$a.current")" ]; then repeat=0; fi
        fi
    done
    if [ "$repeat" = 1 ]; then
        echo '{"systemMessage": "Accessibility audit: the findings reported before are still open (unchanged files). The pre-push hook will block until they are fixed."}'
        exit 0
    fi
fi

# One audit at a time (Simulator, port 8091).
LOCK="$STATE/lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    if [ -f "$LOCK/pid" ] && kill -0 "$(cat "$LOCK/pid")" 2>/dev/null; then
        if [ "$MODE" = claude ]; then
            echo '{"systemMessage": "Accessibility audit skipped: another audit is running."}'
            exit 0
        fi
        log "waiting for the running audit (pid $(cat "$LOCK/pid"))…"
        while [ -d "$LOCK" ]; do sleep 5; done
        mkdir "$LOCK" 2>/dev/null || true
    else
        rm -rf "$LOCK"; mkdir "$LOCK"
    fi
fi
echo $$ > "$LOCK/pid"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/a11y-audit.XXXXXX")
cleanup() { rm -rf "$LOCK" "$WORK"; docker rm -f bsg-webui-a11y >/dev/null 2>&1 || true; }
trap cleanup EXIT

FINDINGS="$WORK/findings.txt"
: > "$FINDINGS"

# ---------------------------------------------------------------- iOS
audit_ios() {
    command -v xcodebuild >/dev/null || { log "no xcodebuild, iOS audit skipped"; return 0; }
    local device=${A11Y_SIMULATOR_ID:-}
    if [ -z "$device" ]; then
        device=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devs = [d for k, v in json.load(sys.stdin)["devices"].items() if "iOS" in k for d in v if d["name"].startswith("iPhone")]
booted = [d for d in devs if d["state"] == "Booted"]
print((booted or devs or [{"udid": ""}])[0]["udid"])')
    fi
    [ -z "$device" ] && { echo "iOS: no iPhone Simulator available" >> "$FINDINGS"; return 1; }
    log "iOS audit on Simulator $device (light + dark, ~10 min)…"
    xcrun simctl boot "$device" >/dev/null 2>&1 || true
    local before; before=$(xcrun simctl ui "$device" appearance 2>/dev/null || echo light)
    xcrun simctl ui "$device" content_size large >/dev/null 2>&1 || true
    command -v xcodegen >/dev/null && xcodegen generate -q >/dev/null 2>&1
    local failed=0
    for appearance in light dark; do
        xcrun simctl ui "$device" appearance "$appearance"
        local out="$WORK/ios-$appearance.log"
        TEST_RUNNER_TZ=Europe/Vienna xcodebuild test -project BlindensportGraz.xcodeproj -scheme BlindensportGraz \
            -destination "id=$device" -testLanguage de -testRegion AT \
            -only-testing:BlindensportGrazUITests > "$out" 2>&1
        local status=$?
        if grep -qE "\.swift:[0-9]+:[0-9]+: error" "$out"; then
            { echo "iOS build failed ($appearance):"; grep -E "\.swift:[0-9]+:[0-9]+: error" "$out" | sort -u | head -10; } >> "$FINDINGS"
            failed=1; break
        fi
        if [ $status -ne 0 ]; then
            failed=1
            {
                echo "iOS audit, $appearance mode:"
                grep "A11Y-ISSUE" "$out" | grep -v "XCTAssert\|error:" | sed 's/.*A11Y-ISSUE | /  /' | sort -u
                # Non-audit failures (screen not reached, element missing, crash).
                grep -E "error: -\[" "$out" | grep -v "A11Y-ISSUE" | sed 's/^.*error: /  /' | cut -c1-240 | sort -u
                grep -q "A11Y-ISSUE\|error: -\[" "$out" || tail -15 "$out" | sed 's/^/  /'
            } >> "$FINDINGS"
        fi
    done
    xcrun simctl ui "$device" appearance "$before" >/dev/null 2>&1 || true
    return $failed
}

# ---------------------------------------------------------------- Web UI
audit_web() {
    command -v docker >/dev/null || { log "no docker, web audit skipped"; return 0; }
    command -v supabase >/dev/null || { log "no supabase CLI, web audit skipped"; return 0; }
    [ -f webui/a11y/axe_check.py ] || { log "no webui/a11y/axe_check.py on this branch, web audit skipped"; return 0; }
    log "web UI axe check (local Supabase + container, ~3 min)…"
    local venv="$HOME/.cache/blindensport-a11y/venv" req=webui/a11y/requirements.txt
    if [ ! -x "$venv/bin/python" ] || ! cmp -s "$req" "$venv/requirements.txt"; then
        python3 -m venv "$venv" && "$venv/bin/pip" install -q --disable-pip-version-check -r "$req" && "$venv/bin/playwright" install chromium >/dev/null \
            && cp "$req" "$venv/requirements.txt" \
            || { echo "web: could not install Playwright/axe ($req)" >> "$FINDINGS"; return 1; }
    fi
    if ! supabase status >/dev/null 2>&1; then
        log "starting local Supabase…"
        SUPABASE_AUTH_EXTERNAL_APPLE_SECRET=${SUPABASE_AUTH_EXTERNAL_APPLE_SECRET:-unused} \
            supabase start -x studio,imgproxy,logflare,vector,supavisor,realtime,edge-runtime,postgres-meta,mailpit >/dev/null \
            || { echo "web: local Supabase did not start" >> "$FINDINGS"; return 1; }
    fi
    local db; db=$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -1)
    if [ -z "$(docker exec "$db" psql -U postgres -tAc "select 1 from auth.users where email='root@example.test'" 2>/dev/null)" ]; then
        echo "web: local Supabase has no seed root (root@example.test); run 'supabase db reset' (wipes local data)" >> "$FINDINGS"
        return 1
    fi
    # Sample rows (fixed ids, idempotent) so tables and reports have content.
    docker exec -i "$db" psql -U postgres -v ON_ERROR_STOP=1 -q < webui/a11y/sample-data.sql > "$WORK/web-data.log" 2>&1 \
        || { { echo "web: sample data failed:"; tail -5 "$WORK/web-data.log"; } >> "$FINDINGS"; return 1; }
    local anon service
    anon=$(supabase status -o env 2>/dev/null | sed -n 's/^ANON_KEY="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')
    service=$(supabase status -o env 2>/dev/null | sed -n 's/^SERVICE_ROLE_KEY="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')
    docker build -q -t bsg-webui-a11y webui/ > "$WORK/web-build.log" 2>&1 \
        || { { echo "web: docker build failed:"; tail -15 "$WORK/web-build.log"; } >> "$FINDINGS"; return 1; }
    docker rm -f bsg-webui-a11y >/dev/null 2>&1
    docker run -d --name bsg-webui-a11y -p 8091:8080 \
        -e SUPABASE_URL=http://host.docker.internal:54321 -e SUPABASE_ANON_KEY="$anon" \
        -e SUPABASE_SERVICE_KEY="$service" -e SESSION_COOKIE_SECURE=false bsg-webui-a11y >/dev/null
    local i
    for i in $(seq 60); do curl -sf -o /dev/null http://127.0.0.1:8091/ && break; sleep 2; done
    if ! "$venv/bin/python" webui/a11y/axe_check.py http://127.0.0.1:8091 root@example.test localroot123 > "$WORK/web.log" 2>&1; then
        { echo "web UI axe check:"; grep -E "^FAIL|Error|error" "$WORK/web.log" | head -30 | sed 's/^/  /'; } >> "$FINDINGS"
        return 1
    fi
    return 0
}

result=0
if [ "$RUN_IOS" = 1 ]; then
    if audit_ios; then cp "$STATE/ios.current" "$STATE/ios.pass"; rm -f "$STATE/ios.fail"
    else cp "$STATE/ios.current" "$STATE/ios.fail"; result=1; fi
fi
if [ "$RUN_WEB" = 1 ]; then
    if audit_web; then cp "$STATE/web.current" "$STATE/web.pass"; rm -f "$STATE/web.fail"
    else cp "$STATE/web.current" "$STATE/web.fail"; result=1; fi
fi

if [ $result = 0 ]; then
    log "passed ($( [ "$RUN_IOS" = 1 ] && echo -n "iOS light+dark ")$( [ "$RUN_WEB" = 1 ] && echo -n "web axe"))"
    exit 0
fi
{
    echo "Accessibility audit found problems. Fix them (or, for a deliberate exception, add a proven exemption:"
    echo "BlindensportGrazUITests/XCUIApplication+Audit.swift, webui/a11y/accepted.txt):"
    cat "$FINDINGS"
} >&2
[ "$MODE" = claude ] && exit 2
exit 1
