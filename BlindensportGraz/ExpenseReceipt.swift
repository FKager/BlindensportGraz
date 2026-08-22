import Foundation
import SwiftData

/// An expense-receipt photo attached to a KostZ/PRAE accounting period —
/// audit.md Enhancement #10. Mirrors `EventImage`'s field shape and
/// immutable-once-uploaded convention exactly (see that model's doc
/// comment), just scoped differently: KostZ/PRAE aren't tied to one
/// specific Training/Tournament instance the way event photos are, they're
/// scoped to a whole calendar month or one tournament — the same
/// month-vs-tournament split `KostZMonthSummary`/`KostZTournamentSummary`
/// already use. Exactly one of `(month, year)` / `tournament` is set, never
/// both/neither (same convention as `TeamMembership.user`/`.member`).
///
/// **Scoping decision: images only, no PDF support.** A receipt photo
/// (photographing a paper receipt) is the realistic common case this
/// mirrors `EventImage`'s existing `PhotosPicker` + `ImageProcessing`
/// pipeline for; PDF receipts would need an entirely separate
/// `.fileImporter` + viewer path (no downscale-before-upload equivalent,
/// no shared UI with the image gallery below) — materially more work than
/// reusing the proven image pattern, so it's out of scope here and left as
/// a documented follow-up rather than half-implemented.
@Model
final class ExpenseReceipt {
    @Attribute(.unique) var id: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data = Data()
    var uploadedBy: String = ""
    var uploadedAt: Date = Date.now
    var note: String = ""
    var month: Int?
    var year: Int?
    var tournament: Tournament?

    init(id: UUID = UUID(),
         imageData: Data,
         uploadedBy: String = "",
         uploadedAt: Date = .now,
         note: String = "",
         month: Int? = nil,
         year: Int? = nil,
         tournament: Tournament? = nil) {
        self.id = id
        self.imageData = imageData
        self.uploadedBy = uploadedBy
        self.uploadedAt = uploadedAt
        self.note = note
        self.month = month
        self.year = year
        self.tournament = tournament
    }
}
