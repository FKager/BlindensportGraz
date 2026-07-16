// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "rootcli",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "rootcli", path: "Sources/rootcli")
    ]
)
