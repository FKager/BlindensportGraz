import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AddTeamView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var sport = "Torball"
    @State private var descriptionText = ""

    /// What's missing before saving; shown above the buttons and read out.
    @State private var formMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                FormTitleHeader(title: "Neues Team")
                Section(heading: "Team") {
                    StackedField(label: "Name", text: $name)
                    SportPicker(selection: $sport)
                    StackedField(label: "Beschreibung", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }
                FormActionButtons(primaryTitle: "Speichern", cancelTitle: "Abbrechen", message: formMessage,
                                  onPrimary: attemptSave, onCancel: { dismiss() })
            }
        }
    }

    /// Speichern is never greyed out: it says what's missing instead.
    private func attemptSave() {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            formMessage = String(localized: "Bitte gib einen Namen ein.")
            AccessibilityNotification.Announcement(formMessage ?? "").post()
            return
        }
        formMessage = nil
        save()
    }

    private func save() {
        let team = Team(name: name, sport: sport, descriptionText: descriptionText)
        modelContext.insert(team)
        TeamService.save(team, modelContext: modelContext)
        dismiss()
    }
}
