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
            name: "CloudKitS2SCore",
            dependencies: [
                .product(name: "ClubSchema", package: "ClubSchema")
            ],
            path: "Sources/CloudKitS2SCore"
        ),
        .executableTarget(
            name: "rootcli",
            dependencies: ["CloudKitS2SCore"],
            path: "Sources/rootcli"
        ),
        // Covers CloudKitS2SCore's pure logic (member import/fill, private rows) —
        // no network. Mirrors Shared/ClubSchema's Tests target.
        .testTarget(
            name: "CloudKitS2SCoreTests",
            dependencies: ["CloudKitS2SCore"],
            path: "Tests/CloudKitS2SCoreTests"
        )
    ]
)
