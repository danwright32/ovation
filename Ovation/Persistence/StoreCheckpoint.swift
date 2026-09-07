// Plan 1.2, ovation#88. The second step of the launch sequence: identify,
// CHECKPOINT, back up, then open.
//
// WHY IT EXISTS, measured rather than assumed. `SwiftDataBehaviourTests` opens a
// store, saves one row, and copies the store file alone. On this OS the write
// ahead log holds 57,712 bytes and the copied store file carries NO rows: a
// saved row lives entirely in the log until something moves it.
//
// That makes three things true, and the backup depends on all of them.
//
//   An archive holding `Ovation.store` without its log restores an EMPTY
//   database. The archive verifies clean, because every file it recorded is
//   present and matches its hash, which says nothing about whether the pair is
//   consistent. That is a verification measuring the wrong quantity (L63).
//
//   `BackupPlan` cannot simply require the log instead, because a checkpointed
//   store legitimately has none, and a guard that refuses every healthy backup
//   is worse than no guard.
//
//   Copying both is not a fix either. They are copied at two different instants,
//   so the pair can be internally inconsistent in a way neither file reveals.
//
// So the store is made SELF SUFFICIENT before anything reads it, and then the
// log's presence stops mattering.
//
// IT USES RAW SQLITE, NOT SWIFTDATA, deliberately. The whole point is to act on
// the file BEFORE `ModelContainer` opens it, because opening it is the last step
// of the sequence and an open container is what a refusal is trying to prevent.
// `StoreSchemaGuard` reads the same file the same way one step earlier.
import Foundation
import SQLite3

enum StoreCheckpoint {

    /// What happened, in distinct cases, because they need different responses.
    ///
    /// A first launch with no store is ORDINARY and must not read as a failure,
    /// or every fresh install raises a problem (L11). A file that is not a
    /// database is a real fault and is named, because the checkpoint runs before
    /// the backup and a silent success here would let the backup proceed against
    /// something nobody has identified (L98).
    enum Outcome: Equatable {
        case checkpointed
        case noStoreFile
        case failed(detail: String)
    }

    /// Moves everything in the write ahead log into the store file and empties
    /// the log.
    ///
    /// TRUNCATE rather than PASSIVE or FULL, because it also empties the log
    /// file rather than leaving its bytes in place, so a copy taken afterwards
    /// cannot carry a stale log that contradicts the store.
    ///
    /// The mode is NOT what makes this safe. Every mode, TRUNCATE included,
    /// gives up when a reader is active and reports that in its result row
    /// rather than in its return code. Reading the row is what makes it safe,
    /// and the first version of this file did not.
    nonisolated static func run(storeURL: URL) -> Outcome {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return .noStoreFile
        }

        var handle: OpaquePointer?
        let opened = sqlite3_open_v2(storeURL.path, &handle, SQLITE_OPEN_READWRITE, nil)
        defer { if handle != nil { sqlite3_close(handle) } }
        guard opened == SQLITE_OK, let handle else {
            return .failed(detail: message(from: handle, fallback: "could not open the store"))
        }

        // Refuse a file that is not a database before asking it to checkpoint.
        // sqlite3_open_v2 does not read the header, so it succeeds on any file
        // and the first real statement is what fails (L108): a check that
        // accepts something on its shape alone and stays silent afterwards
        // reads as confirmation.
        if sqlite3_exec(handle, "PRAGMA schema_version;", nil, nil, nil) != SQLITE_OK {
            return .failed(detail: message(from: handle, fallback: "not a database"))
        }

        // THE VERDICT IS THE RESULT ROW, NOT THE RETURN CODE, and reading only
        // the return code is a defect that shipped here once. `PRAGMA
        // wal_checkpoint` answers SQLITE_OK even when it moved NOTHING: it hands
        // back one row of three integers, and the first is a BUSY flag saying it
        // gave up because a reader was active. Judging it by the call's success
        // is judging a command by the wrong signal (L184), and it fails in the
        // reassuring direction: a clean report over a store that is still not
        // self sufficient, which the backup then copies and verifies.
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA wal_checkpoint(TRUNCATE);", -1,
                                 &statement, nil) == SQLITE_OK else {
            return .failed(detail: message(from: handle, fallback: "the checkpoint was refused"))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            // No row at all is not success. It means the pragma did not answer,
            // and an unanswered question must never read as a clean run (L98).
            return .failed(detail: message(from: handle,
                                           fallback: "the checkpoint reported nothing"))
        }

        let busy = sqlite3_column_int(statement, 0)
        let pagesLeftInLog = sqlite3_column_int(statement, 1)

        guard busy == 0 else {
            return .failed(detail: "the checkpoint could not be completed, "
                           + "a reader is holding the store open")
        }
        guard pagesLeftInLog == 0 else {
            // TRUNCATE is supposed to leave nothing behind. Anything left means
            // the store is not self sufficient, whatever the flags said.
            return .failed(detail: "the checkpoint could not be completed, "
                           + "\(pagesLeftInLog) page(s) remain in the log")
        }

        return .checkpointed
    }

    private nonisolated static func message(from handle: OpaquePointer?,
                                            fallback: String) -> String {
        guard let handle, let raw = sqlite3_errmsg(handle) else { return fallback }
        let text = String(cString: raw)
        return text.isEmpty ? fallback : text
    }
}
