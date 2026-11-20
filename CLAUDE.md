# OpenWolf

@.wolf/OPENWOLF.md

This project uses OpenWolf for context management (protocol imported above).


# Project

Club app for Blindensport Graz: tournaments, trainings, teams and memberships, member and account administration.
Two front ends share one Supabase backend: the SwiftUI iOS app (`BlindensportGraz/`) and the web UI (`webui/`, Quarkus + Vaadin).

## Framework
SwiftData is a local offline cache only (no CloudKit/iCloud); accounts, roles and club data live in Supabase and sync via `SupabaseSync`.
Events are visible to every signed-in user; everything else follows the user's role permissions (see BlindensportGraz/CLAUDE.md, Role Hierarchy).

