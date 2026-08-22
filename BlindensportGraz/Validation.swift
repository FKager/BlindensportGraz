import Foundation

/// Lightweight, dependency-free validation helpers shared across the app's
/// entry forms (audit.md Security Findings 4/5, Enhancement #7). All checks
/// here are advisory by design — a blank input is never flagged (absence
/// isn't malformed), and none of them ever reject/crash on already-saved
/// real-world data (see MemberImportExport.swift and cerebrum.md's
/// 2026-07-30 malformed-source-data entry — imports must keep working on
/// messy data, just without a green checkmark).
enum Validation {
    /// Loose email-shape check: exactly one "@", non-empty local/domain
    /// parts, no whitespace, and a "." somewhere in the domain that isn't
    /// the first/last character. Intentionally not RFC 5322-strict — this
    /// only needs to catch obviously-malformed input, not validate
    /// deliverability.
    static func isPlausibleEmail(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        guard !trimmed.contains(" "),
              let atIndex = trimmed.firstIndex(of: "@"),
              trimmed.filter({ $0 == "@" }).count == 1,
              atIndex != trimmed.startIndex,
              trimmed.index(after: atIndex) != trimmed.endIndex else { return false }
        let domain = trimmed[trimmed.index(after: atIndex)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    /// Mod-97 IBAN checksum (ISO 7064 MOD 97-10). Advisory only — never
    /// blocks saving, see Member.iban's own doc comment (source roster data
    /// isn't consistently formatted enough to validate/typecheck further).
    static func ibanChecksumIsValid(_ raw: String) -> Bool {
        let iban = raw.uppercased().replacingOccurrences(of: " ", with: "")
        guard !iban.isEmpty else { return true }
        guard iban.count >= 5, iban.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }

        let rearranged = String(iban.dropFirst(4)) + String(iban.prefix(4))
        var remainder = 0
        for char in rearranged {
            let value: Int
            if let digit = char.wholeNumberValue, char.isNumber {
                value = digit
            } else if let ascii = char.asciiValue, char.isLetter, let aValue = Character("A").asciiValue {
                value = Int(ascii - aValue) + 10
            } else {
                return false
            }
            // Feed each digit of `value` (1 or 2 digits) into the running
            // mod-97 remainder rather than building one giant numeric
            // string, which would overflow Int for any real IBAN length.
            for digitChar in String(value) {
                guard let digit = digitChar.wholeNumberValue else { return false }
                remainder = (remainder * 10 + digit) % 97
            }
        }
        return remainder == 1
    }

    /// Austrian SVNR ("Sozialversicherungsnummer") shape: 4-digit running
    /// number + 6-digit birthdate (DDMMYY), 10 digits total, dashes/spaces
    /// allowed as separators. Pattern-only (no checksum digit verified),
    /// advisory.
    static func isPlausibleAustrianSVNR(_ raw: String) -> Bool {
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty else { return true }
        return digits.count == 10
    }
}
