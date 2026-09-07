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

        // Its write ahead log and shared memory file. NOT required, because a
        // checkpointed store legitimately has neither, and requiring them would
        // refuse every healthy backup. Carried whenever they ARE there, because
        // the newest committed pages can live in the log and a store copied
        // without it reconstructs to an older state (ovation#88).
        .init(path: "Ovation.store-wal", kind: .file,
              expectation: .presentSometimes(reason: "absent once the store is checkpointed")),
        .init(path: "Ovation.store-shm", kind: .file,
              expectation: .presentSometimes(reason: "absent once the store is checkpointed")),

        // Declared now, built later. Each names the issue, so an archive can say
        // what it does not hold and why, rather than being quietly short.
        .init(path: "consumed-bookings.jsonl", kind: .file,
              expectation: .notYetBuilt(issue: "ovation#31")),
        .init(path: "consumed-messages.jsonl", kind: .file,
              expectation: .notYetBuilt(issue: "ovation#79")),
        .init(path: "referral-ledger.jsonl", kind: .file,
              expectation: .notYetBuilt(issue: "ovation#38")),
        .init(path: "export-runs.jsonl", kind: .file,
              expectation: .notYetBuilt(issue: "ovation#64")),
    ]

    /// Files that must NEVER reach an archive, by name.
    ///
    /// `gmail-tokens.json` is the refresh token store: a long lived credential
    /// carrying send and modify rights on Dan's mailbox. It is deliberately not a
    /// member above; this list is the second half, so that adding it by accident
    /// is caught rather than merely being unlikely (L19).
    static let excludedNames: Set<String> = ["gmail-tokens.json"]
}
