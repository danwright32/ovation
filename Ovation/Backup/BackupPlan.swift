// Plan 1.8, ovation#57. WHAT A BACKUP CONTAINS, enumerated in one place rather
// than left to whoever writes it (PRD 29b).
//
// THE LIST IS THE POINT. A backup that silently omits a member reads exactly
// like a complete one, and the omission is found in an audit months later (L98).
// So every member the plan names is declared HERE, including the ones nothing
// has built yet, and each carries the issue that will build it. A member that
// should exist and is missing REFUSES the backup; a member that does not exist
// yet is recorded in the manifest as not yet built, so an archive says what it
// does not contain rather than being silently short.
//
// IT EXCLUDES THE CREDENTIAL STORE, and that is the security decision in this
// issue. A backup lands in a folder Dan chooses, which on this Mac may sync to a
// Synology. It must never carry a long lived refresh token granting send and
// modify on his mailbox. The exclusion is enforced by NAME and by CONTENT HASH,
// because a token copied under another name is the same secret.
import Foundation

struct BackupMember: Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case file
        case directory
    }

    /// Why this member is or is not expected in an archive taken today.
    enum Expectation: Equatable, Sendable {
        /// It exists now, and an archive without it is refused.
        case required
        /// It is there sometimes and absent other times, and BOTH are correct,
        /// so its absence is never a failure and its presence is always carried.
        ///
        /// This exists because the write ahead log cannot be either of the other
        /// two. Requiring it would refuse every healthy backup, since a
        /// checkpointed store has no log beside it. Calling it not yet built
        /// would be false and would put it in the manifest's standing list of
        /// things nobody has written. The reason is recorded rather than the
        /// bare case, so a later reader does not have to reconstruct it (L233).
        case presentSometimes(reason: String)
        /// Nothing has built it yet. Recorded in the manifest with the issue that
        /// will, so an archive is honest about what it could not contain.
        case notYetBuilt(issue: String)
    }

    /// Its path inside the archive, and inside the data directory. One name, so
    /// restore does not need a second mapping that could disagree with this one.
    let path: String
    let kind: Kind
    let expectation: Expectation
}

enum BackupPlan {
    /// Everything a backup carries. Adding a member here is what puts it in the
    /// archive AND in the verification, so the two cannot drift (L41).
    static let members: [BackupMember] = [
        // Built.
        .init(path: "problems.jsonl", kind: .file, expectation: .required),
        .init(path: "documents", kind: .directory, expectation: .required),
        .init(path: "custody", kind: .directory, expectation: .required),

        // THE DATABASE. Promoted from notYetBuilt to required on 2026-09-07,
        // long after ovation#60 shipped it, and the delay is the lesson. The
        // staging step copies whatever is on disk, so archives DID hold it; the
        // verification only checks required members, so a failed copy or a
        // backup taken before the store existed recorded it as not yet built and
        // verified clean. An expectation left at its build time value is a guard
        // measuring the wrong quantity, and it fails in the reassuring direction
        // (L63, L98). It holds the only copy of every invoice.
        .init(path: "Ovation.store", kind: .file, expectation: .required),

        // The version marker (ovation#116). REQUIRED, alongside the store it
        // describes, because an archive carrying the database without it restores
        // a store nobody can date, and the guard that refuses a downgrade then
        // has nothing to read. Measured: an older build handed a newer store
        // migrates it BACKWARDS and the newer field is gone.
        .init(path: "Ovation.store.version", kind: .file, expectation: .required),

        // The export run record (ovation#64). NOT required, and the reason is the
        // same shape as the write ahead log's: a fresh installation has never run
        // an export and legitimately has no file, so requiring it would refuse
        // every backup until the first run. Carried whenever it IS there, because
        // it is the only thing that can say whether an export is stale, and a
        // restore without it silences that notice for ever (L575).
        .init(path: ExportRunLog.filename, kind: .file,
              expectation: .presentSometimes(
                reason: "absent until the first export has been run")),

        // Its write ahead log and shared memory file. NOT required, because a
        // checkpointed store legitimately has neither, and requiring them would
        // refuse every healthy backup. Carried whenever they ARE there, because
        // the newest committed pages can live in the log and a store copied
        // without it reconstructs to an older state (ovation#88).
        .init(path: "Ovation.store-wal", kind: .file,
              expectation: .presentSometimes(reason: "absent once the store is checkpointed")),
        .init(path: "Ovation.store-shm", kind: .file,
              expectation: .presentSometimes(reason: "absent once the store is checkpointed")),

        // THE REFERRAL LEDGER IS NOT IN THIS LIST, and its absence is the entry.
        // It was declared here as `referral-ledger.jsonl`, not yet built, naming
        // ovation#38. That issue shipped on 2026-09-08 and the ledger is
        // `ReferralLedgerEntry` INSIDE the store, so the file it named will never
        // exist. Left standing, a member whose issue is closed reads as work
        // outstanding forever, and every archive would report itself short of a
        // file nothing writes (L346, L377).
        //
        // Declared now, built later. Each names the issue, so an archive can say
        // what it does not hold and why, rather than being quietly short.
        .init(path: "consumed-bookings.jsonl", kind: .file,
              expectation: .notYetBuilt(issue: "ovation#31")),
        .init(path: "consumed-messages.jsonl", kind: .file,
              expectation: .notYetBuilt(issue: "ovation#79")),
    ]

    /// Files that must NEVER reach an archive, by name.
    ///
    /// `gmail-tokens.json` is the refresh token store: a long lived credential
    /// carrying send and modify rights on Dan's mailbox. It is deliberately not a
    /// member above; this list is the second half, so that adding it by accident
    /// is caught rather than merely being unlikely (L19).
    static let excludedNames: Set<String> = ["gmail-tokens.json"]
}
