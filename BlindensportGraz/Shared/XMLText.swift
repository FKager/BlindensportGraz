import Foundation

/// Text for an XML element's content in the .xlsx/.docx files this app
/// writes (string-level patching, no XML library).
nonisolated enum XMLText {
    /// Escapes `&`, `<`, `>` and drops characters XML 1.0 doesn't allow at
    /// all (control characters other than tab, line feed and carriage
    /// return, e.g. a vertical tab pasted from Word). Excel and Word refuse a
    /// file containing one, so a single odd character in a name would make
    /// the whole report unusable.
    static func escape(_ value: String) -> String {
        var result = ""
        result.unicodeScalars.reserveCapacity(value.unicodeScalars.count)
        for scalar in value.unicodeScalars where isAllowed(scalar) {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// XML 1.0 `Char`: #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF].
    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x9, 0xA, 0xD, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF: return true
        default: return false
        }
    }
}
