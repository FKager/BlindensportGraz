// swift-tools-version:5.9
import PackageDescription

/// Shared record-shape package for the Member/ClubMember CKRecord — audit.md
/// Architecture Finding 5: the app's `Member` model (BlindensportGraz/Member.swift)
/// and RootCLI's `MemberRecord`/`clubmembersapi`'s routes each independently
/// hand-maintained this field shape with no shared code, already causing
/// drift twice (cerebrum.md's 2026-07-18/2026-07-30 entries — a field split
/// requiring lockstep updates, caught only by manual checklist discipline).
///
/// Deliberately Foundation-only, no CloudKit/Vapor/UIKit/SwiftData imports,
/// so it builds cleanly as a dependency of both the iOS app target
/// (BlindensportGraz.xcodeproj, via project.yml's `packages:`) and the
/// macOS SPM executables in RootCLI/Package.swift.
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
