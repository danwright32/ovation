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

    /// The launch stopped waiting for a backup that was still running
    /// (ovation#507). Its own kind, because nothing refused: the remedy for a
    /// folder that is slow is not the remedy for one that cannot be written, and a
    /// sentence about a write failure would send Dan to fix a folder that works.
    static let backupStillRunning = ProblemKind("backup.still-running")

    /// No backup folder has been chosen yet (ovation#225). A STANDING condition,
    /// restated on every launch until it is answered, and RESOLVED when a folder
    /// is chosen: `ProblemsStore` never retracts on its own, `raise` clears
    /// `acknowledgedAt`, and the presenter shows the oldest first, so a condition
    /// re-raised for ever sits at the head of the queue and pushes every more
    /// urgent notice behind it.
    static let backupFolderNotChosen = ProblemKind("backup.no-folder-chosen")

    /// A build that never backs up has upgraded its store without a backup
    /// (ovation#505). Said only on that launch: on an ordinary open, never backing
    /// up is what the build is for, and there is nothing to say.
    static let backupNotTakenByThisBuild = ProblemKind("backup.not-taken-by-this-build")

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

    /// Kinds that report something that HAPPENED, so reading them is the end of
    /// them (ovation#564). A kind belongs here only when nothing is left for Dan
    /// to do once he has read it; one that still needs him, like
    /// `clientImportNeedsAnAnswer`, stays open until it is resolved.
    ///
    /// THE EXPORT THAT WAS WRITTEN, THE DRAFTS THAT WERE MADE AND THE EXPORT THAT
    /// CORRECTLY FOUND NOTHING JOINED IT with the rail's foot (ovation#99,
    /// ovation#566). Dan settled on 2026-09-26 that the foot lists what is OPEN,
    /// read or not, on the understanding that a notice closes once read. Each of
    /// these reports something done with nothing left for him to do, so left open
    /// they would stand in the foot for ever after he had read them.
    static let closingOnceRead: Set<ProblemKind> = [
        .clientImportBroughtClientsAcross, .exportWritten, .bookingsDrafted, .exportFoundNothing,
    ]

    var closesOnceRead: Bool { Self.closingOnceRead.contains(self) }

    /// ovation#99 and ovation#566. What the rail's foot calls a problem of this kind:
    /// a few plain words on one line, with Read beside it and the whole sentence
    /// behind Read (Dan, 2026-09-26).
    ///
    /// KEYED BY KIND, NOT WRITTEN BY THE RAISER, because a problem read back from
    /// the journal carries only its kind, subject and sentence, and a name the
    /// raiser supplied would be missing on every problem raised before it existed.
    /// `RailFootTests` derives every kind the app declares and fails on one with
    /// no name here (L113), and measures every name against the foot's width.
    ///
    /// NO COUNTS AND NO DATES IN A NAME. A name is read for as long as the problem
    /// stays open, so "3 days behind" would go on saying 3 on the fifth day. The
    /// sentence behind Read carries the dates.
    static let shortNames: [ProblemKind: String] = [
        .foreignStore: "Wrong database",
        .unreadableStore: "Can't read database",
        .storeIsNotADatabase: "Not a database",
        .unidentifiableStore: "Database unknown",
        .storeFromANewerVersion: "From newer Ovation",
        .storeVersionUnreadable: "Version unreadable",
        .storeVersionNotRecorded: "Version not saved",
        .secondRunningCopy: "Another copy open",
        .backupFailed: "Backup failed",
        .backupCouldNotBeWritten: "Backup not written",
        .backupStillRunning: "Backup still running",
        .backupFolderNotChosen: "No backup folder",
        .backupNotTakenByThisBuild: "No upgrade backup",
        .backupFolderIsEmpty: "No backups yet",
        .backupsAreStale: "Backups are behind",
        .archiveNoLongerVerifies: "Old backup broken",
        .backupCurrencyCouldNotBeJudged: "Backups unchecked",
        .archiveCouldNotBeRemoved: "Backup not deleted",
        .retentionCouldNotRun: "Backups not tidied",
        .startingDataNotSeeded: "No service types",
        .clientImportExportMissing: "No Downbeat file",
        .clientImportUnreadable: "Bad Downbeat file",
        .clientImportBroughtClientsAcross: "New clients added",
        .clientImportNeedsAnAnswer: "Clients to check",
        .exportStale: "No export lately",
        .exportFoundNothing: "Nothing to export",
        .exportRunRecordUnreadable: "Export log broken",
        .exportRunRecordDamaged: "Export log damaged",
        .problemsJournalUnreadable: "Problem log broken",
        .problemsJournalDamaged: "Some problems lost",
        .problemsJournalUnwritable: "Problems unsaved",
        .invoicesUnreadable: "Invoices unreadable",
        .rosterUnreadable: "Clients unreadable",
        .bookingsDrafted: "Bookings drafted",
        .bookingDraftRefused: "No drafts made",
        .bookingRecordUnreadable: "Booking unreadable",
        .exportWritten: "Export written",
        .exportRefused: "Export held back",
        .exportFailed: "Export failed",
        .exportWrittenButNotRecorded: "Export not recorded",
        .exportCouldNotBeRun: "Export did not run",
    ]

    /// The year end export's outcomes, named for the year they are about, which is
    /// how this year's export is told from last year's in the foot. The year is read
    /// from the subject `YearEndExportCommand` raises them with.
    static let yearlyShortNames: [ProblemKind: @Sendable (Int) -> String] = [
        .exportWritten: { "\($0) export written" },
        .exportRefused: { "\($0) not exported" },
        .exportFailed: { "\($0) export failed" },
        .exportWrittenButNotRecorded: { "\($0) not recorded" },
    ]

    /// This kind's name in the foot, or nil where it has none, which a test refuses.
    func shortName(subject: String?) -> String? {
        if let yearly = Self.yearlyShortNames[self], let year = Self.exportYear(in: subject) {
            return yearly(year)
        }
        return Self.shortNames[self]
    }

    /// The year in a year end export's subject, `year-end-export-2026`, or nil.
    private static func exportYear(in subject: String?) -> Int? {
        let prefix = "year-end-export-"
        guard let subject, subject.hasPrefix(prefix) else { return nil }
        let digits = subject.dropFirst(prefix.count)
        guard digits.count == 4, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }

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

    /// Open until resolved, or, for a kind that reports what HAPPENED rather than
    /// a standing condition, until Dan has read it (ovation#564). Decided here,
    /// where it is read, rather than by writing a resolution on acknowledgement,
    /// so a report read before this rule existed closes too and nothing has to
    /// be rewritten in the journal (L559). Raising it again clears the
    /// acknowledgement, so a new report reopens it.
    var isOpen: Bool {
        guard resolvedAt == nil else { return false }
        return !(kind.closesOnceRead && acknowledgedAt != nil)
    }
    var needsPresenting: Bool { resolvedAt == nil && acknowledgedAt == nil }

    /// What the rail's foot calls it (ovation#99). A kind with no name says so
    /// plainly rather than borrowing another's, and `RailFootTests` keeps that
    /// from ever being drawn by failing on the missing name (L113).
    var shortName: String {
        kind.shortName(subject: subject) ?? "Something to read"
    }

    static func identity(kind: ProblemKind, subject: String?) -> String {
        guard let subject, !subject.isEmpty else { return kind.rawValue }
        return "\(kind.rawValue):\(subject)"
    }
}
