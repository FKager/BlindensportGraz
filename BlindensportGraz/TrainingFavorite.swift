import Foundation
import SwiftData

/// A shared, capped (max 5) quick-fill shortcut for AddTrainingView, keyed by
/// name+sport, populated automatically (not manually curated) from whatever
/// trainings actually get created — see `recordUsage`. Stores time-of-day
/// only (hour/minute), not a full Date: a favorite gets reapplied against a
/// freshly-computed suggested date every time it's picked, so baking in a
/// stale calendar date would be wrong (same reasoning as `Training` storing
/// `durationMinutes` instead of a redundant absolute `endDate`). No
/// `@available(iOS 26, *)` needed — unlike SportEvent/Training/Tournament,
/// this is a plain final class with no `@Model` inheritance, so it isn't
/// subject to that restriction.
@Model
final class TrainingFavorite {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var sport: String = ""
    var startHour: Int = 18
    var startMinute: Int = 0
    var endHour: Int = 19
    var endMinute: Int = 30
    // Calendar.current's `.weekday` component convention (1 = Sunday...7 =
    // Saturday), stored directly in that form so it plugs straight back into
    // Calendar arithmetic in suggestedStartDate without any custom mapping.
    var weekday: Int = 2 // Monday
    var location: String = ""
    var street: String = ""
    var zip: String = ""
    var city: String = ""
    var country: String = ""
    var lastUsedAt: Date = Date.now

    // The manually-checked "Beteiligte Teams" selection at save time (NOT
    // including sport-driven auto-assigned teams — those are re-derived from
    // `sport` via Team.autoAssignTeamNames every time regardless, so storing
    // them here too would just be redundant). No explicit @Relationship
    // needed, same as SportEvent.teams — a plain unidirectional reference,
    // no inverse required since Team never needs to look up its favorites.
    var teams: [Team] = []

    init(id: UUID = UUID(), title: String, sport: String,
         startHour: Int, startMinute: Int, endHour: Int, endMinute: Int,
         weekday: Int = 2, location: String = "", street: String = "", zip: String = "", city: String = "", country: String = "",
         teams: [Team] = [], lastUsedAt: Date = .now) {
        self.id = id
        self.title = title
        self.sport = sport
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.weekday = weekday
        self.location = location
        self.street = street
        self.zip = zip
        self.city = city
        self.country = country
        self.teams = teams
        self.lastUsedAt = lastUsedAt
    }
}

extension TrainingFavorite {
    static let maxCount = 5

    /// Called from AddTrainingView's save action every time a training is
    /// created. Matches an existing favorite by case-insensitive trimmed
    /// title + exact sport: if found, refreshes its stored time + `weekday` +
    /// address + `teams` + `lastUsedAt` in place; if not found and the list
    /// has room, inserts a new one; if not found and already at `maxCount`,
    /// evicts the least-recently-used favorite first (returned as
    /// `evictedID` so the caller can push its deletion to CloudKit too).
    ///
    /// `teams` should be the manually-checked "Beteiligte Teams" selection
    /// only, NOT the final sport-driven auto-assigned set — see the
    /// `teams` property's doc comment on why auto-assigned teams are
    /// deliberately excluded here.
    ///
    /// Returns the favorite that was inserted/updated (nil if `modelContext`
    /// couldn't be queried) alongside the id of any favorite evicted to make
    /// room, so CloudKitSync pushes stay in sync with the local change.
    @discardableResult
    static func recordUsage(title: String, sport: String, startDate: Date, durationMinutes: Int,
                             location: String = "", street: String = "", zip: String = "", city: String = "", country: String = "",
                             teams: [Team] = [], in modelContext: ModelContext) -> (favorite: TrainingFavorite?, evictedID: UUID?) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty,
              let existingFavorites = try? modelContext.fetch(FetchDescriptor<TrainingFavorite>()) else {
            return (nil, nil)
        }

        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: startDate)
        let endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes) * 60)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endDate)
        let weekday = calendar.component(.weekday, from: startDate)

        if let match = existingFavorites.first(where: {
            $0.title.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(trimmedTitle) == .orderedSame
                && $0.sport == sport
        }) {
            match.startHour = startComponents.hour ?? match.startHour
            match.startMinute = startComponents.minute ?? match.startMinute
            match.endHour = endComponents.hour ?? match.endHour
            match.endMinute = endComponents.minute ?? match.endMinute
            match.weekday = weekday
            match.location = location
            match.street = street
            match.zip = zip
            match.city = city
            match.country = country
            match.teams = teams
            match.lastUsedAt = .now
            return (match, nil)
        }

        var evictedID: UUID?
        if existingFavorites.count >= maxCount, let leastRecentlyUsed = existingFavorites.min(by: { $0.lastUsedAt < $1.lastUsedAt }) {
            evictedID = leastRecentlyUsed.id
            modelContext.delete(leastRecentlyUsed)
        }

        let favorite = TrainingFavorite(
            title: trimmedTitle, sport: sport,
            startHour: startComponents.hour ?? 18, startMinute: startComponents.minute ?? 0,
            endHour: endComponents.hour ?? 19, endMinute: endComponents.minute ?? 30,
            weekday: weekday, location: location, street: street, zip: zip, city: city, country: country, teams: teams
        )
        modelContext.insert(favorite)
        return (favorite, evictedID)
    }

    /// Produces the date AddTrainingView pre-fills when the favorite is
    /// tapped: the favorite's stored weekday, at its stored time-of-day, in
    /// the calendar week immediately following `reference`'s (today's) own
    /// week — i.e. "same weekday, next week", not "the next occurrence of
    /// that weekday" (which could resolve to later THIS week) and not a
    /// fixed +7-days-then-search-forward offset (which could overshoot into
    /// the week after next). Uses `.yearForWeekOfYear`/`.weekOfYear` (not
    /// plain `.year`/`.weekOfYear`) so this stays correct across a
    /// year-boundary week (e.g. a week that starts in late December and
    /// ends in early January). Factored out as a plain static function
    /// (rather than inline SwiftUI code) so it's independently testable.
    static func suggestedStartDate(startHour: Int, startMinute: Int, weekday: Int, from reference: Date = .now,
                                    calendar: Calendar = .current) -> Date {
        let nextWeekReference = calendar.date(byAdding: .weekOfYear, value: 1, to: reference) ?? reference
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: nextWeekReference)
        components.weekday = weekday
        components.hour = startHour
        components.minute = startMinute
        components.second = 0
        return calendar.date(from: components) ?? nextWeekReference
    }

    /// Duration in minutes implied by this favorite's stored start/end
    /// time-of-day, clamped to AddTrainingView's Stepper range (15...240) so
    /// an edge-case (e.g. end time before start time) never produces a
    /// negative or wildly out-of-range value.
    var durationMinutes: Int {
        let raw = (endHour * 60 + endMinute) - (startHour * 60 + startMinute)
        return min(max(raw, 15), 240)
    }

    /// Backfills the Favoriten list from real `Training` records already in
    /// the store, via the exact same `recordUsage` path a live training
    /// creation goes through — useful right after this feature shipped
    /// (existing trainings predate any auto-recorded favorite, so their
    /// favorite either doesn't exist yet or has stale/default data from an
    /// earlier version of this feature) or any time the list should just be
    /// rebuilt from what's actually being trained recently, without
    /// re-creating trainings by hand.
    ///
    /// `trainings` is expected sorted newest-first (as TrainingsListView's
    /// own `@Query` already provides). Dedupes by the same title+sport key
    /// `recordUsage` matches on — only the newest instance of each combo
    /// counts — then processes up to `maxCount` distinct combos **oldest of
    /// the selected batch first**, so `recordUsage`'s own `lastUsedAt`
    /// bookkeeping ends up ranking the newest training as most recently
    /// used, exactly as if a user had tapped through creating these
    /// trainings themselves in that order.
    ///
    /// Returns each recorded/updated favorite paired with any id evicted to
    /// make room, mirroring `recordUsage`'s own return shape, so the caller
    /// can push every change (and every eviction) to CloudKit.
    @available(iOS 26, *)
    @discardableResult
    static func populateFromRecentTrainings(_ trainings: [Training], in modelContext: ModelContext) -> [(favorite: TrainingFavorite?, evictedID: UUID?)] {
        var seenKeys = Set<String>()
        var distinctNewestFirst: [Training] = []
        for training in trainings {
            let key = "\(training.title.trimmingCharacters(in: .whitespaces).lowercased())|\(training.sport)"
            guard seenKeys.insert(key).inserted else { continue }
            distinctNewestFirst.append(training)
            if distinctNewestFirst.count == maxCount { break }
        }

        return distinctNewestFirst.reversed().map { training in
            recordUsage(
                title: training.title, sport: training.sport, startDate: training.startDate,
                durationMinutes: training.durationMinutes,
                location: training.location, street: training.street, zip: training.zip, city: training.city, country: training.country,
                teams: training.teams, in: modelContext
            )
        }
    }
}
