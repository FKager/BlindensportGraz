import Foundation
import SwiftData

/// The organiser's invitation (Einladung) for a tournament — PDF/DOCX/TXT,
/// uploaded in the tournament's Sammelabrechnung or kept from "Turnier aus
/// Einladung erstellen", and bundled into its ZIP/print job. Admins only
/// (budget.manage, like `ExpenseReceipt`). Immutable once uploaded:
/// replacing deletes the old one and inserts a new one
/// (`TournamentInvitationService.replace`). The newest per tournament wins
/// if two ever coexist.
@Model
final class TournamentInvitation {
    @Attribute(.unique) var id: UUID = UUID()
    @Attribute(.externalStorage) var fileData: Data = Data()
    var fileName: String = ""
    var contentType: String = ""
    var uploadedBy: String = ""
    var uploadedAt: Date = Date.now
    var tournament: Tournament?

    init(id: UUID = UUID(),
         fileData: Data,
         fileName: String,
         contentType: String,
         uploadedBy: String = "",
         uploadedAt: Date = .now,
         tournament: Tournament? = nil) {
        self.id = id
        self.fileData = fileData
        self.fileName = fileName
        self.contentType = contentType
        self.uploadedBy = uploadedBy
        self.uploadedAt = uploadedAt
        self.tournament = tournament
    }

    /// File extension (lowercased, without dot), from the name; "pdf" if none.
    var fileExtension: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ext.isEmpty ? "pdf" : ext
    }
}

extension TournamentInvitation {
    /// MIME type for a file name's extension (upload content type / bucket allow-list).
    nonisolated static func contentType(forFileName name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc": "application/msword"
        case "txt": "text/plain"
        default: "application/pdf"
        }
    }
}
