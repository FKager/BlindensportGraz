import SwiftUI
import SwiftData

struct EventDetailView: View {
      @Bindable var event: SportEvent
    let currentUser: User?
      @Environment(\.modelContext) private var modelContext
      @Query(sort: [SortDescriptor(\User.lastName), SortDescriptor(\User.firstName)]) private var allUsers: [User]
      @Query(sort: [SortDescriptor(\Member.lastName), SortDescriptor(\Member.firstName)]) private var allMembers: [Member]
      @Query private var approvals: [AccountApproval]
      // Detail screens open read-only. Only an admin or the root account gets
      // the "Bearbeiten" toolbar toggle that flips this true and unlocks the
      // editable sections (user request 2026-09-08). "Selbst anmelden" below
      // stays available to everyone — it's the viewer's own participation,
      // not event data.
      @State private var isEditing = false

    // Who may leave read-only mode: admins and the club's root account.
    var canEdit: Bool {
        currentUser?.role == .admin || (currentUser?.isRoot ?? false)
    }

    // Direct-membership toggle helpers — event.directMembers is a to-many
    // relationship, not a plain array like the old event.teams, so adding/
    // removing needs a real EventMembership insert/delete, not just array
    // mutation. Applied immediately on tap (like Anwesenheit toggles in
    // TrainingDetailView/TournamentDetailView), not deferred to "Fertig".
    private func directMembership(forUser id: UUID) -> EventMembership? {
        event.directMembers.first { $0.user?.id == id }
    }

    private func directMembership(forMember id: UUID) -> EventMembership? {
        event.directMembers.first { $0.member?.id == id }
    }

    private func toggleDirectUser(_ user: User) {
        if let existing = directMembership(forUser: user.id) {
            EventMembershipService.delete(existing, modelContext: modelContext)
        } else {
            let membership = EventMembership(user: user, event: event)
            modelContext.insert(membership)
            EventMembershipService.save(membership, modelContext: modelContext)
        }
    }

    private func toggleDirectMember(_ member: Member) {
        if let existing = directMembership(forMember: member.id) {
            EventMembershipService.delete(existing, modelContext: modelContext)
        } else {
            let membership = EventMembership(member: member, event: event)
            modelContext.insert(membership)
            EventMembershipService.save(membership, modelContext: modelContext)
        }
    }

    var body: some View {
        Form {
            EventImagesSection(images: event.images, currentUser: currentUser, onAdd: addImage, onDelete: deleteImage)
                .disabled(!isEditing)

            Section("Details") {
                if !event.sport.isEmpty {
                    LabeledContent("Art der Veranstaltung", value: event.sport)
                }
                if !event.location.isEmpty {
                    LabeledContent("Veranstaltungsort", value: event.location)
                }
                if !event.fullAddress.isEmpty {
                    LabeledContent("Adresse", value: event.fullAddress)
                }
                LabeledContent("Start", value: event.startDate.formatted(date: .long, time: .shortened))
                LabeledContent("Ende", value: event.endDate.formatted(date: .long, time: .shortened))
              }

            if !event.notes.isEmpty {
                Section("Notizen") {
                    Text(event.notes)
                 }
             }

            if isEditing {
                if !allUsers.isEmpty || !allMembers.isEmpty {
                    Section("Mitglieder") {
                        if !allUsers.isEmpty {
                            Section("Registrierte Benutzer") {
                                ForEach(allUsers) { user in
                                    MemberSelectionRow(name: user.displayName, isSelected: directMembership(forUser: user.id) != nil) {
                                        toggleDirectUser(user)
                                    }
                                }
                            }
                        }
                        if !allMembers.isEmpty {
                            Section("Mitglieder ohne Konto") {
                                ForEach(allMembers) { member in
                                    MemberSelectionRow(name: member.fullName, isSelected: directMembership(forMember: member.id) != nil) {
                                        toggleDirectMember(member)
                                    }
                                }
                            }
                        }
                        Text("Keine Auswahl = für alle sichtbar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if !event.directMembers.isEmpty {
                Section("Mitglieder") {
                    ForEach(event.directMembers.sortedByLastName()) { membership in
                        Text(membership.displayName)
                    }
                }
            }

            Section("Teilnehmer (\(event.participations.count))") {
                if event.participations.isEmpty {
                    Text("Noch keine Teilnehmer")
                          .foregroundStyle(.secondary)
                  } else {
                     ForEach(event.participations.sorted { ($0.user.lastName, $0.user.firstName) < ($1.user.lastName, $1.user.firstName) }) { p in
                        HStack {
                            Text(p.user.displayName)
                            Spacer()
                            Text(p.status)
                                  .font(.caption)
                                  .foregroundStyle(.secondary)
                           }
                      }

                       if let user = currentUser,
                           !event.participations.contains(where: { $0.user.id == user.id }) {
                        // GVSC-gated (account-tiers refactor, decision #6) —
                        // a logged-in user who isn't a GVSC member/coach/
                        // admin can view an Event's participant list but not
                        // self-register for it.
                        if user.hasGVSCPrivileges(approved: AccessPolicy.approvedMember(
                            for: user, roster: allMembers, approvals: approvals, users: allUsers) != nil) {
                            Button("Selbst anmelden") {
                                let participation = EventParticipation(user: user, event: event, status: "confirmed")
                                modelContext.insert(participation)
                                EventParticipationService.save(participation, modelContext: modelContext)
                               }
                        } else {
                            Text("Nur für Grazer VSC Mitglieder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                       }
                  }
             }
        }
        .navigationTitle(event.title)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Fertig" : "Bearbeiten") {
                        if isEditing {
                            SportEventService.save(event, modelContext: modelContext)
                        }
                        isEditing.toggle()
                    }
                }
            }
        }
        .onDisappear {
            SportEventService.save(event, modelContext: modelContext)
        }
    }

    private func addImage(_ data: Data) {
        let image = EventImage(imageData: data, uploadedBy: currentUser?.id.uuidString ?? "", event: event)
        modelContext.insert(image)
        EventImageService.save(image, modelContext: modelContext)
    }

    private func deleteImage(_ image: EventImage) {
        EventImageService.delete(image, modelContext: modelContext)
    }
}
