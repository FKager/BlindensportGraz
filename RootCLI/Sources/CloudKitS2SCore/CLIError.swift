import Foundation

public enum CLIError: Error, CustomStringConvertible {
    case message(String)

    public var description: String {
        switch self {
        case .message(let text): return text
        }
    }
}
