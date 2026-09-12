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
    /// ovation#222. Makes the directories `BackupPlan` requires, immediately
    /// before the backup that refuses without them. Injected like every other
    /// step, so a test can make it fail without damaging anything (L196).
    let prepareDataDirectory: @Sendable () throws -> Void
    let takeBackup: @Sendable (Date) throws -> URL
    let openContainer: @Sendable (URL) throws -> ModelContainer
    let identify: @Sendable (URL) -> StoreSchemaGuard.Verdict
    /// ovation#107. Puts PRD 5.4's starting service types into a store that has
    /// none, and answers how many it wrote. Injected like every other step, so a
    /// test can make it fail without damaging anything (L196).
    let seed: @Sendable (ModelContainer) throws -> Int
    /// ovation#116. Records the schema version that has just opened the store,
    /// beside it, so the next launch can refuse a downgrade before opening
    /// anything. Injected like every other step.
    let recordVersion: @Sendable (URL) throws -> Void
    /// ovation#64. What is true about the year end export at this moment, read
    /// from the durable run record and from the store that has just opened.
    ///
    /// INJECTED WITH NO DEFAULT, like every other step. A default of "no notices"
    /// would be indistinguishable from a healthy export history, which is this
    /// feature's own failure mode (L168, L98).
    let exportNotices: @Sendable (ModelContainer, Date) -> [ExportNotice]
    /// ovation#208. Brings Downbeat's client roster across, and says what it did.
    ///
    /// INJECTED WITH NO DEFAULT, like every other step. A default of "no notices"
    /// would be indistinguishable from an import that ran and correctly found
    /// nothing to do, which is this feature's own commonest outcome (L168, L98).
    let importClients: @Sendable (ModelContainer) -> [ClientImportNotice]

    /// ovation#162. Hands the opened store to whoever has to act on it later.
    ///
    /// IT EXISTS BECAUSE A CONTROL NEEDS ONE. `YearEndExportCommand` runs an
    /// export over this store, and until now the container was a local inside
    /// this method: the app opened it, used it, and dropped it, so nothing after
    /// launch could read the store at all. Opening a SECOND container would be a
    /// second writer over one file, which is the thing the second instance check
    /// exists to prevent (ovation#84), so the one that is already open is handed
    /// on instead.
    ///
    /// It runs LAST, after every step above, so nothing downstream sees a store
    /// that has not been checkpointed, identified, seeded and version stamped.
    /// It defaults to doing nothing, which is what every test wants.
    var onOpened: @Sendable (ModelContainer) -> Void = { _ in }

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
        //
        // WHAT IT ANSWERS IS ALSO WHAT STEP 3 NEEDS. `noStoreFile` is the one
        // measurement that says this installation has never had a database, and
        // the backup step below reads it rather than asking the filesystem a
        // second time: two lookups can disagree, and a check whose two sides come
        // from one lookup is the only kind that cannot (L70).
        var thereIsAStoreFile = true
        switch checkpoint(storeURL) {
        case .checkpointed:
            break
        case .noStoreFile:
            thereIsAStoreFile = false
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
        //
        // A FIRST LAUNCH DOES NOT BACK UP AT ALL (ovation#137). `Ovation.store`
        // and `Ovation.store.version` are required members, so a backup taken
        // before the store exists throws `requiredMemberMissing` and this step
        // raises "the backup was refused because Ovation.store is missing" about
        // a database that has simply never been created. That would fire on the
        // one launch where a person is most likely to conclude the app is broken,
        // and "there was nothing here yet" and "the database is missing" must not
        // be the same sentence (L11).
        //
        // The skip is deliberately narrow: it is the absence of the STORE, not
        // the absence of any member. A required member missing while the store is
        // present is the genuinely alarming case, something removed from the data
        // folder, and it is still taken, still fails, and is still said out loud.
        //
        // Nothing reports the skip, and that is not the absence being swallowed:
        // an installation with no archives at all is a standing condition rather
        // than an event, and ovation#87 raises it from the backup folder, where it
        // stays true on every later launch. Saying it here would say it once, on
        // the launch where it is least informative.
        if thereIsAStoreFile {
            do {
                // PREPARE FIRST, INSIDE THE SAME ATTEMPT (ovation#222). The
                // directories `BackupPlan` requires were created by nothing, so a
                // backup of the real data directory refused on its first member,
                // for ever, on a machine where no receipt has been filed yet.
                //
                // It is one step with the backup rather than two, because the two
                // fail for one reason. Preparing, failing, and then attempting the
                // backup anyway would raise a SECOND problem under the same kind
                // and subject, and `ProblemsStore.raise` merges those into one
                // record whose sentence is whichever spoke last (L53).
                try prepareDataDirectory()
                _ = try takeBackup(now)
            } catch {
                let condition = Self.backupCondition(for: error)
                _ = problems.raise(kind: condition.kind, subject: storeURL.path,
                                   sentence: condition.sentence, now: now)
            }
        }

        // 4. OPEN.
        let container: ModelContainer
        do {
            container = try openContainer(storeURL)
        } catch {
            let sentence = "The store was identified as Ovation's and still would not open: "
                + "\(error.localizedDescription)"
            _ = problems.raise(kind: .unreadableStore, subject: storeURL.path,
                               sentence: sentence, now: now)
            return .refused(step: .identify, detail: sentence)
        }

        // 5. RECORD THE VERSION, immediately after the open that established it,
        // because the marker must be written by whatever ESTABLISHES the version
        // rather than by a surface that happens to notice (L319). It goes before
        // the seed so that a store which opened is marked even if seeding fails.
        //
        // A failure here is REPORTED and the launch continues. The store is open
        // and correct; what is lost is the ability to refuse a downgrade NEXT
        // time, which is worth saying and is not worth refusing to open over.
        do {
            try recordVersion(storeURL)
        } catch {
            _ = problems.raise(
                kind: .storeVersionNotRecorded, subject: storeURL.path,
                sentence: "Ovation could not record which version of itself opened this "
                    + "database: \(error.localizedDescription). It opened normally, but until "
                    + "this is written Ovation cannot warn you if an older build opens it later, "
                    + "which would remove anything a newer one added.",
                now: now)
        }

        // 6. SEED, and it is LAST for two reasons rather than one. There is no
        // container to write into until the store is open, and seeding WRITES,
        // so putting it before the backup would be a write the backup does not
        // carry.
        //
        // A failure here is REPORTED and the launch continues, the same choice
        // as the backup and for a weaker reason, so with a weaker consequence: an
        // empty service type picker is an annoyance Dan can fix by typing a name,
        // where refusing to open would leave him unable to invoice at all. It is
        // still said out loud, because a picker silently empty on a fresh install
        // reads as a product with no service types rather than as a step that
        // failed (L10).
        //
        // A launch that seeded NOTHING raises nothing. That is every launch after
        // the first, and a notice on the commonest case is one Dan learns to
        // click past (L36).
        do {
            _ = try seed(container)
        } catch {
            _ = problems.raise(
                kind: .startingDataNotSeeded, subject: storeURL.path,
                sentence: "Ovation could not write its starting service type list into a new "
                    + "store: \(error.localizedDescription). It opened anyway, and the service "
                    + "type picker on a new invoice will be empty until a type is added.",
                now: now)
        }

        // 7. BRING THE CLIENT ROSTER ACROSS (ovation#208).
        //
        // IT RUNS HERE, AFTER THE BACKUP, because it WRITES, and a write made
        // before the backup is a write the backup does not carry (L5). That is
        // the same reason the seed sits where it does.
        //
        // A FAILURE IS REPORTED AND THE LAUNCH CONTINUES, the same weighing as
        // the backup and the seed: a roster that could not be refreshed is an
        // annoyance Dan can work around, and refusing to open would leave him
        // unable to invoice at all. The runner has already turned every way this
        // can fail into a notice that says which one it was, so there is nothing
        // to catch here; what would be wrong is saying nothing.
        //
        // A RUN THAT CHANGED NOTHING RAISES NOTHING, which is every launch after
        // the first. That decision lives in the runner rather than here, so the
        // rule has one home (L83).
        for notice in importClients(container) {
            _ = problems.raise(kind: notice.kind, subject: notice.subject,
                               sentence: notice.sentence, now: now)
        }

        // 8. SAY WHAT IS TRUE ABOUT THE EXPORT (ovation#64). Both notices reach
        // Dan through this one presenter rather than as independent alerts
        // (L242), and both are DERIVED here rather than stored as a conclusion,
        // because a recorded fact about something outside the app is only true on
        // the day it was written (L175).
        //
        // It runs last, after the store is open, because one of the two questions
        // it answers is about what the store holds.
        for notice in exportNotices(container, now) {
            _ = problems.raise(kind: notice.kind, subject: notice.subject,
                               sentence: notice.sentence, now: now)
        }

        onOpened(container)
        return .opened
    }

    /// A KIND AND A SENTENCE, not a sentence alone (ovation#229).
    ///
    /// ovation#87 asked for two labels, not one, and distinct sentences under ONE
    /// kind is not two labels: `ProblemsStore.raise` keys a record on kind plus
    /// subject and overwrites its sentence, so two backup conditions true in one
    /// launch were one record whose text was whichever spoke last (L53, L260).
    ///
    /// The person reading these does different things about each: a write that
    /// could not happen is about reaching the folder, a verification that failed
    /// is about what landed in it, and a required member missing is about the data
    /// directory rather than the backup folder at all.
    static func backupCondition(for error: Error) -> (kind: ProblemKind, sentence: String) {
        let tail = "Ovation opened anyway, so nothing is lost, "
            + "but there is no backup from today."
        switch error {
        case BackupError.couldNotWrite(let detail):
            // The detail carries the CAUSE where the thrower had one, because a
            // volume that is gone, a disk that is full and a permission macOS
            // withdrew need three different actions and rendered one sentence
            // until now (L11).
            return (.backupCouldNotBeWritten,
                    "The backup could not be written to \(detail). " + tail)
        case BackupError.requiredMemberMissing(let path):
            return (.backupCouldNotBeWritten,
                    "The backup was refused because \(path) is missing from the data folder. "
                        + tail)
        case BackupError.verificationFailed:
            return (.backupFailed,
                    "The backup was written and did NOT verify, so it is not a backup. "
                        + "It has been kept as the evidence of what went wrong. " + tail)
        default:
            return (.backupFailed,
                    "The backup did not complete: \(error.localizedDescription). " + tail)
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
        case .fromANewerVersion: return .storeFromANewerVersion
        case .versionUnreadable: return .storeVersionUnreadable
        case .noStoreFile, .empty, .ovation: return .unidentifiableStore
        }
    }
}
