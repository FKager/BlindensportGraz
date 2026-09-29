import SwiftUI
import SwiftData

struct AccountView: View {
    let currentUser: User?
    let onLogout: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query private var allUsers: [User]
    @Query private var members: [Member]
    @Query private var approvals: [AccountApproval]

    @State private var showEdit = false
    @State private var showMyMember = false
    @State private var showMembershipTypeChoice = false
    @State private var requestedMember: Member?
    @State private var showDeleteAccountConfirmation = false
    @State private var showSetPassword = false
    @State private var showRequestSent = false

    /// The Benutzerverwaltung entry an admin confirmed as this account's
    /// (`AccessPolicy.approvedMember`). A name/email match alone is not
    /// enough — registration verifies neither, so without an approval nobody
    /// may open (or edit) a roster entry's personal data from here.
    private var approvedMember: Member? {
        currentUser.flatMap { AccessPolicy.approvedMember(for: $0, roster: members, approvals: approvals, users: allUsers) }
    }

    /// An unapproved account that plausibly belongs to a roster entry (or has
    /// requested membership) — shown "Freigabe ausstehend", never the data.
    private var awaitingApproval: Bool {
        guard let user = currentUser, approvedMember == nil else { return false }
        return AccessPolicy.suggestedMember(for: user, roster: members) != nil
    }

    var body: some View {
        Form {
            if let user = currentUser {
                Section {
                    HStack(spacing: Theme.Spacing.l) {
                        ZStack {
                            Circle()
                                .fill(Theme.brandFill)
                            Text(user.displayName.prefix(1).uppercased())
                                .font(.title)
                                .bold()
                                .foregroundStyle(.white)
                        }
                        .frame(width: 70, height: 70)

                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(user.displayName)
                                .font(.title3)
                                .bold()
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TagLabel(roleLabel(user.role.rawValue))
                        }
                    }
                    .padding(.vertical, Theme.Spacing.s)
                }

                Section("Kontoinformationen") {
                    LabeledContent("E-Mail", value: user.email)
                    LabeledContent("Mitglied seit",
                                   value: user.createdAt.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Teams", value: "\(user.memberships.count)")
                    LabeledContent("Teilnahmen", value: "\(user.participations.count)")
                    LabeledContent("Grazer VSC") {
                        let isMember = approvedMember?.memberOfGVSC ?? false
                        Label(isMember ? "Mitglied" : "Kein Mitglied",
                              systemImage: isMember ? "checkmark.seal.fill" : "xmark.seal")
                            .foregroundStyle(isMember ? Theme.Palette.success : .secondary)
                    }
                }

                calendarFeedSection(for: user)

                Section {
                    Button {
                        showEdit = true
                    } label: {
                        Label("Profil bearbeiten", systemImage: "pencil")
                    }

                    // Only an admin-approved link opens roster data (see
                    // `approvedMember`); a plausible but unapproved match just
                    // says it's waiting for an admin.
                    if user.passwordHash.isEmpty {
                        Button {
                            showSetPassword = true
                        } label: {
                            Label("Passwort festlegen", systemImage: "key")
                        }
                    }
                    if let member = approvedMember {
                        Button {
                            requestedMember = member
                            showMyMember = true
                        } label: {
                            Label("Vereinsdaten bearbeiten", systemImage: "square.and.pencil")
                        }
                    } else if awaitingApproval {
                        Label("Freigabe ausstehend: Ein Admin muss bestätigen, dass dieses Konto zu deinem Eintrag in der Benutzerverwaltung gehört.",
                              systemImage: "hourglass")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            showMembershipTypeChoice = true
                        } label: {
                            Label("Mitgliedschaft beantragen", systemImage: "person.badge.plus")
                        }
                    }

                }

                Section {
                    Button(role: .destructive) {
                        onLogout()
                    } label: {
                        Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteAccountConfirmation = true
                    } label: {
                        Label("Konto löschen", systemImage: "trash")
                    }
                } footer: {
                    Text("Löscht dein Konto endgültig, inklusive aller Team-Mitgliedschaften und Event-Teilnahmen.")
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Account")
        .sheet(isPresented: $showSetPassword) {
            if let user = currentUser {
                // Already signed in (e.g. via Apple on this device) — no
                // activation code needed.
                SetPasswordView(user: user, requiresActivationCode: false) { _ in }
            }
        }
        .alert("Antrag gesendet", isPresented: $showRequestSent) {
        } message: {
            Text("Ein Admin prüft deinen Antrag und bestätigt dein Konto.")
        }
        .sheet(isPresented: $showEdit) {
            if let user = currentUser {
                EditAccountView(user: user)
            }
        }
        .sheet(isPresented: $showMyMember) {
            // Uses requestedMember (set right before showMyMember = true, by
            // either button above) rather than re-deriving via
            // Member.first(matching:in:) here — a freshly-inserted Member
            // from requestMembership(for:as:) isn't guaranteed to already be
            // reflected in the `members` @Query by the time this closure
            // first runs, so re-deriving here could flash the "not found"
            // fallback right after a successful request.
            if let member = requestedMember {
                MyMemberView(member: member, currentUser: currentUser)
            } else {
                ContentUnavailableView("Kein Vereinsdateneintrag gefunden",
                                       systemImage: "exclamationmark.triangle")
            }
        }
        // Helfer vs. Sportler selection for a brand-new self-request — sets
        // the new Member's defaultFunction so it isn't left blank/ambiguous,
        // matching the field's own stated purpose ("Default TeamMembership.role
        // for this person"). Both choices lead to the exact same
        // requestMembership(for:as:) call, just a different `role` argument —
        // deliberately no branch that only allows one or the other, per user
        // request ("A registration for member should be possible in both cases").
        .confirmationDialog("Mitgliedschaft beantragen", isPresented: $showMembershipTypeChoice, titleVisibility: .visible) {
            if let user = currentUser {
                Button("Als Sportler:in") { requestMembership(for: user, as: .player) }
                Button("Als Helfer:in") { requestMembership(for: user, as: .coach) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Als Sportler:in oder als Helfer:in (Trainer:in/Betreuer:in) registrieren?")
        }
        // Self-service account deletion (account-tiers refactor, decision
        // #7 — App Store guideline 5.1.1(v): any app offering in-app
        // account creation must also let the user delete that account from
        // within the app). Reuses the same UserService.delete UserListView
        // already calls for admin-initiated deletion, then routes through
        // onLogout — which also clears the appleUserIdentifier/localUserID
        // @AppStorage keys (RootView), so a deleted account is never
        // "resumed" on next launch.
        .confirmationDialog("Konto löschen?", isPresented: $showDeleteAccountConfirmation, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let user = currentUser {
                    UserService.delete(user, modelContext: modelContext)
                }
                onLogout()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dein Konto wird endgültig gelöscht, inklusive aller Team-Mitgliedschaften und Event-Teilnahmen. Das kann nicht rückgängig gemacht werden.")
        }
    }

    /// Self-service roster signup for an account with no matching `Member`
    /// entry yet ("Mitgliedschaft beantragen"). `role` is the Sportler/Helfer
    /// choice from the confirmationDialog above, stored as the new Member's
    /// `defaultFunction` (using the same raw strings as `MembershipRole` —
    /// "player"/"coach" — so it stays directly usable as a
    /// `MembershipRole.normalize(...)` input if a future admin-assignment
    /// flow ever pre-fills from it, matching this codebase's existing role
    /// vocabulary rather than inventing a separate one). Only applied to a
    /// freshly-created entry — an existing matched Member already has
    /// admin-managed data, so its defaultFunction is left untouched.
    /// `Member.resolveMembershipRequest` re-derives the match live rather
    /// than trusting `matchedMember`'s value from whenever the button last
    /// rendered (e.g. an admin could have added a matching roster entry in
    /// between) — see that function's doc comment for why this re-check
    /// matters. Calls `Member.checkMembership` right after so
    /// `user.isGrazerVSCMember`/AccountView's status row update immediately,
    /// without waiting for the next login.
    private func requestMembership(for user: User, as role: MembershipRole) {
        switch Member.resolveMembershipRequest(for: user, in: members, defaultFunction: role.rawValue) {
        case .existing:
            // A roster entry already matches by name/email — never open its
            // data for an unapproved account; an admin links it instead.
            showRequestSent = true
        case .new(let member):
            modelContext.insert(member)
            guard MemberService.save(member, modelContext: modelContext) else { return }
            let allMembers = (try? modelContext.fetch(FetchDescriptor<Member>())) ?? []
            MemberBackup.snapshot(members: allMembers)
            // The person's own brand-new entry — fine to fill in; full access
            // still needs an admin's approval.
            requestedMember = member
            showMyMember = true
        }
    }

    private func roleLabel(_ role: String) -> LocalizedStringKey {
        switch role {
        case "admin": return "Administrator"
        case "coach": return "Trainer:in"
        default: return "Mitglied"
        }
    }

    // MARK: - Calendar feed (architecture-review.md §5 P2)

    @ViewBuilder
    private func calendarFeedSection(for user: User) -> some View {
        Section("Kalender-Abo") {
            if user.calendarToken.isEmpty {
                Text("Trage alle Trainings und Turniere, die du sehen kannst, automatisch in deine Kalender-App ein.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    generateCalendarToken(for: user)
                } label: {
                    Label("Kalender-Link erstellen", systemImage: "calendar.badge.plus")
                }
            } else {
                LabeledContent("Kalender-URL") {
                    Text(calendarFeedURL(for: user))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                ShareLink(item: calendarFeedURL(for: user)) {
                    Label("Kalender-Link teilen", systemImage: "square.and.arrow.up")
                }
                Button {
                    generateCalendarToken(for: user)
                } label: {
                    Label("Neuen Link erzeugen", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityHint("Ungültig macht den bisherigen Link, falls er versehentlich weitergegeben wurde.")
                if ServerConfig.clubMembersAPIHost == nil {
                    Label("Der Server für den Kalender-Abgleich ist noch nicht eingerichtet — die URL oben zeigt einen Platzhalter.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.warning)
                }
            }
        }
    }

    /// `webcal://` so a tap opens straight in the device's default calendar
    /// app instead of a browser. Placeholder host when `ServerConfig`
    /// hasn't been pointed at a real deployment yet — see that file's doc
    /// comment; the token itself is real and ready either way.
    private func calendarFeedURL(for user: User) -> String {
        let host = ServerConfig.clubMembersAPIHost ?? "DEIN-SERVER.example"
        return "webcal://\(host)/calendar/\(user.calendarToken).ics"
    }

    private func generateCalendarToken(for user: User) {
        user.calendarToken = UUID().uuidString
        UserService.save(user, modelContext: modelContext)
    }
}
