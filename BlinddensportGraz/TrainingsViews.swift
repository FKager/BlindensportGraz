import SwiftUI
import SwiftData
import Combine

struct AddTrainingView: View {
     @Environment(\.modelContext) private var modelContext
      @Environment(\.dismiss) private var dismiss

       @State private var title = ""
       @State private var sport = "Torball"
       @State private var location = "Graz"
       @State private var startDate = Date()
       @State private var durationMinutes = 90
       @State private var focusArea = ""
       @State private var notes = ""

    let sports = ["Torball", "Goalball", "Blindenfußball", "Showdown", "Judo", "Leichtathletik", "Schwimmen", "Ski", "Radfahren"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Training") {
                    TextField("Titel", text: $title)
                    Picker("Sportart", selection: $sport) {
                        ForEach(sports, id: \.self) { Text($0) }
                       }
                    TextField("Ort", text: $location)
                   }
                Section("Planung") {
                    DatePicker("Start", selection: $startDate)
                    Stepper("Dauer: \(durationMinutes) min", value: $durationMinutes, in: 15...240, step: 15)
                    TextField("Schwerpunkt", text: $focusArea)
                   }
                Section("Notizen") {
                    TextField("Notizen", text: $notes, axis: .vertical)
                           lineLimit(3...6)
                   }
             }
              navigationTitle("Neues Training")
           navigationBarTitleDisplayMode(.inline)
        toolbar {
           ToolbarItem(placement: .cancellationAction) {
               Button("Abbrechen") { dismiss() }
                  }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    let training = Training(
                        title: title,
                        sport: sport,
                        location: location,
                        startDate: startDate,
                        durationMinutes: durationMinutes,
                        focusArea: focusArea,
                        notes: notes,
                        createdBy: currentUser?.username ?? ""
                        )
                    modelContext.insert(training)
                    try? modelContext.save()

                    // Post notification when training is created
                   NotificationCenter.default.post(
                       name: NSNotification.Name("TrainingCreated"),
                       object: nil,
                       userInfo: [
                           "message": "Neues Training erstellt!",
                           "title": title,
                           "sport": sport,
                           "location": location,
                           "durationMinutes": durationMinutes
                        ]
                    )

                   dismiss()
                      }
                       disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                      }
                   }
             }
        }
    }
}

struct TrainingRow: View {
     let training: Training

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(training.title)
               .font(.headline)
            HStack {
                Label(training.sport, systemImage: "sportscourt")
                Spacer()
                Label("\(training.durationMinutes) min", systemImage: "clock")
               }
               .font(.caption)
               .foregroundColor(.secondary)

            HStack {
                Label(training.location, systemImage: "mappin.and.ellipse")
                Spacer()
                Text(training.startDate, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
               }
               .font(.caption)
               .foregroundColor(.secondary)
        }
       .padding(.vertical, 4)
    }
}

struct TrainingDetailView: View {
     @Bindable var training: Training

    var body: some View {
        Form {
            Section("Training") {
                TextField("Titel", text: $training.title)
                TextField("Sportart", text: $training.sport)
                TextField("Ort", text: $training.location)
               }
           Section("Planung") {
               DatePicker("Start", selection: $training.startDate)
               Stepper("Dauer: \(training.durationMinutes) min", value: $training.durationMinutes, in: 15...240, step: 15)
               TextField("Schwerpunkt", text: $training.focusArea)
              }
           Section("Notizen") {
                TextField("Notizen", text: $training.notes, axis: .vertical)
                       lineLimit(3...6)
              }
         }
          navigationTitle(training.title)
          navigationBarTitleDisplayMode(.inline)
      }
}

struct TrainingsListView: View {
     let currentUser: User?
        @Environment(\.modelContext) private var modelContext
        @Query(sort: \(Training.startDate)) private var trainings: [Training]
        @State private var showAdd = false

    var canManageEvents: Bool {
        guard let user = currentUser else { return false }
        return user.role == "admin" || user.role == "coach"
       }

    var body: some View {
        List {
           if trainings.isEmpty {
               ContentUnavailableView("Keine Trainings",
                                      systemImage: "figure.run",
                                      description: Text("Lege ein neues Training an."))
              } else {
                  ForEach(trainings) { training in
                    NavigationLink {
                        TrainingDetailView(training: training)
                          } label: {
                           TrainingRow(training: training)
                         }
                       }.onDelete(perform: deleteTrainings)
                      }
                 }

             navigationTitle("Trainings")
             toolbar {
               if canManageEvents {
                   ToolbarItem(placement: .topBarTrailing) {
                       Button { showAdd = true } label: {
                            Image(systemName: "plus")
                           }
                         }
                    }
                }
           }

            sheet(isPresented: $showAdd) {
                 AddTrainingView(currentUser: currentUser)
               }
        }
    }
}
