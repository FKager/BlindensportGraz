import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Admin-only combined "Personen" list, pushed from `VereinView`'s hub —
/// one row per real person, merging app accounts (`User`) and roster
/// entries (`Member`). Reachable only from the admin hub, so no extra role
/// gate here.
///
/// Dedup is best-effort: a `User` is folded together with the `Member` it
/// matches via `Member.first(matching:)` (email first, else first+last
/// name). Because that match is fuzzy, a `User` synced from another device
/// — whose `email` is never synced (see CloudKitSync) — can only be paired
/// by name, and two different people who share a first+last name collapse
/// into one row. A persistent User↔Member link is the real fix (out of
/// scope here).
struct PersonenListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\User.lastName), SortDescriptor(\User.firstName)])
    private var users: [User]
    @Query(sort: [SortDescriptor(\Member.lastName), SortDescriptor(\Member.firstName)])
    private var members: [Member]
    @State private var searchText = ""
    @State private var filter: PersonFilter = .all

    enum PersonFilter: String, CaseIterable, Identifiable {
        case all = "Alle"
        case withAccount = "Mit Konto"
        case rosterOnly = "Nur Kartei"
        case grazerVSC = "Grazer VSC"
        var id: String { rawValue }
    }

    private var people: [PersonEntry] {
        var rows: [PersonEntry] = []
        var matchedMemberIDs = Set<UUID>()

        for user in users {
            let match = Member.first(matching: user, in: members)
            if let match { matchedMemberIDs.insert(match.id) }
            rows.append(PersonEntry(
                id: "user-\(user.id.uuidString)",
                lastName: user.lastName,
                firstName: user.firstName,
                name: user.displayName.isEmpty ? "?" : user.displayName,
                hasAccount: true,
                onRoster: match != nil,
                roleLabel: user.role.displayLabel,
                memberOfGVSC: match?.memberOfGVSC ?? user.isGrazerVSCMember,
                teamCount: user.memberships.count,
                member: match
            ))
        }

        for member in members where !matchedMemberIDs.contains(member.id) {
            rows.append(PersonEntry(
                id: "member-\(member.id.uuidString)",
                lastName: member.lastName,
                firstName: member.firstName,
                name: member.fullName.isEmpty ? "?" : member.fullName,
                hasAccount: false,
                onRoster: true,
                roleLabel: nil,
                memberOfGVSC: member.memberOfGVSC,
                teamCount: member.teamMemberships.count,
                member: member
            ))
        }

        let filtered = rows.filter { row in
            switch filter {
            case .all: return true
            case .withAccount: return row.hasAccount
            case .rosterOnly: return row.onRoster && !row.hasAccount
            case .grazerVSC: return row.memberOfGVSC
            }
        }
        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let searched = needle.isEmpty ? filtered : filtered.filter { $0.name.lowercased().contains(needle) }
        return searched.sorted {
            let byLast = $0.lastName.localizedCaseInsensitiveCompare($1.lastName)
            if byLast != .orderedSame { return byLast == .orderedAscending }
            return $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(PersonFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if people.isEmpty {
                ContentUnavailableView("Keine Personen", systemImage: "person.crop.rectangle.stack")
            } else {
                ForEach(people) { row in
                    if let member = row.member {
                        NavigationLink { MemberDetailView(member: member) } label: { rowLabel(row) }
                    } else {
                        rowLabel(row)
                    }
                }
            }
        }
        .navigationTitle("Personen")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Name")
        .refreshable {
            await SyncOrchestrationService.syncAll(modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func rowLabel(_ row: PersonEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.name).font(.headline)
            HStack(spacing: 6) {
                if row.hasAccount { capsuleTag("Konto", .blue) }
                if row.onRoster { capsuleTag("Kartei", .green) }
                if row.memberOfGVSC {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Grazer VSC")
                }
            }
            HStack(spacing: 8) {
                if let roleLabel = row.roleLabel {
                    Text(roleLabel)
                }
                Text(row.teamCount == 1 ? "1 Team" : "\(row.teamCount) Teams")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func capsuleTag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 1)
            .badge(tint: color)
            .foregroundStyle(color)
    }
}

private struct PersonEntry: Identifiable {
    let id: String
    let lastName: String
    let firstName: String
    let name: String
    let hasAccount: Bool
    let onRoster: Bool
    let roleLabel: String?
    let memberOfGVSC: Bool
    let teamCount: Int
    let member: Member?
}
