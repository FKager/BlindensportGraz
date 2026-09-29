import SwiftUI
import SwiftData

/// Every screen that gets pushed onto a `NavigationStack`. Links use
/// `NavigationLink(value: AppRoute.…)` and the destination view is only built
/// when the link is actually followed — unlike `NavigationLink { … }`, which
/// constructs its destination for every visible row.
///
/// Destinations are registered exactly once per stack via
/// `.appRouteDestinations(currentUser:)` on the stack's root view (see
/// `MainTabView` and `VereinSplitView`). Never add that modifier to a pushed
/// view — list screens like `EventsListView` are pushed from several places,
/// and a second registration for `AppRoute` in the same stack is an error.
enum AppRoute: Hashable {
    // Lists
    case eventsList
    case tournamentsList
    case trainingsList
    case teamsList
    case membersList
    case personenList
    case userList
    case memberChangeRequests
    case roleChangeLog
    case fullBackup
    case welcomeSettings
    case budget

    // Details
    case event(SportEvent)
    case training(Training)
    case tournament(Tournament)
    case team(Team)
    case member(Member)
    case memberChangeRequest(MemberChangeRequest, member: Member?)
}

extension View {
    /// Registers the destinations for all `AppRoute`s. Apply once, to the root
    /// view inside each `NavigationStack`.
    func appRouteDestinations(currentUser: User?) -> some View {
        navigationDestination(for: AppRoute.self) { route in
            AppRouteDestination(route: route, currentUser: currentUser)
        }
    }
}

private struct AppRouteDestination: View {
    let route: AppRoute
    let currentUser: User?

    var body: some View {
        switch route {
        case .eventsList: EventsListView(currentUser: currentUser)
        case .tournamentsList: TournamentsListView(currentUser: currentUser)
        case .trainingsList: TrainingsListView(currentUser: currentUser)
        case .teamsList: TeamsListView(currentUser: currentUser)
        case .membersList:
            // Admin-only screens take a non-optional user; they're only ever
            // linked from the Verein hub, which always has one.
            if let currentUser { MembersListView(currentUser: currentUser) }
        case .personenList: PersonenListView()
        case .userList:
            if let currentUser { UserListView(currentUser: currentUser) }
        case .memberChangeRequests: MemberChangeRequestsView(currentUser: currentUser)
        case .roleChangeLog: RoleChangeLogView()
        case .fullBackup: FullBackupView()
        case .welcomeSettings: WelcomeScreenSettingsView()
        case .budget: BudgetView(currentUser: currentUser)
        case .event(let event): EventDetailView(event: event, currentUser: currentUser)
        case .training(let training): TrainingDetailView(training: training, currentUser: currentUser)
        case .tournament(let tournament): TournamentDetailView(tournament: tournament, currentUser: currentUser)
        case .team(let team): TeamDetailView(team: team, currentUser: currentUser)
        case .member(let member): MemberDetailView(member: member)
        case .memberChangeRequest(let request, let member):
            MemberChangeRequestDetailView(request: request, member: member, currentUser: currentUser)
        }
    }
}
