import Foundation

/// Pushes the sensitive fields of locally saved/deleted roster entries to
/// Supabase `member_private` (CloudKit no longer carries them). Only runs for
/// accounts with `members.private.write`; RLS enforces the same server-side.
/// Failures surface through `ServiceFailureSignal` like other roster saves.
@MainActor
enum MemberPrivateSync {
    // Never write before this session loaded the server values: the local
    // fields would still be blank and overwrite real data.
    private static var mayWrite: Bool {
        guard let context = AuthContext.current else { return false }
        return context.can(.membersPrivateWrite) && context.privateDataLoaded
    }

    static func push(_ members: [Member]) {
        guard mayWrite, !members.isEmpty else { return }
        let rows = members.map(SupabaseMemberPrivateService.data(from:))
        Task {
            do {
                for row in rows { try await SupabaseMemberPrivateService.upsert(row) }
            } catch {
                ServiceFailureSignal.shared.report(
                    String(localized: "Geschützte Mitgliedsdaten (SVNR, IBAN, Geburtsdatum, Untersuchung) konnten nicht gespeichert werden: \(AuthErrorMessage.text(for: error))"))
            }
        }
    }

    static func delete(memberID: UUID) {
        guard mayWrite else { return }
        Task { try? await SupabaseMemberPrivateService.delete(memberID: memberID) }
    }
}
