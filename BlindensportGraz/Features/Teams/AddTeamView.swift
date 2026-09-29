import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AddTeamView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var sport = "Torball"
    @State private var descriptionText = ""

    let sports = ["Torball", "Goalball", "Blindenfußball", "Showdown", "Judo", "Leichtathletik", "Schwimmen"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Team") {
                    TextField("Name", text: $name)
                    Picker("Sportart", selection: $sport) {
                        ForEach(sports, id: \.self) { s in
                            Label(s, systemImage: SportIcon.symbolName(for: s)).tag(s)
                        }
                    }
                    TextField("Beschreibung", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Neues Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let team = Team(name: name, sport: sport, descriptionText: descriptionText)
                        modelContext.insert(team)
                        TeamService.save(team, modelContext: modelContext)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
