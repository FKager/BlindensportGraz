import Foundation
import Supabase

enum MembershipApplicationError: LocalizedError {
    case notAllowed
    case alreadyMember
    case justSent
    case failed

    var errorDescription: String? {
        switch self {
        case .notAllowed:
            return String(localized: "Du darfst für diesen Eintrag keine Beitrittserklärung senden.")
        case .alreadyMember:
            return String(localized: "Dieser Eintrag ist bereits Mitglied des Grazer VSC.")
        case .justSent:
            return String(localized: "Die Beitrittserklärung wurde gerade erst gesendet. Bitte in ein paar Minuten noch einmal versuchen.")
        case .failed:
            return String(localized: "Die Beitrittserklärung konnte nicht gesendet werden. Bitte später noch einmal versuchen.")
        }
    }
}

/// Edge Function `send-membership-application`: mails the filled .docx (and
/// the linked account's profile photo) to the club and marks the roster
/// entry as applied. Who may send is checked server-side.
@MainActor
enum SupabaseMembershipApplicationService {
    nonisolated struct Result: Decodable {
        let sent: Bool
        let photo: Bool
    }

    /// Returns whether a profile photo was attached. `ownPhoto`: sent from
    /// the caller's own Account screen — without a linked account the
    /// caller's own profile photo is attached.
    static func send(memberID: UUID, docx: Data, ownPhoto: Bool) async throws -> Bool {
        nonisolated struct Body: Encodable {
            let member_id: String
            let docx_base64: String
            let own_photo: Bool
        }
        let body = Body(member_id: memberID.uuidString.lowercased(), docx_base64: docx.base64EncodedString(),
                        own_photo: ownPhoto)
        do {
            let result: Result = try await SupabaseClientSingleton.shared.client.functions.invoke(
                "send-membership-application", options: FunctionInvokeOptions(method: .post, body: body))
            return result.photo
        } catch FunctionsError.httpError(let code, let data) {
            nonisolated struct Failure: Decodable { let error: String }
            let reason = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            switch (code, reason) {
            case (403, _): throw MembershipApplicationError.notAllowed
            case (409, "already_member"): throw MembershipApplicationError.alreadyMember
            case (409, _): throw MembershipApplicationError.justSent
            default: throw MembershipApplicationError.failed
            }
        }
    }
}
