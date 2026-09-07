// Plan 1.2, ovation#88. IDENTIFY, CHECKPOINT, BACK UP, THEN OPEN, in that order,
// with a refusal at each point that must not be walked past.
//
// WHY THIS FILE EXISTS AT ALL. ovation#52 built the identify step and ovation#57
// built the backup step, and both closed with nothing running them. So
// `StoreSchemaGuard` was written, tested, and called by NOTHING: the check that
// stops Core Data creating its tables inside another app's database was inert
// while reading, to anyone auditing the repository, exactly like a live
// safeguard. Built is not wired, and wired is not proven (L3).
//
// THE ORDER IS THE REQUIREMENT, not an implementation detail, because each step
// exists to protect the one after it.
//
//   IDENTIFY first, because every later step WRITES. Core Data does not throw on
//   a foreign file: it creates its missing tables inside whatever it is handed
//   and opens what looks like an empty store, so the other app's data is gone
//   and nothing reports a fault. That has happened twice on this Mac.
//
//   CHECKPOINT second, because a store whose write ahead log still holds the
//   rows produces an archive that restores an EMPTY database and verifies clean
//   (measured, see StoreCheckpoint). Backing up first would manufacture the
//   reassuring corrupt backup the verification cannot see (L63).
//
//   BACK UP third, because opening can migrate, and a migration is the moment
//   the only copy of Dan's invoices is at risk (L5).
//
//   OPEN last.
//
// EVERY COLLABORATOR IS INJECTED. Not for tidiness: a test that had to make a
// real backup fail would have to damage the machine to do it, and a sequence
// that constructed its own collaborators would be beyond every refusal they
// could offer (L196).
import Foundation
import SwiftData

@MainActor
struct StoreLaunchSequence {

    /// What the launch did. A refusal names the step that refused, because the
    /// remedies are unrelated: a foreign store is a file to move, and a blocked
    /// checkpoint is another process to close (L11).
    enum Outcome: Equatable {
        case opened
        case refused(step: Step, detail: String)

        enum Step: String, Equatable {
            case identify
            case checkpoint
        }
    }

    let storeURL: URL
    let problems: ProblemsStore
    let checkpoint: @Sendable (URL) -> StoreCheckpoint.Outcome
    let takeBackup: @Sendable (Date) throws -> URL
    let openContainer: @Sendable (URL) throws -> ModelContainer
    let identify: @Sendable (URL) -> StoreSchemaGuard.Verdict

    @discardableResult
    func run(now: Date) -> Outcome {
        // 1. IDENTIFY.
        let verdict = identify(storeURL)
        if !StoreSchemaGuard.mayOpenForWriting(verdict) {
            let sentence = StoreSchemaGuard.refusalSentence(for: verdict, at: storeURL.path)
                ?? "The store at \(storeURL.path) could not be identified."
            _ = problems.raise(kind: kind(for: verdict), subject: storeURL.path,
                               sentence: sentence, now: now)
            return .refused(step: .identify, detail: sentence)
        }

        // 2. CHECKPOINT. `noStoreFile` is the ordinary first launch and is not a
        // failure: raising one here would fire on every fresh install, which is
        // a guard speaking on the commonest case rather than the dangerous one.
        switch checkpoint(storeURL) {
        case .checkpointed, .noStoreFile:
            break
        case .failed(let detail):
            let sentence = "The store could not be consolidated before backing up, "
                + "so the backup was not taken: \(detail). Nothing has been opened or changed."
            _ = problems.raise(kind: .unreadableStore, subject: storeURL.path,
                               sentence: sentence, now: now)
            return .refused(step: .checkpoint, detail: detail)
        }

        // 3. BACK UP. A failure here is REPORTED and the launch continues, which
        // is a deliberate choice against the defensible opposite. Refusing to
        // open would leave Dan unable to invoice because a folder on a Synology
        // was unreachable, which is a worse failure than the one being guarded
        // against.
        //
        // It becomes a refusal once ovation#105 can say whether opening would
        // run a MIGRATION, because that is the case where opening without a
        // backup can lose data rather than merely leave it unprotected. Until
        // then this comment is the record that the coupling is missing, not an
        // argument that it is unnecessary.
        do {
            _ = try takeBackup(now)
        } catch {
            _ = problems.raise(kind: .backupFailed, subject: storeURL.path,
                               sentence: Self.backupSentence(for: error), now: now)
        }

        // 4. OPEN.
        do {
            _ = try openContainer(storeURL)
        } catch {
            let sentence = "The store was identified as Ovation's and still would not open: "
                + "\(error.localizedDescription)"
            _ = problems.raise(kind: .unreadableStore, subject: storeURL.path,
                               sentence: sentence, now: now)
            return .refused(step: .identify, detail: sentence)
        }

        return .opened
    }

    /// Two labels, not one (ovation#87). An archive that could not be WRITTEN and
    /// one that was written and did not VERIFY are different failures, and the
    /// person reading them does different things about each.
    static func backupSentence(for error: Error) -> String {
        switch error {
        case BackupError.couldNotWrite(let path):
            return "The backup could not be written to \(path). "
                + "Ovation opened anyway, so nothing is lost, but there is no backup from today."
        case BackupError.requiredMemberMissing(let path):
            return "The backup was refused because \(path) is missing from the data folder. "
                + "Ovation opened anyway, so nothing is lost, but there is no backup from today."
        default:
            return "The backup did not complete: \(error.localizedDescription). "
                + "Ovation opened anyway, so nothing is lost, but there is no backup from today."
        }
    }

    /// One verdict, one kind. The four already exist for exactly this, and a
    /// single collapsed "could not open the store" would lose the distinction
    /// the guard went to the trouble of measuring (L11).
    private func kind(for verdict: StoreSchemaGuard.Verdict) -> ProblemKind {
        switch verdict {
        case .foreign: return .foreignStore
        case .notADatabase: return .storeIsNotADatabase
        case .unreadable: return .unreadableStore
        case .unidentifiable: return .unidentifiableStore
        case .noStoreFile, .empty, .ovation: return .unidentifiableStore
        }
    }
}
