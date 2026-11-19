import SwiftUI
import SwiftData

/// Verein › "Sportarten und Veranstaltungsarten" (club.manage): the club's
/// two lists. Adding, renaming, (de)activating and reordering go straight
/// to the server via `CatalogService`; an online screen like Rollen.
struct CatalogListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var sports: [ClubSport]
    @Query private var types: [EventType]

    @State private var draft: CatalogDraft?
    @State private var isBusy = false
    @State private var errorMessage: String?

    private var sortedSports: [ClubSport] {
        sports.sorted { ($0.sortOrder, $0.name.localizedLowercase) < ($1.sortOrder, $1.name.localizedLowercase) }
    }

    private var sortedTypes: [EventType] {
        types.sorted { ($0.sortOrder, $0.name.localizedLowercase) < ($1.sortOrder, $1.name.localizedLowercase) }
    }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.Palette.warning)
                }
            }

            Section {
                ForEach(sortedSports) { sport in
                    Button {
                        draft = CatalogDraft(sport: sport)
                    } label: {
                        CatalogRow(name: sport.name, detail: nil, isActive: sport.isActive,
                                   systemImage: SportIcon.symbolName(for: sport.name))
                    }
                }
                .onMove { from, to in
                    var ids = sortedSports.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    run { try await CatalogService.reorder(table: "sports", ids: ids) }
                }
                Button {
                    draft = CatalogDraft(newSportAfter: sports.map(\.sortOrder))
                } label: {
                    Label("Sportart hinzufügen", systemImage: "plus")
                }
            } header: {
                Text("Sportarten")
            } footer: {
                Text("Deaktivierte Einträge bleiben bei bestehenden Teams und Terminen erhalten, werden aber nicht mehr zur Auswahl angeboten. Umbenennen ändert alle Einträge mit dem alten Namen.")
            }

            Section {
                ForEach(sortedTypes) { type in
                    Button {
                        draft = CatalogDraft(type: type)
                    } label: {
                        CatalogRow(name: type.name,
                                   detail: EventType.Behavior(rawValue: type.behavior)?.label,
                                   isActive: type.isActive, systemImage: nil)
                    }
                }
                .onMove { from, to in
                    var ids = sortedTypes.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    run { try await CatalogService.reorder(table: "event_types", ids: ids) }
                }
                Button {
                    draft = CatalogDraft(newTypeAfter: types.map(\.sortOrder))
                } label: {
                    Label("Veranstaltungsart hinzufügen", systemImage: "plus")
                }
            } header: {
                Text("Veranstaltungsarten")
            } footer: {
                Text("Das Verhalten bestimmt, wo eine Art angeboten wird und wie sie sich verhält: wie ein Training (Anwesenheit, Trainingsberichte), wie ein Turnier (Teams, Dokumente, Abrechnung) oder wie eine Veranstaltung (Personen direkt auswählen).")
            }
        }
        .navigationTitle("Sportarten und Arten")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            if isBusy {
                ToolbarItem(placement: .topBarLeading) { ProgressView() }
            }
        }
        .disabled(isBusy)
        .refreshable { await CatalogService.refresh(modelContext: modelContext) }
        .task { await CatalogService.refresh(modelContext: modelContext) }
        .sheet(item: $draft) { draft in
            CatalogEntryForm(draft: draft) { saved in
                try await save(saved, original: draft)
            }
        }
    }

    private func save(_ saved: CatalogDraft, original: CatalogDraft) async throws {
        switch (saved.kind, saved.existingID) {
        case (.sport, nil):
            try await CatalogService.addSport(name: saved.name, sortOrder: saved.sortOrder)
        case (.eventType, nil):
            try await CatalogService.addEventType(name: saved.name, behavior: saved.behavior, sortOrder: saved.sortOrder)
        case (.sport, let id?):
            if CatalogService.clean(saved.name) != original.name {
                try await CatalogService.renameSport(id: id, to: saved.name)
            }
            if saved.isActive != original.isActive {
                try await CatalogService.setSport(id: id, isActive: saved.isActive)
            }
        case (.eventType, let id?):
            if CatalogService.clean(saved.name) != original.name {
                try await CatalogService.renameEventType(id: id, to: saved.name)
            }
            if saved.isActive != original.isActive {
                try await CatalogService.setEventType(id: id, isActive: saved.isActive)
            }
        }
        await CatalogService.refresh(modelContext: modelContext)
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            isBusy = true
            errorMessage = nil
            defer { isBusy = false }
            do {
                try await work()
            } catch {
                errorMessage = CatalogEntryForm.message(for: error)
            }
            await CatalogService.refresh(modelContext: modelContext)
        }
    }
}

/// What the edit form works on: a new or an existing sport / event type.
struct CatalogDraft: Identifiable {
    enum Kind { case sport, eventType }

    let id = UUID()
    let kind: Kind
    let existingID: UUID?
    var name: String
    var behavior: EventType.Behavior
    var isActive: Bool
    var sortOrder: Int

    init(sport: ClubSport) {
        kind = .sport; existingID = sport.id; name = sport.name
        behavior = .event; isActive = sport.isActive; sortOrder = sport.sortOrder
    }

    init(type: EventType) {
        kind = .eventType; existingID = type.id; name = type.name
        behavior = EventType.Behavior(rawValue: type.behavior) ?? .event
        isActive = type.isActive; sortOrder = type.sortOrder
    }

    init(newSportAfter orders: [Int]) {
        kind = .sport; existingID = nil; name = ""
        behavior = .event; isActive = true; sortOrder = CatalogService.nextSortOrder(after: orders)
    }

    init(newTypeAfter orders: [Int]) {
        kind = .eventType; existingID = nil; name = ""
        behavior = .event; isActive = true; sortOrder = CatalogService.nextSortOrder(after: orders)
    }
}

private struct CatalogRow: View {
    let name: String
    let detail: String?
    let isActive: Bool
    let systemImage: String?

    var body: some View {
        HStack {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading) {
                Text(name)
                    .foregroundStyle(isActive ? .primary : .secondary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !isActive {
                Text("Deaktiviert")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Bearbeiten")
    }
}
