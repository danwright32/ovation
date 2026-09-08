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

    /// The backup could not be verified (ovation#57).
    static let backupFailed = ProblemKind("backup.failed")

    /// The starting service types could not be written into a fresh store
    /// (ovation#107). Its own kind, because the remedy is not the store's: the
    /// app is open and usable, and what is missing is three rows in a picker.
    static let startingDataNotSeeded = ProblemKind("seed.starting-data")

    /// No export has been run for long enough to be worth saying (ovation#64).
    static let exportStale = ProblemKind("export.stale")

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
