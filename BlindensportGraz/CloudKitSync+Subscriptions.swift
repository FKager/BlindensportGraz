import CloudKit
import Foundation

extension CloudKitSync {
    /// Ensures a `CKQuerySubscription` exists for `user`'s current team
    /// memberships, for both Training and Tournament creation — so members
    /// of those teams get a native push notification when one is created,
    /// including on a device where the app isn't running at all (see
    /// `PushNotifications.swift`'s doc comment for why this uses plain
    /// "alert" subscriptions instead of a silent-push +
    /// client-constructed-notification pattern).
    ///
    /// One subscription per (user, record type) — NOT per team — with an
    /// `ANY teamIDs IN %@` predicate against the user's full current set of
    /// team ids, re-saved with the same deterministic `subscriptionID`
    /// (`"training-created-<user.id>"`) every time this runs. Saving over an
    /// existing subscription ID replaces its predicate, so this naturally
    /// keeps the subscription in sync with team joins/leaves — no separate
    /// cleanup logic needed, unlike a per-team subscription scheme would
    /// require. A subscriptionID keyed by this app's own stable `user.id`
    /// (not a per-device id) is deliberate: the same person using the app on
    /// two devices under the same iCloud account should update the SAME
    /// subscription, not create a second one — CloudKit already delivers a
    /// subscription's pushes to every device registered under that account
    /// for this container, so there's no need for a per-device identity here.
    /// No-op if the user currently has no team memberships at all.
    func ensureTrainingTournamentSubscriptions(for user: User) async {
        let teamIDStrings = user.memberships.map { $0.team.id.uuidString }
        guard !teamIDStrings.isEmpty else { return }
        await ensureCreationSubscription(recordType: CKSchema.Training.recordType, teamIDStrings: teamIDStrings,
                                          titleKey: "training_created_title", bodyKey: "training_created_body",
                                          subscriptionID: "training-created-\(user.id.uuidString)")
        await ensureCreationSubscription(recordType: CKSchema.Tournament.recordType, teamIDStrings: teamIDStrings,
                                          titleKey: "tournament_created_title", bodyKey: "tournament_created_body",
                                          subscriptionID: "tournament-created-\(user.id.uuidString)")
    }

    /// Alert text is resolved by iOS itself at display time from
    /// `Localizable.xcstrings` via `titleLocalizationKey`/
    /// `alertLocalizationKey`, with `alertLocalizationArgs` naming the
    /// pushed record's OWN field keys ("title"/"location") to substitute
    /// into that localized format string's `%1$@`/`%2$@` placeholders — no
    /// app code runs to construct this, which is what makes it work even
    /// when the recipient's app is fully terminated.
    private func ensureCreationSubscription(recordType: String, teamIDStrings: [String],
                                             titleKey: String, bodyKey: String, subscriptionID: String) async {
        let predicate = NSPredicate(format: "ANY \(CKSchema.Training.teamIDs) IN %@", teamIDStrings)
        let subscription = CKQuerySubscription(recordType: recordType, predicate: predicate,
                                                subscriptionID: subscriptionID,
                                                options: .firesOnRecordCreation)
        let info = CKSubscription.NotificationInfo()
        info.titleLocalizationKey = titleKey
        info.alertLocalizationKey = bodyKey
        info.alertLocalizationArgs = [CKSchema.Training.title, CKSchema.Training.location]
        info.soundName = "default"
        info.shouldBadge = true
        subscription.notificationInfo = info
        // audit.md SwiftData & CloudKit Finding 8: a failed registration
        // used to be a single silent `print()`, permanently killing
        // creation alerts for this device with no recovery path. Reuses
        // Phase 6's shared retry/backoff helper — a subscription save is a
        // one-shot async throwing call, the exact shape `performWithRetry`
        // was built for.
        await performWithRetry("subscription save for \(subscriptionID)") {
            try await self.publicDB.save(subscription)
        }
    }
}
