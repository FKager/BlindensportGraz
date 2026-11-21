// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "rootcli",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Local, dependency-free package holding the shared Member/ClubMember
        // record shape (audit.md Architecture Finding 5) — also depended on
        // by the iOS app target, see ../project.yml's `packages:` section.
        .package(path: "../Shared/ClubSchema")
    ],
    targets: [
        .target(
            name: "RootCLICore",
            dependencies: [
                .product(name: "ClubSchema", package: "ClubSchema")
            ],
            path: "Sources/RootCLICore"
        ),
        .executableTarget(
            name: "rootcli",
            dependencies: ["RootCLICore"],
            path: "Sources/rootcli"
        ),
        // Covers RootCLICore's pure logic (member import/fill, private rows) —
        // no network. Mirrors Shared/ClubSchema's Tests target.
        .testTarget(
            name: "RootCLICoreTests",
            dependencies: ["RootCLICore"],
            path: "Tests/RootCLICoreTests"
        )
    ]
)
