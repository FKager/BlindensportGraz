import SwiftUI
import SwiftData

/// Lets an admin/coach add someone who isn't in the roster yet directly from
/// a Training/Tournament's Anwesenheit section — user request 2026-09-12:
/// "add new members to this event... can be a[n] athlete or coach/assistant...
/// in case of a coach/assistant, a PRAE can be assigned... added to the club
/// members list but without the flag 'Mitglied bei Grazer VSC'."
///
/// A Training/Tournament's roster is always derived from its assigned
/// Team(s) (`SportEvent.rosterAcrossTeams`), so a genuinely new person needs
/// a real `TeamMembership` on SOME team to show up in Anwesenheit at all —
/// there's no team-less attendance path (unlike plain Events, which use
/// `EventMembership` instead). Per the user's own suggestion, every new
/// member added this way goes onto one standing catch-all team,
/// "Blindensport Graz" (`Team.defaultTeams`, auto-created by
/// `CloudKitSync.ensureDefaultTeams` like the other default teams) — this
/// event's own `teams` gets that catch-all team appended if it isn't already
/// there, so the new person actually appears in THIS event's Anwesenheit
/// list, not just the catch-all team's own roster.
struct AddNewEventMemberView: View {
    let event: SportEvent
    /// Upper bound (in €) for the PRAE wheel picker — Training passes a flat
    /// 90 (matching TrainingDetailView's own picker), Tournament passes
    /// `Int(PraeCalculator.dailyCap) * tournament.dayCount` (matching
    /// TournamentDetailView's own per-membership calculation).
    let praeMax: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allTeams: [Team]

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var role: MembershipRole = .player
    @State private var praeAmount = 0

    static let catchAllTeamName = "Blindensport Graz"

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Vorname", text: $firstName)
                    TextField("Nachname", text: $lastName)
                }
                Section("Rolle") {
                    Picker("Rolle", selection: $role) {
                        Text("Sportler:in").tag(MembershipRole.player)
                        Text("Trainer:in").tag(MembershipRole.coach)
                        Text("Assistent:in").tag(MembershipRole.assistant)
                    }
                    .pickerStyle(.segmented)
                }
                if role.isHelfer {
                    Section("PRAE (€)") {
                        Picker("PRAE (€)", selection: $praeAmount) {
                            ForEach(Array(stride(from: 0, through: praeMax, by: 5)), id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.wheel)
                    }
                }
                Section {
                    Text("Wird der Mitgliederliste hinzugefügt (ohne die Kennzeichnung „Mitglied bei Grazer VSC“) und dem Team „\(Self.catchAllTeamName)“ zugeordnet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Neues Mitglied")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") { addMember() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func addMember() {
        let catchAllTeam: Team
        if let existing = allTeams.first(where: { $0.name.caseInsensitiveCompare(Self.catchAllTeamName) == .orderedSame }) {
            catchAllTeam = existing
        } else {
            // Safety net in case this device hasn't synced/run
            // ensureDefaultTeams yet — the team should normally already
            // exist via Team.defaultTeams.
            let team = Team(name: Self.catchAllTeamName, sport: "Sonstige")
            modelContext.insert(team)
            TeamService.save(team, modelContext: modelContext)
            catchAllTeam = team
        }

        let member = Member(firstName: firstName.trimmingCharacters(in: .whitespaces),
                            lastName: lastName.trimmingCharacters(in: .whitespaces),
                            memberOfGVSC: false)
        modelContext.insert(member)
        MemberService.save(member, modelContext: modelContext)

        let membership = TeamMembership(member: member, team: catchAllTeam, role: role)
        modelContext.insert(membership)
        TeamMembershipService.save(membership, modelContext: modelContext)

        // rosterAcrossTeams only walks event.teams — without this, the new
        // membership would exist but never show up in THIS event's list.
        // Deliberately NOT saved/pushed here: `event` is really a Training or
        // Tournament underneath this shared SportEvent-typed view, and only
        // the caller knows which type-specific service (TrainingService/
        // TournamentService) pushes it as the right CKRecord type. Same
        // "mutate now, let the existing Fertig/onDisappear save pick it up"
        // pattern the Beteiligte-Teams checkboxes in both detail views
        // already rely on.
        if !event.teams.contains(where: { $0.id == catchAllTeam.id }) {
            event.teams.append(catchAllTeam)
        }

        // Same two-step "create attendance, then set PRAE" sequence
        // TrainingDetailView/TournamentDetailView's own setAttendance/
        // setPraeAmount helpers use — mirrored here since this view is
        // shared across both rather than living inside either one.
        AttendanceService.setAttended(true, for: membership, at: event, modelContext: modelContext)
        if role.isHelfer, praeAmount > 0,
           let attendance = event.attendances.first(where: { $0.membership.id == membership.id }) {
            attendance.praeAmount = Double(praeAmount)
            AttendanceService.save(attendance, modelContext: modelContext)
        }

        dismiss()
    }
}
