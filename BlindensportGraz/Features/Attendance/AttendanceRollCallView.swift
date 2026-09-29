import SwiftUI
import SwiftData

/// Distraction-free "roll call" for one Training or Tournament —
/// architecture-review.md §5 (P1). The detail views already have an
/// Anwesenheit section, but it's buried in a long edit form behind the
/// "Bearbeiten" toggle; a coach marking who showed up on the sideline wants
/// big rows, one tap per person, swipe gestures, and a running count.
///
/// Every edit goes through `AttendanceService.setAttended` — the exact same
/// call the detail-form toggles use — so the two stay perfectly in sync, and
/// the "row created lazily on first toggle" semantics live in one place.
/// Gated to admin/root at the call sites (same `canEdit` as everything else
/// that changes an entry's data).
struct AttendanceRollCallView: View {
    @Bindable var event: SportEvent
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var roster: [TeamMembership] { event.rosterAcrossTeams }

    private func isPresent(_ membership: TeamMembership) -> Bool {
        event.attendances.first { $0.membership.id == membership.id }?.attended ?? false
    }

    private var presentCount: Int { roster.filter(isPresent).count }

    private func setPresent(_ present: Bool, _ membership: TeamMembership) {
        AttendanceService.setAttended(present, for: membership, at: event, modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            Group {
                if roster.isEmpty {
                    ContentUnavailableView("Kein Team zugeordnet",
                                           systemImage: "person.3",
                                           description: Text("Diesem Eintrag ist kein Team zugewiesen."))
                } else {
                    List {
                        Section {
                            ForEach(roster) { membership in
                                Button {
                                    setPresent(!isPresent(membership), membership)
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: isPresent(membership) ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                            .foregroundStyle(isPresent(membership) ? Color.green : Color.secondary)
                                            .accessibilityHidden(true)
                                        Text(membership.displayName)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                                .accessibilityLabel(membership.displayName)
                                .accessibilityValue(isPresent(membership) ? "anwesend" : "abwesend")
                                .accessibilityHint("Doppeltippen, um die Anwesenheit umzuschalten")
                                .accessibilityAddTraits(isPresent(membership) ? .isSelected : [])
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { setPresent(true, membership) } label: {
                                        Label("Anwesend", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button { setPresent(false, membership) } label: {
                                        Label("Abwesend", systemImage: "xmark")
                                    }
                                    .tint(.gray)
                                }
                            }
                        } header: {
                            Text("\(presentCount) von \(roster.count) anwesend")
                                .font(.headline)
                                .textCase(nil)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Anwesenheit")
            .navigationBarTitleDisplayMode(.inline)
            // Light non-visual confirmation on every change — this screen is
            // meant to be operated without looking (architecture-review.md §3.6).
            .sensoryFeedback(.selection, trigger: presentCount)
            .toolbar {
                if !roster.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu("Alle") {
                            Button {
                                for membership in roster { setPresent(true, membership) }
                            } label: {
                                Label("Alle anwesend", systemImage: "checkmark.circle")
                            }
                            Button {
                                for membership in roster { setPresent(false, membership) }
                            } label: {
                                Label("Alle abwesend", systemImage: "circle")
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
