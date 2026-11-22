# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Blindensport Graz** is a SwiftUI iOS app for managing sport events organized for visually impaired athletes. The app helps organize tournaments, trainings, team memberships, and event participations for sports like Torball, Goalball, Blindenfußball, Showdown, Judo, Athletics, Swimming, Skiing, and Cycling.

## Architecture

### Folder Layout
Sources are grouped by feature (XcodeGen picks up subfolders; run `xcodegen generate` after adding files):

- `App/` — app entry, `RootView`/`MainTabView`, App Intents, server config
- `Models/` — one `@Model` per file, `ModelSchema`, role/sport enums
- `Services/` — `*Service` persistence/business logic, `PersistenceService`
- `Sync/` — sync state, outbox (`PendingPush`), network/push; `Sync/Supabase/` — `SupabaseSync` (+`+Models`), `SupabaseRows` (`*DBRow` mapping)
- `Features/<Feature>/` — views + feature-specific import/export (Dashboard, Events, Tournaments, Trainings, Teams, Members, Account, Attendance, Budget, Welcome, Backup)
- `Features/Reports/<Report>/` — Prae, KostZ, Sammelabrechnung, Trainingsfrequenzliste, Teilnehmerliste (+ shared `XLSXCellPatch`)
- `Shared/` — theme, icons, validation, files shared with the widget/share extensions (paths referenced in `project.yml`)
- `Resources/` — asset catalog, `Localizable.xcstrings`, `.xlsx` templates
- Root: `Info.plist`, entitlements, this file (excluded from the app bundle in `project.yml`)

### Core Models (`Models/`)
All data models use SwiftData's `@Model` protocol as a local offline cache (no CloudKit mirroring); `SupabaseSync` pulls/pushes them to Supabase with RLS:

- **User**: App accounts with email, display name, and role (member/coach/admin)
- **Member**: Club roster entry (address, contact info, membership number) — distinct from `User`
- **Team**: Sport teams with name, sport type, description, and membership list
- **TeamMembership**: Link between users and teams with roles (player/coach/assistant)
- **SportEvent**: Base class for events/tournaments with title, sport, location, date range, participations
- **Tournament**: Competitions with venue, maxTeams count, status (planned/ongoing/finished)
- **Training**: Training sessions with focus area, duration, location
- **TrainingFavorite**: Saved recurring-training templates (title, sport, weekday, time range)
- **Attendance**: Links a `TeamMembership` to a `SportEvent` with an attended flag and optional PRAE amount
- **EventImage**: Photo attached to a `SportEvent` (or, via inheritance, a `Training`/`Tournament`)
- **EventParticipation**: Link between users and events with status (invited/confirmed/declined)

The `ModelContainer` is built in `App/BlindensportGrazApp.swift` from `ModelSchema.schema` (`Models/ModelSchema.swift`), the single list of every model type; register new models there.

### Application Structure
```
RootView -> Login/Registration (if not authenticated) -> MainTabView
MainTabView -> TabView (Übersicht, Events, Turniere, Trainings, Verein, Account)
```

Each tab uses `@Query` for data fetching from SwiftData and displays different views:

1. **Features/Dashboard/**: Overview dashboard with stats cards and upcoming items
2. **Features/Events/**: Event management (create/edit/delete events)
3. **Features/Tournaments/**: Tournament management (list, details, create)
4. **Features/Trainings/**: Training session management
5. **Features/Teams/**: Team management, member assignments, and the admin "Verein" hub
6. **Features/Account/**: Login/registration, user profile and account settings

One SwiftUI view type per file, named after the type (e.g. `TrainingDetailView.swift`); small `private` helper types stay in the file of the view that uses them.

### Data Flow Pattern
Views read with `@Query`. Writes go through the matching `*Service` in `Services/`, which saves locally and queues the Supabase push; inserting and saving through `modelContext` in a view skips the sync.

## Build & Development

### Build Commands

**macOS (Xcode):**
```bash
xcodebuild -project BlindensportGraz.xcodeproj -configuration Debug -scheme BlindensportGraz
```

**Build for iOS Simulator:**
```bash
xcodebuild \
  -project BlindensportGraz.xcodeproj \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -scheme BlindensportGraz
```

**Build for Device (iOS):**
```bash
xcodebuild \
  -project BlindensportGraz.xcodeproj \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'platform=iOS' \
  -scheme BlindensportGraz
```

### Common Commands

**Show build settings (JSON):**
```bash
xcodebuild -showBuildSettings -json >> BUILD_SETTINGS.json
```

**Run tests:**
```bash
xcodebuild test -project BlindensportGraz.xcodeproj -configuration Debug -scheme BlindensportGraz
```

**Clean build directory:**
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/*
```

### Opening in Xcode
```bash
open BlindensportGraz.xcodeproj
```

## Testing Guidelines

Unit tests live in `BlindensportGrazTests/` (XCTest) and run in the Simulator with the `xcodebuild test` command above. Cover CRUD paths, persistence across restarts and permission checks (`can(.permission)`).

## Key Patterns

### Navigation
Tabs use the `Tab` API in `MainTabView`; each tab has its own `NavigationStack` whose root view calls `.appRouteDestinations(currentUser:)` exactly once. Every pushed screen is a case of `AppRoute` (`App/AppRoute.swift`), linked by value, so destinations are only built when followed:
```swift
NavigationLink(value: AppRoute.team(team)) {
    TeamRow(team: team)
}
```
Don't use `NavigationLink { DetailView() }`, and don't add `.appRouteDestinations` to a pushed view (a second registration in one stack is an error).

### Lists
```swift
List {
    if teams.isEmpty {
        EmptyStateView("Keine Teams", systemImage: "person.3",
                       description: "Lege ein neues Team an.")
    } else {
        ForEach(teams) { team in
            NavigationLink(value: AppRoute.team(team)) { TeamRow(team: team) }
                .deleteDisabled(!canManageTeams)
        }
        .onDelete { offsets in
            for index in offsets { TeamService.delete(teams[index], modelContext: modelContext) }
        }
    }
}
.refreshable { await SyncOrchestrationService.syncAll(modelContext: modelContext) }
```
`onDelete` offsets index the collection the `ForEach` shows — resolve them against that same (filtered, sorted) array, never the raw `@Query`. Gate swipe actions and toolbar buttons with `user.can(.permission)`.

### Writes
Create, edit and delete through the model's `*Service` (`TeamService.save(team, modelContext:)`, `TeamService.delete(team, modelContext:)`): it saves locally, reports failures and queues the Supabase push. Don't call `modelContext.save()` from a view.

### Forms and sheets
Data entry is a `Form` of `Section`s bound to the model with `@Bindable`. Add/edit forms open with `.sheet(isPresented:)`; use `.sheet(item:)` when the sheet shows an optional value. Errors are kept in an optional `@State` and shown with `.alert`.

## UI Conventions

- Spacing, radii, colours and the brand fill come from `Theme` (`Shared/Theme.swift`) — no hard-coded values
- `Form` for data entry, `List` for collections, `EmptyStateView` (Shared/) for empty states — not ContentUnavailableView (clips its title, grey text under 4.5:1)
- **ZStack** with `Theme.brandFill` circles for avatars; the initial letter is decorative (`accessibilityHidden`)
- `LazyVGrid` for card layouts (stats, recent items)
- Icon-only buttons get an `accessibilityLabel`; tap targets are at least 44×44 pt

## Localization (German)
All UI text is in German. Common terms:
- "Anmelden" = Login
- "Benutzername" = Username
- "Rolle" = Role
- "Mitglied" = Member
- "Trainer:in" = Coach
- "Admin" = Administrator

## Role Hierarchy
Accounts, roles and approvals live in **Supabase** (`../supabase/`), like all club data. Roles come from `user_roles`; permissions from `role_permissions` (check with `user.can(.permission)` / `authContext.can(.permission)`, never compare roles directly). The server enforces everything via RLS and RPCs.
1. **root** - admin + assigns roles (`roles.assign`)
2. **admin** - Full access to all features, approves accounts, reads protected member data
3. **coach** - Can create/manage events, trainings and teams
4. **member** - Basic user, can participate in events
5. *(no role)* - pending: schedule only until an admin approves the account

## Database Schema
Relationships in the local SwiftData models (the Supabase tables in `../supabase/` are the source of truth):
- Users <-> Teams (via TeamMembership)
- Users <-> Events (via EventParticipation)
- Teams <-> Memberships (one-to-many with TeamMembership)

## Date Handling
Dates are stored as `Date` objects and formatted using `.dateTime` format specifiers for display.
