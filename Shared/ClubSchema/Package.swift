// swift-tools-version:5.9
import PackageDescription

/// The roster record's field names and shape (`MemberField`,
/// `ClubMemberRecord`), used by RootCLI's member import/update. Foundation
/// only. The iOS app used it too until 2026-11-21; it now maps members to
/// Supabase rows itself (SupabaseRows.swift).
let package = Package(
    name: "ClubSchema",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "ClubSchema", targets: ["ClubSchema"]),
    ],
    targets: [
        .target(name: "ClubSchema"),
        .testTarget(name: "ClubSchemaTests", dependencies: ["ClubSchema"]),
    ]
)
