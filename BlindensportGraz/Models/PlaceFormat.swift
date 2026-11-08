import Foundation

/// The "Ort" rule shared by the reports: Austria is the club's default and
/// stays implicit, any other country is appended after a comma.
nonisolated enum PlaceFormat {
    /// "Linz" → "Linz"; "Prag" + "Tschechien" → "Prag, Tschechien".
    /// The country is left out when it is empty or "Österreich", and
    /// stands alone when `place` is empty.
    static func appendingForeignCountry(_ country: String, to place: String) -> String {
        let trimmedCountry = country.trimmingCharacters(in: .whitespaces)
        guard !trimmedCountry.isEmpty, trimmedCountry != "Österreich" else { return place }
        let trimmedPlace = place.trimmingCharacters(in: .whitespaces)
        return trimmedPlace.isEmpty ? trimmedCountry : "\(trimmedPlace), \(trimmedCountry)"
    }
}
