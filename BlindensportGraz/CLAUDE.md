# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Blindensport Graz** is a SwiftUI iOS app for managing sport events organized for visually impaired athletes. The app helps organize tournaments, trainings, team memberships, and event participations for sports like Torball, Goalball, Blindenfußball, Showdown, Judo, Athletics, Swimming, Skiing, and Cycling.

## Architecture

### Core Models (Models.swift)
All data models use SwiftData's `@Model` protocol with iCloud sync via `ModelContainer`:

- **User**: User accounts with username, email, display name, and role (member/coach/admin)
- **Team**: Sport teams with name, sport type, description, and membership list
- **TeamMembership**: Link between users and teams with roles (player/coach/assistant)
- **SportEvent**: Events/tournaments with title, sport, location, date range, participations
- **Tournament**: Competitions with venue, maxTeams count, status (planned/ongoing/finished)
- **Training**: Training sessions with focus area, duration, location
- **EventParticipation**: Link between users and events with status (invited/confirmed/declined)

The `ModelContainer` is initialized in `BlindensportGrazApp.swift` with all 7 model types configured for persistent storage.

### Application Structure
```
RootView -> Login/Registration (if not authenticated) -> MainTabView
MainTabView -> TabView (Dashboard, Events, Tournaments, Trainings, Teams, Account)
```

Each tab uses `@Query` for data fetching from SwiftData and displays different views:

1. **DashboardView.swift**: Overview dashboard with stats cards and upcoming items
2. **EventsViews.swift**: Event management (create/edit/delete events)
3. **TournamentsViews.swift**: Tournament management (list, details, create)
4. **TrainingsViews.swift**: Training session management
5. **TeamsViews.swift**: Team management and member assignments
6. **AccountView.swift**: User profile management and account settings

### Data Flow Pattern
```swift
@Environment(\.modelContext) private var modelContext
@Query(sort: \(ModelField)) private var items: [EntityType]
// For modifications:
modelContext.insert(entity)
try? modelContext.save()
```

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

- The app uses SwiftUI's built-in testing infrastructure
- Test views for data CRUD operations
- Verify SwiftData persistence across app restarts
- Test role-based access controls (admin/coach/member)

## Key Patterns

### Form Styling
```swift
Form {
    Section("Title") {
        TextField("Label", text: $viewModel.title)
    }
}
```

### List with CRUD
```swift
List {
    ForEach(items) { item in
        NavigationLink { DetailView() } label: { Row(item) }
    }.onDelete(perform: deleteItems)
}
.toolbar(.menu)
```

### Sheets for Modals
```swift
.sheet(isPresented: $showAdd, content: { AddDetailView(currentUser: currentUser) })
```

### Navigation Stack Pattern
```swift
NavigationStack {
    ViewContent()
}.tabItem { Label("Name", systemImage: "icon") }
```

## UI Conventions

- **LinearGradient** backgrounds with blue/purple theme
- **ZStack** centered icons in circles for avatars
- **Form** layout for data entry views
- **List** + **Picker/SegmentedControl** for selection interfaces
- **LazyVGrid** for card layouts (stats, recent items)
- **NavigationStack** for hierarchical navigation
- **TabView** for main app tabs

## Localization (German)
All UI text is in German. Common terms:
- "Anmelden" = Login
- "Benutzername" = Username
- "Rolle" = Role
- "Mitglied" = Member
- "Trainer:in" = Coach
- "Admin" = Administrator

## Role Hierarchy
1. **admin** - Full access to all features
2. **coach** - Can create/manage events and trainings for their team
3. **member** - Basic user, can participate in events

## Database Schema
All data is stored using SwiftData's persistence layer with relationships:
- Users <-> Teams (via TeamMembership)
- Users <-> Events (via EventParticipation)
- Teams <-> Memberships (one-to-many with TeamMembership)

## Date Handling
Dates are stored as `Date` objects and formatted using `.dateTime` format specifiers for display.
