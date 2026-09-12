// Plan 1.13, ovation#59. What a failure looks like once it has been reported.
//
// Ported in SPIRIT from Downbeat's "raises a problem naming that shoot, and
// deliberately never retracts" pattern rather than line by line: Downbeat's is a
// SwiftData model tied to its own domain, and Ovation needs the record before it
// has a domain model at all.
//
// NOTHING HERE EVER RETRACTS ON ITS OWN. A later success says nothing about the
// earlier failure. A problem leaves the open list in exactly one way: somebody
// resolves it and says why.
import Foundation

/// What kind of failure this is. Deliberately open rather than an enum: each
/// later issue raises its own kinds, and an enum here would make this file a
/// dependency of every one of them. The identity a problem is deduplicated on is
/// the kind AND its subject, so the vocabulary being open costs nothing.
struct ProblemKind: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
}

extension ProblemKind {
    // The store refusals (ovation#52). Four causes, four kinds, because they
    // need four different sentences and lead to different remedies (L11).
    static let foreignStore = ProblemKind("store.foreign")
    static let unreadableStore = ProblemKind("store.unreadable")
    static let storeIsNotADatabase = ProblemKind("store.not-a-database")
    static let unidentifiableStore = ProblemKind("store.unidentifiable")

    /// The store was written by a NEWER Ovation than the one running
    /// (ovation#116). Its own kind, because the remedy is the opposite of every
    /// other store refusal: this file is Dan's own invoices and must NOT be moved
    /// aside, it means the wrong build is running.
    static let storeFromANewerVersion = ProblemKind("store.from-a-newer-version")

    /// The version marker beside the store could not be read, so a downgrade
    /// cannot be ruled out. Different from there being no marker at all.
    static let storeVersionUnreadable = ProblemKind("store.version-unreadable")

    /// The version marker could not be WRITTEN after a successful open
    /// (ovation#116). The store is fine; what is lost is the ability to refuse a
    /// downgrade next time.
    static let storeVersionNotRecorded = ProblemKind("store.version-not-recorded")

    /// Another copy of Ovation is already running, so this one stood aside
    /// (ovation#84). Its own kind because the remedy is not about a file at all:
    /// there is nothing wrong with the store, and the action is to use the copy
    /// that is already open.
    static let secondRunningCopy = ProblemKind("app.second-running-copy")

    /// An archive was WRITTEN and did not verify (ovation#57, narrowed by
    /// ovation#229).
    ///
    /// IT NAMED EVERY BACKUP FAILURE UNTIL NOW, and that was the defect.
    /// `ProblemsStore.raise` keys a record on kind plus subject and OVERWRITES
    /// its sentence, so several conditions under one kind were one record whose
    /// text was whichever spoke last. On a launch where verification fails, "the
    /// archive did not verify" and "the backups are stale" are both true, and the
    /// second silently erased the first (L53, L260). Four sentences under one
    /// kind satisfies L11 and is not enough.
    static let backupFailed = ProblemKind("backup.failed")

    /// The archive could not be WRITTEN at all: the folder is not there, the disk
    /// is full, or macOS has withdrawn the permission. Its own kind because the
    /// remedy differs from an archive that was written and failed to verify. One
    /// is about reaching the folder, the other about what landed in it.
    static let backupCouldNotBeWritten = ProblemKind("backup.could-not-be-written")

    /// No backup folder has been chosen yet (ovation#225). A STANDING condition,
    /// restated on every launch until it is answered, and RESOLVED when a folder
    /// is chosen: `ProblemsStore` never retracts on its own, `raise` clears
    /// `acknowledgedAt`, and the presenter shows the oldest first, so a condition
    /// re-raised for ever sits at the head of the queue and pushes every more
    /// urgent notice behind it.
    static let backupFolderNotChosen = ProblemKind("backup.no-folder-chosen")

    /// A folder IS chosen and holds no archives at all (ovation#228).
    /// `StoreLaunchSequence` already promises in writing that this is raised from
    /// the backup FOLDER, where it stays true on every later launch, rather than
    /// from the one launch that skipped the first backup.
    ///
    /// It cannot be expressed as staleness: there is no newest archive to compare
    /// against, so the two would be one silence (L98).
    static let backupFolderIsEmpty = ProblemKind("backup.folder-is-empty")

    /// The backups are behind the data (ovation#230): the newest archive predates
    /// the last change to the store, on a day the trigger should have fired.
    static let backupsAreStale = ProblemKind("backup.stale")

    /// An archive that verified when it was written no longer does (ovation#233).
    /// Its own kind because nothing is wrong with today's backup: what has gone is
    /// an older one, and the action is about the folder rather than about Ovation.
    static let archiveNoLongerVerifies = ProblemKind("backup.archive-no-longer-verifies")

    /// Whether the backups are behind the data could not be judged (ovation#230),
    /// because the store's own dates could not be read.
    ///
    /// ITS OWN KIND rather than folded into `backupsAreStale`, which would be a
    /// message claiming something its check did not measure (L11), and rather
    /// than silence, which would make "could not tell" and "everything is fine"
    /// the same outcome (L98).
    static let backupCurrencyCouldNotBeJudged = ProblemKind("backup.currency-unknown")

    /// Retention decided to remove an archive and could not (ovation#227). Its own
    /// kind because a folder where deletions fail grows silently, and one failed
    /// eviction and a systemic one otherwise arrive on the same path and are
    /// indistinguishable for exactly as long as the second lasts (L77).
    static let archiveCouldNotBeRemoved = ProblemKind("backup.archive-could-not-be-removed")

    /// Retention did not run at all, because the folder could not be enumerated
    /// completely (ovation#227). A DIFFERENT fact from a deletion that failed:
    /// nothing was removed and nothing was judged, and acting on a short read is
    /// how incompleteness becomes permanent deletion (L211).
    static let retentionCouldNotRun = ProblemKind("backup.retention-could-not-run")

    /// The starting service types could not be written into a fresh store
    /// (ovation#107). Its own kind, because the remedy is not the store's: the
    /// app is open and usable, and what is missing is three rows in a picker.
    static let startingDataNotSeeded = ProblemKind("seed.starting-data")

    /// Downbeat's export is not at the path Ovation reads (ovation#208). Its own
    /// kind because the remedy is not about a file at all: Downbeat writes that
    /// file when it starts, so opening Downbeat once creates it.
    static let clientImportExportMissing = ProblemKind("client-import.export-missing")

    /// The export is there and could not be read (ovation#208). Deliberately not
    /// folded into the one above: that would send Dan to launch Downbeat when the
    /// real answer is a damaged file, which is a true sentence for the wrong
    /// reason (L11).
    static let clientImportUnreadable = ProblemKind("client-import.unreadable")

    /// Clients that were not here before are here now (ovation#208). Not a fault,
    /// and said out loud because a roster appearing is a change to what every
    /// screen shows.
    static let clientImportBroughtClientsAcross = ProblemKind("client-import.brought-across")

    /// Rows that matched more than one client, or matched only by name, so the
    /// import left them alone (ovation#208). The one import outcome that needs
    /// Dan, which is why it speaks although nothing changed.
    static let clientImportNeedsAnAnswer = ProblemKind("client-import.needs-an-answer")

    /// No export has been run for long enough to be worth saying (ovation#64).
    static let exportStale = ProblemKind("export.stale")

    /// The last export ran and correctly found nothing (ovation#64). Its own
    /// kind, and differently worded, because an export that found nothing and one
    /// that never ran look the same on disk and need different work: this one
    /// needs nothing done at all (L11, L98).
    static let exportFoundNothing = ProblemKind("export.found-nothing")

    /// The record of past exports is there and could not be read at all
    /// (ovation#64). Deliberately not folded into staleness: that would be a true
    /// sentence for the wrong reason, and it would send Dan to run an export
    /// rather than to look at a damaged file (L11).
    static let exportRunRecordUnreadable = ProblemKind("export.run-record-unreadable")

    /// Some lines of the export run record did not decode, so that history is
    /// short. Different from being unable to read it at all, because the notices
    /// still work and may simply name an older run (L215).
    static let exportRunRecordDamaged = ProblemKind("export.run-record-damaged")

    /// The problems journal could not be READ at all, so this session started
    /// with no history. A different fact from not being able to write one, and
    /// it needs a different sentence (L11).
    static let problemsJournalUnreadable = ProblemKind("problems.journal-unreadable")

    /// The problems journal was read, and some of what it held did not decode.
    static let problemsJournalDamaged = ProblemKind("problems.journal-damaged")

    /// The problems journal itself could not be written. Raised by the store
    /// about itself, because the one failure nobody hears about must not be the
    /// failure of the thing that exists to make failures heard.
    static let problemsJournalUnwritable = ProblemKind("problems.journal-unwritable")
}

struct Problem: Identifiable, Equatable, Codable, Sendable {
    /// Kind plus subject. Two launches finding the same foreign file report ONE
    /// problem that has happened twice, not two problems.
    let id: String
    let kind: ProblemKind
    /// What it is about: a path, an identifier, a year. Nil when the kind is the
    /// whole story.
    let subject: String?
    /// The one sentence for this cause, written by whatever raised it. The store
    /// never composes a sentence of its own, because only the raiser knows what
    /// it measured.
    var sentence: String

    let firstRaised: Date
    var lastRaised: Date
    var occurrences: Int

    /// Dan has seen it. It stops being presented at launch and stays in the list.
    var acknowledgedAt: Date?

    /// Somebody stated that the condition is gone, and said why. Never set by the
    /// absence of a new failure.
    var resolvedAt: Date?
    var resolutionReason: String?

    var isOpen: Bool { resolvedAt == nil }
    var needsPresenting: Bool { resolvedAt == nil && acknowledgedAt == nil }

    static func identity(kind: ProblemKind, subject: String?) -> String {
        guard let subject, !subject.isEmpty else { return kind.rawValue }
        return "\(kind.rawValue):\(subject)"
    }
}
