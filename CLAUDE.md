# OpenWolf

@.wolf/OPENWOLF.md

This project uses OpenWolf for context management (protocol imported above).


# Project

Club app for Blindensport Graz: tournaments, trainings, teams and memberships, member and account administration.
Two front ends share one Supabase backend: the SwiftUI iOS app (`BlindensportGraz/`) and the web UI (`webui/`, Quarkus + Vaadin).

## Framework
SwiftData is a local offline cache only (no CloudKit/iCloud); accounts, roles and club data live in Supabase and sync via `SupabaseSync`.
Events are visible to every signed-in user; everything else follows the user's role permissions (see BlindensportGraz/CLAUDE.md, Role Hierarchy).


## Accessibility audits (hooks)
`scripts/a11y-audit.sh` runs the audits for what differs from origin/main: the iOS XCUITest audit (BlindensportGrazUITests) in light and dark mode when the app changed, the web UI axe check (webui/a11y) against local Supabase when webui/ changed. It runs from the git pre-push hook (`.githooks/pre-push`; activate once per clone with `git config core.hooksPath .githooks`, skip once with `--no-verify`) and from the Claude Code Stop hook (`.claude/settings.json`; findings come back to Claude, exit 2). A passing state is remembered in `.git/a11y-audit/`, so the same files aren't audited twice; `--force`, `--ios`, `--web` run it by hand.
