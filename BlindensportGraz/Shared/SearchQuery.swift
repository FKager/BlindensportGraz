import Foundation

/// How list searches match: ignoring case and accents ("muller" finds
/// "Müller"), after trimming the query. One rule for every list.
nonisolated enum SearchQuery {
    /// True when the trimmed `query` is empty or any of `fields` contains it.
    static func matches(_ query: String, in fields: String...) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return fields.contains { $0.localizedStandardContains(needle) }
    }
}
