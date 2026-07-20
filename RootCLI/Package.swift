// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "rootcli",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0")
    ],
    targets: [
        .target(name: "CloudKitS2SCore", path: "Sources/CloudKitS2SCore"),
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
