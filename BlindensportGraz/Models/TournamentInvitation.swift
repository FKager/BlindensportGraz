import Foundation
import SwiftData
import UniformTypeIdentifiers

/// One document of a tournament ("Dokumente": invitation, schedule,
/// results …) — PDF, Word, Excel, text or image. A tournament has any number
/// of them; they're uploaded in the tournament's detail screen (or kept from
/// "Turnier aus Einladung erstellen") and all bundled into its
/// Sammelabrechnung ZIP/print job. Every approved account reads them;
/// events.manage adds and deletes (`TournamentInvitationService`). Immutable
/// once uploaded. The name stays "invitation" (table `tournament_invitations`,
/// bucket `tournament-invitations`) from when a tournament had only one.
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
        case "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls": "application/vnd.ms-excel"
        case "txt": "text/plain"
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "heic": "image/heic"
        case "heif": "image/heif"
        default: "application/pdf"
        }
    }

    /// The document types the bucket accepts (file picker filter).
    nonisolated static let supportedContentTypes: [UTType] = [
        .pdf, .plainText, .jpeg, .png, .heic, .heif,
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "doc") ?? .data,
        UTType(filenameExtension: "xlsx") ?? .data,
        UTType(filenameExtension: "xls") ?? .data
    ]

    /// Largest file the bucket accepts (15 MB, see the storage migration).
    nonisolated static let maxFileSize = 15 * 1024 * 1024

    /// Why a file can't be kept as a tournament document, in German for the
    /// screen; nil if it can.
    nonisolated static func attachmentProblem(fileName: String, size: Int) -> String? {
        if !isSupported(fileName: fileName) { return "Dateityp wird nicht unterstützt." }
        if size > maxFileSize { return "größer als 15 MB." }
        return nil
    }

    /// Accepted by the bucket? Judged by extension, like `contentType(forFileName:)`.
    nonisolated static func isSupported(fileName: String) -> Bool {
        ["pdf", "docx", "doc", "xlsx", "xls", "txt", "jpg", "jpeg", "png", "heic", "heif"]
            .contains((fileName as NSString).pathExtension.lowercased())
    }
}
