import Foundation

public enum CLIError: Error, CustomStringConvertible {
    case message(String)

    public var description: String {
        switch self {
        case .message(let text): return text
        }
    }
}

/// Connection settings for the CloudKit Web Services Server-to-Server API.
/// Read from the environment so the private key path and key ID never end up
/// hardcoded or committed — see RootCLI/README.md for how to provision these.
public struct Config {
    public let containerID: String
    public let environment: String // "development" or "production"
    public let keyID: String
    public let privateKeyPath: String

    public init(containerID: String, environment: String, keyID: String, privateKeyPath: String) {
        self.containerID = containerID
        self.environment = environment
        self.keyID = keyID
        self.privateKeyPath = privateKeyPath
    }

    public static func fromEnvironment() throws -> Config {
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

    /// Destination settings for `copy-records`, read from a parallel set of
    /// `CLOUDKIT_TARGET_*` variables. CloudKit requires a *separate*
    /// Server-to-Server key pair per environment (see RootCLI/README.md), so
    /// the copy target can't reuse `CLOUDKIT_KEY_ID`/`CLOUDKIT_PRIVATE_KEY_PATH`.
    /// Same container as the source; environment defaults to `production`.
    public static func targetFromEnvironment() throws -> Config {
        let env = ProcessInfo.processInfo.environment
        func require(_ name: String) throws -> String {
            guard let value = env[name], !value.isEmpty else {
                throw CLIError.message("Missing required environment variable \(name) (the copy destination). See RootCLI/README.md.")
            }
            return value
        }
        return Config(
            containerID: env["CLOUDKIT_CONTAINER"] ?? "iCloud.it.a11y.BlindensportGraz",
            environment: env["CLOUDKIT_TARGET_ENVIRONMENT"] ?? "production",
            keyID: try require("CLOUDKIT_TARGET_KEY_ID"),
            privateKeyPath: try require("CLOUDKIT_TARGET_PRIVATE_KEY_PATH")
        )
    }
}
