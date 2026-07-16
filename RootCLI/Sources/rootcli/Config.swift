import Foundation

enum CLIError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): return text
        }
    }
}

/// Connection settings for the CloudKit Web Services Server-to-Server API.
/// Read from the environment so the private key path and key ID never end up
/// hardcoded or committed — see RootCLI/README.md for how to provision these.
struct Config {
    let containerID: String
    let environment: String // "development" or "production"
    let keyID: String
    let privateKeyPath: String

    static func fromEnvironment() throws -> Config {
        let env = ProcessInfo.processInfo.environment
        func require(_ name: String) throws -> String {
            guard let value = env[name], !value.isEmpty else {
                throw CLIError.message("Missing required environment variable \(name). See RootCLI/README.md.")
            }
            return value
        }
        return Config(
            containerID: env["CLOUDKIT_CONTAINER"] ?? "iCloud.it.a11y.BlindensportGraz",
            environment: env["CLOUDKIT_ENVIRONMENT"] ?? "development",
            keyID: try require("CLOUDKIT_KEY_ID"),
            privateKeyPath: try require("CLOUDKIT_PRIVATE_KEY_PATH")
        )
    }
}
