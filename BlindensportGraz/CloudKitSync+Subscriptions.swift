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
    /// One subscription per (user, record type, event) — NOT per team —
    /// with an `ANY teamIDs IN %@` predicate against the user's full
    /// current set of team ids, re-saved with the same deterministic
    /// `subscriptionID` every time this runs. Saving over an existing
    /// subscription ID replaces its predicate, so this naturally keeps the
    /// subscription in sync with team joins/leaves — no separate cleanup
    /// logic needed, unlike a per-team subscription scheme would require. A
    /// subscriptionID keyed by this app's own stable `user.id` (not a
    /// per-device id) is deliberate: the same person using the app on two
    /// devices under the same iCloud account should update the SAME
    /// subscription, not create a second one — CloudKit already delivers a
    /// subscription's pushes to every device registered under that account
    /// for this container, so there's no need for a per-device identity
    /// here. No-op if the user currently has no team memberships at all.
    func ensureTrainingTournamentSubscriptions(for user: User) async {
        let teamIDStrings = user.memberships.map { $0.team.id.uuidString }
        guard !teamIDStrings.isEmpty else { return }
        let teamsFormat = "ANY \(CKSchema.Training.teamIDs) IN %@"

        // Creation alerts (original behaviour) plus, since architecture-review.md
        // §5, a second subscription per type that fires when an existing
        // Training/Tournament is *edited* — an admin changing the time or venue
        // in the detail view calls `*Service.save` → `pushX` → a `.changedKeys`
        // update to the same CKRecord, which is a distinct server event from the
        // first insert, so the two subscriptions never both fire for one change.
        // Kept as separate subscription IDs (not one with both fire options) so
        // each can carry its own "neu"/"geändert" alert text — a pure alert push
        // can't branch on `queryNotificationReason` with no app code running.
        // No cancellation subscription for Tournament: it has no "cancelled"
        // status value (Tournament.status is planned/ongoing/finished, see
        // Tournament.swift) — only Training's Abgesagt gets its own alert
        // (user request 2026-09-10).
        // No plain-delete subscription for either type: `TrainingService`/
        // `TournamentService` delete only locally (no CloudKit delete path
        // exists for these types), so `.firesOnRecordDeletion` would never fire.
        await ensureSubscription(recordType: CKSchema.Training.recordType,
                                 predicate: NSPredicate(format: teamsFormat, teamIDStrings),
                                 titleKey: "training_created_title", bodyKey: "training_created_body",
                                 subscriptionID: "training-created-\(user.id.uuidString)",
                                 options: .firesOnRecordCreation)
        await ensureSubscription(recordType: CKSchema.Tournament.recordType,
                                 predicate: NSPredicate(format: teamsFormat, teamIDStrings),
                                 titleKey: "tournament_created_title", bodyKey: "tournament_created_body",
                                 subscriptionID: "tournament-created-\(user.id.uuidString)",
                                 options: .firesOnRecordCreation)

        // The plain "updated" alert explicitly excludes the cancelled state —
        // that transition gets its own distinct alert below instead of also
        // triggering this generic one, so a member sees exactly one push per
        // save, not a duplicate "Training geändert" alongside "Training
        // abgesagt". A record with no `status` value yet (synced before this
        // field existed) compares not-equal, so it still matches here as
        // expected for an ordinary edit.
        await ensureSubscription(recordType: CKSchema.Training.recordType,
                                 predicate: NSPredicate(format: "\(teamsFormat) AND \(CKSchema.Training.status) != %@",
                                                        teamIDStrings, Training.cancelledStatus),
                                 titleKey: "training_updated_title", bodyKey: "training_updated_body",
                                 subscriptionID: "training-updated-\(user.id.uuidString)",
                                 options: .firesOnRecordUpdate)
        await ensureSubscription(recordType: CKSchema.Tournament.recordType,
                                 predicate: NSPredicate(format: teamsFormat, teamIDStrings),
                                 titleKey: "tournament_updated_title", bodyKey: "tournament_updated_body",
                                 subscriptionID: "tournament-updated-\(user.id.uuidString)",
                                 options: .firesOnRecordUpdate)

        // The cancellation alert (user request 2026-09-10): fires whenever a
        // save results in `status == "cancelled"` — whether that's the same
        // edit that also changed the time/venue, or a plain status-only
        // change from the list's swipe action. Distinct subscriptionID/alert
        // text from "updated" so members get an unambiguous "Training
        // abgesagt", not a generic "geändert".
        await ensureSubscription(recordType: CKSchema.Training.recordType,
                                 predicate: NSPredicate(format: "\(teamsFormat) AND \(CKSchema.Training.status) == %@",
                                                        teamIDStrings, Training.cancelledStatus),
                                 titleKey: "training_cancelled_title", bodyKey: "training_cancelled_body",
                                 subscriptionID: "training-cancelled-\(user.id.uuidString)",
                                 options: .firesOnRecordUpdate)
    }

    /// Alert text is resolved by iOS itself at display time from
    /// `Localizable.xcstrings` via `titleLocalizationKey`/
    /// `alertLocalizationKey`, with `alertLocalizationArgs` naming the
    /// pushed record's OWN field keys ("title"/"location") to substitute
    /// into that localized format string's `%1$@`/`%2$@` placeholders — no
    /// app code runs to construct this, which is what makes it work even
    /// when the recipient's app is fully terminated.
    private func ensureSubscription(recordType: String, predicate: NSPredicate,
                                    titleKey: String, bodyKey: String, subscriptionID: String,
                                    options: CKQuerySubscription.Options) async {
        let subscription = CKQuerySubscription(recordType: recordType, predicate: predicate,
                                                subscriptionID: subscriptionID,
                                                options: options)
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
