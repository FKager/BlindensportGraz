// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "rootcli",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        // CryptoKit is Apple-only; swift-crypto is the drop-in-API-compatible
        // replacement used on Linux/Windows (see CloudKitS2SClient.swift's
        // `#if canImport(CryptoKit)` import). Not needed at all on macOS,
        // where CryptoKit is used instead — hence the platform condition below.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "CloudKitS2SCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux, .windows, .android]))
            ],
            path: "Sources/CloudKitS2SCore"
        ),
        .executableTarget(
            name: "rootcli",
            dependencies: ["CloudKitS2SCore"],
            path: "Sources/rootcli"
        ),
        .executableTarget(
            name: "clubmembersapi",
            dependencies: [
                "CloudKitS2SCore",
                .product(name: "Vapor", package: "vapor")
            ],
            path: "Sources/clubmembersapi"
        )
    ]
)
