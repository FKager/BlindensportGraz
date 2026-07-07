import SwiftUI
import SwiftData

struct AddEventView: View {
    let currentUser: User?
        @Environment(\.modelContext) private var modelContext
        @Environment(\.dismiss) private var dismiss

       @State private var title = ""
       @State private var sport = "Torball"
       @State private var location = "Graz"
       @State private var startDate = Date()
       @State private var endDate = Date().addingTimeInterval(3600)
       @State private var notes = ""

    let sports = ["Torball", "Goalball", "Blindenfußball", "Showdown", "Judo", "Leichtathletik", "Schwimmen", "Ski", "Radfahren"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Titel", text: $title)
                    Picker("Sportart", selection: $sport) {
                        ForEach(sports, id: \.self) { Text($0) }
                      }
                    TextField("Ort", text: $location)
                 }
                Section("Zeit") {
                    DatePicker("Start", selection: $startDate)
                    DatePicker("Ende", selection: $endDate)
                 }
                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                          .lineLimit(3...6)
                  }
             }
             .navigationTitle("Neues Event")
              .navigationBarTitleDisplayMode(.inline)
              .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                      }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let event = SportEvent(
                            title: title,
                            sport: sport,
                            location: location,
                            startDate: startDate,
                            endDate: endDate,
                            notes: notes,
                            createdBy: currentUser?.username ?? ""
                            )
                        modelContext.insert(event)
                        try? modelContext.save()
                       dismiss()
                     }
                      .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                   }
                }
           }
        }
    }

struct EventsListView: View {
    let currentUser: User?
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SportEvent.startDate) private var events: [SportEvent]
    @State private var showAdd = false

    var canManageEvents: Bool {
        guard let user = currentUser else { return false }
        return user.role == "admin" || user.role == "coach"
    }

    var body: some View {
        List {
            if events.isEmpty {
                ContentUnavailableView("Keine Events",
                                       systemImage: "calendar",
                                       description: Text("Lege ein neues Event an."))
            } else {
                ForEach(events) { event in
                    NavigationLink {
                        EventDetailView(event: event, currentUser: currentUser)
                    } label: {
                        EventRow(event: event)
                    }
                }
                .onDelete(perform: deleteEvents)
            }
        }
        .navigationTitle("Events")
        .toolbar {
            if canManageEvents {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEventView(currentUser: currentUser)
        }
    }

    private func deleteEvents(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(events[index])
        }
        try? modelContext.save()
    }
}

struct EventRow: View {
    let event: SportEvent

    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Text(event.startDate, format: .dateTime.day())
                      .font(.title2)
                      .bold()
                Text(event.startDate, format: .dateTime.month(.abbreviated))
                      .font(.caption)
                      .foregroundStyle(.secondary)
              }
              .frame(width: 50)
              .padding(.vertical, 4)
              .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                      .font(.headline)
                Text(event.sport)
                      .font(.subheadline)
                      .foregroundStyle(.secondary)
                Label(event.location, systemImage: "mappin.and.ellipse")
                      .font(.caption)
                      .foregroundStyle(.secondary)
              }
          }
          .padding(.vertical, 4)
      }
}

struct EventDetailView: View {
      @Bindable var event: SportEvent
    let currentUser: User?
      @Environment(\.modelContext) private var modelContext
      @Query private var users: [User]

    var body: some View {
        Form {
            Section("Details") {
                LabeledContent("Sportart", value: event.sport)
                LabeledContent("Ort", value: event.location)
                LabeledContent("Start", value: event.startDate.formatted(date: .long, time: .shortened))
                LabeledContent("Ende", value: event.endDate.formatted(date: .long, time: .shortened))
              }

            if !event.notes.isEmpty {
                Section("Notizen") {
                    Text(event.notes)
                 }
             }

            Section("Teilnehmer (\(event.participations.count))") {
                if event.participations.isEmpty {
                    Text("Noch keine Teilnehmer")
                          .foregroundColor(.secondary)
                  } else {
                     ForEach(event.participations) { p in
                        HStack {
                            Text(p.user.displayName)
                            Spacer()
                            Text(p.status)
                                  .font(.caption)
                                  .foregroundColor(.secondary)
                           }
                      }

                       if let user = currentUser,
                           !event.participations.contains(where: { $0.user.id == user.id }) {
                        Button("Selbst anmelden") {
                            let participation = EventParticipation(user: user, event: event, status: "confirmed")
                            modelContext.insert(participation)
                            try? modelContext.save()
                           }
                       }
                  }
             }
        }
        .navigationTitle(event.title)
    }
}
