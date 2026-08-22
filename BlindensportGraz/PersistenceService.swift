import SwiftData
import os

/// Shared save+sync core every per-model `*Service` (e.g. `TeamService`,
/// `TrainingService`) is built on — audit.md Architecture Finding 1 (60
/// view-layer call sites drove `CloudKitSync.shared` directly, no
/// service/viewmodel layer), Finding 6 (98 `try?` silent-failure sites, no
/// consistent error policy), and Finding 8 (save-then-sync duplicated
/// verbatim everywhere).
///
/// One generic core, but NOT one generic `SyncedModelService<T>` type at
/// call sites — the 12 models' `CloudKitSync.shared.pushX`/`deleteX`
/// functions don't share a uniform name or signature (`pushUserIdentity`
/// for `User`, `pushMember` for `Member`, `deleteX(_ id: UUID)` with no
/// delete at all for some types), so a single generic type would need an
/// awkward closure at every call site anyway. Per-model thin services give
/// the "TrainingService.save(_:)" call shape the phase asked for, while
/// this file keeps the actual save/log/signal/push logic in exactly one
/// place — a per-model service is ~10 lines of pure forwarding, see
/// TeamService.swift for the template every other one follows.
enum PersistenceService {
    static let logger = Logger(subsystem: "it.a11y.BlindensportGraz", category: "PersistenceService")

    /// Saves the model context, then — ONLY on success — calls `push`. A
    /// local save failure is logged and reported via `ServiceFailureSignal`;
    /// the CloudKit push is never attempted in that case, since there's
    /// nothing valid to push yet (this phase's explicit requirement).
    @discardableResult
    static func saveAndPush(modelContext: ModelContext, modelName: String, failureMessage: String,
                             push: () -> Void) -> Bool {
        runAndSignal(operation: { try modelContext.save() }, modelName: modelName,
                     failureMessage: failureMessage, onSuccess: push)
    }

    /// Same shape for deletes — caller has already called
    /// `modelContext.delete(model)` before this; saves that removal, then —
    /// only on success — calls `remoteDelete` to push the deletion to
    /// CloudKit.
    @discardableResult
    static func deleteAndPush(modelContext: ModelContext, modelName: String, failureMessage: String,
                               remoteDelete: () -> Void) -> Bool {
        runAndSignal(operation: { try modelContext.save() }, modelName: modelName,
                     failureMessage: failureMessage, onSuccess: remoteDelete)
    }

    /// The actual shared core, factored out to take the save `operation` as
    /// a throwing closure rather than always calling `modelContext.save()`
    /// directly — this is also the seam `PersistenceServiceTests` uses to
    /// force a deterministic failure. A duplicate `@Attribute(.unique) id`
    /// insert was tried first as the "force a real SwiftData throw"
    /// technique, but SwiftData silently remaps the temporary identifier
    /// during save instead of throwing (confirmed live, see cerebrum.md's
    /// 2026-08-22 entry) — an injectable operation sidesteps needing a real
    /// SwiftData failure at all.
    @discardableResult
    static func runAndSignal(operation: () throws -> Void, modelName: String, failureMessage: String,
                              onSuccess: () -> Void) -> Bool {
        do {
            try operation()
        } catch {
            logger.error("\(modelName, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            ServiceFailureSignal.shared.report(failureMessage)
            return false
        }
        onSuccess()
        return true
    }
}
