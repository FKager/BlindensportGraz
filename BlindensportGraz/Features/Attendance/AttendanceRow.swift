import SwiftUI
import SwiftData

/// One person in a Training's "Anwesenheit" / Tournament's "Teilnehmer:innen"
/// section: the attended toggle, plus the PRAE amount inputs for present
/// helpers/coaches (role "assistant"/"coach" — see Attendance.praeAmount).
///
/// The toggle is bound to local `@State`, not to the model: only a user edit
/// (`.onChange(of: isAttended)`) saves and pushes. Model changes — including
/// ones a CloudKit pull writes into the same `Attendance` object — just
/// refresh the displayed value, so a pull never triggers a re-push.
struct AttendanceRow: View {
    let membership: TeamMembership
    let event: SportEvent
    /// Upper bound for the PRAE inputs: €90 for a Training; for a Tournament
    /// PraeCalculator.dailyCap × the tournament's day count.
    let maxPrae: Int

    @Environment(\.modelContext) private var modelContext
    @State private var isAttended = false

    private var attendance: Attendance? {
        event.attendances.first { $0.membership.id == membership.id }
    }

    private var storedAttended: Bool {
        attendance?.attended ?? false
    }

    var body: some View {
        Toggle(membership.displayName, isOn: $isAttended)
            .onChange(of: storedAttended, initial: true) { _, attended in
                isAttended = attended
            }
            .onChange(of: isAttended) { _, attended in
                saveAttended(attended)
            }

        if membership.role.isHelfer, isAttended, let attendance {
            PraeAmountRow(attendance: attendance, maxPrae: maxPrae)
        }
    }

    private func saveAttended(_ attended: Bool) {
        guard attended != storedAttended else { return }
        AttendanceService.setAttended(attended, for: membership, at: event, modelContext: modelContext)
    }
}
