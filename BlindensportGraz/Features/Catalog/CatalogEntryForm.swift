import SwiftUI

/// Sheet to add or edit one sport or event type (see `CatalogListsView`).
/// The behaviour of an event type is chosen once, when adding it: events
/// of that type are trainings, tournaments or plain events, and can't
/// change into another kind later.
struct CatalogEntryForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CatalogDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    let onSave: (CatalogDraft) async throws -> Void

    init(draft: CatalogDraft, onSave: @escaping (CatalogDraft) async throws -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    private var isNew: Bool { draft.existingID == nil }

    private var title: LocalizedStringKey {
        switch (draft.kind, isNew) {
        case (.sport, true): "Neue Sportart"
        case (.sport, false): "Sportart"
        case (.eventType, true): "Neue Veranstaltungsart"
        case (.eventType, false): "Veranstaltungsart"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                    if draft.kind == .eventType {
                        if isNew {
                            Picker("Verhalten", selection: $draft.behavior) {
                                ForEach(EventType.Behavior.allCases) { behavior in
                                    Text(behavior.label).tag(behavior)
                                }
                            }
                        } else {
                            LabeledContent("Verhalten", value: draft.behavior.label)
                        }
                    }
                    if !isNew {
                        Toggle("Zur Auswahl anbieten", isOn: $draft.isActive)
                    }
                } footer: {
                    if !isNew {
                        Text("Ein neuer Name ändert alle Teams und Termine mit dem alten Namen.")
                    }
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Palette.warning)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Speichern") { Task { await save() } }
                            .disabled(CatalogService.clean(draft.name).isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await onSave(draft)
            dismiss()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// German text for a failed save; a duplicate name gets its own.
    static func message(for error: Error) -> String {
        let text = String(describing: error)
        if text.contains("23505") || text.localizedCaseInsensitiveContains("duplicate key") {
            return String(localized: "Diesen Namen gibt es schon.")
        }
        if text.contains("42501") {
            return String(localized: "Nur Admins dürfen diese Listen ändern.")
        }
        return AuthErrorMessage.text(for: error)
    }
}
