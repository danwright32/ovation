// ovation#64, PRD 5.32 and 5.35. A durable record of every export run, and the
// two notices derived from it.
//
// ZERO ROWS IS NOT SUCCESS. An export that produced no rows is indistinguishable
// from one where everything worked and there was nothing to report, unless it
// says so, and here that means Dan believing a year is empty (L98). So a zero row
// run raises its own notice, worded differently from a failure.
//
// STALENESS IS A FACT ABOUT THE RECORD, NOT ABOUT THE FILE, which is why the
// record is durable: the CSV may have been moved or renamed and the question is
// still answerable. It is DERIVED at every read rather than stored as a
// conclusion, because a recorded fact about something outside the app is only
// true on the day it was written (L175), which is the failure this project has
// already hit once with the sibling install records.
//
// IT KEYS ON THE LAST RUN THAT FINISHED, WHATEVER IT PRODUCED, never on the last
// SUCCESSFUL one, and that difference is the whole issue. Phase 2 ships against
// an empty store, so every rehearsal until the Phase 3 import produces zero rows,
// which this design defines as not-success. Keyed on success, the alarm would be
// raised on the first day and stand for months with nothing Dan could do to clear
// it, which teaches him to ignore the whole surface (L36).
//
// A RUN THAT FAILED STILL WRITES A RECORD, in a `defer`, on every exit path
// (L514, L515). Without it, a crash and a month in which nobody ran anything are
// the same absence.
//
// AND IT IS INSIDE THE TEST ISOLATION FLOOR (ovation#58). Phase 2 carries the
// heaviest test coverage in the plan and its fixtures all run the export, so
// without the refusal a test written record would make the staleness notice
// permanently unraisable: a rolling record is a capped store where a cheap writer
// evicts the real observations (L2, L191).
import Foundation
import SwiftData

/// One export run, as it will be read in March.
struct ExportRun: Codable, Equatable, Sendable {
    /// How the run ended.
    ///
    /// `started` is not a transitional nicety: it is what a record LEFT AT
    /// `started` by a process that died means, and it is the only way to tell a
    /// run that was interrupted from a month nobody ran anything.
    enum Outcome: String, Codable, Sendable {
        case started
        case finished
        case failed
    }

    let id: UUID
    let startedAt: Date
    let finishedAt: Date?
    let outcome: Outcome
    /// What the run produced. Absent on a `started` record and on a failure that
    /// happened before there was anything to describe.
    let manifest: TaxExportManifest?
    /// Why it failed, when it did. Never a client name (L222).
    let failure: String?
    /// The files it wrote, by name rather than by full path, so a record stays
    /// readable after the folder is moved.
    let filesWritten: [String]

    var producedNoRows: Bool {
        guard let manifest else { return false }
        return manifest.incomeRows == 0 && manifest.expenseRows == 0
    }
}

/// What Ovation should say about exports at this moment. Derived, never stored.
enum ExportNotice: Equatable, Sendable {
    /// Nobody has run one for long enough to be worth saying.
    case stale(days: Int)
    /// The last run finished and correctly found nothing, naming the range it
    /// looked at. Its own notice, differently worded, because "it found nothing"
    /// and "it did not run" are different facts (L11).
    case foundNothing(firstDayKey: String, lastDayKey: String)

    var kind: ProblemKind {
        switch self {
        case .stale: return .exportStale
        case .foundNothing: return .exportFoundNothing
        }
    }

    /// What the problem is ABOUT, which is half of the identity a problem is
    /// deduplicated on. Stable across launches on purpose: the same standing
    /// condition seen on ten launches is one problem seen ten times, not ten
    /// problems.
    var subject: String {
        switch self {
        case .stale: return "year-end-export"
        case .foundNothing(let first, let last): return "\(first)..\(last)"
        }
    }

    var sentence: String {
        switch self {
        case .stale(let days):
            return "Nobody has run a year end export in \(days) days. Ovation only looks "
                + "when it is open, so nothing is wrong with the data; what is missing is a "
                + "recent copy of the two files an accountant would work from."
        case .foundNothing(let first, let last):
            return "The last export ran and correctly found nothing between \(first) and "
                + "\(last). That is an answer rather than a failure, and it is said out loud "
                + "because an empty file and an export that never ran look the same on disk."
        }
    }
}

enum ExportRunLogError: Error, Equatable {
    case couldNotWrite(String)
    case couldNotRead(String)
}

/// The append only record of every run.
struct ExportRunLog {
    /// How long since the last finished run before it is worth saying.
    ///
    /// THIRTY DAYS BECAUSE THE REHEARSAL IS MONTHLY. The plan rehearses the
    /// export once a month until the real one in January, so one missed rehearsal
    /// is the smallest gap that means anything. A shorter window would fire on an
    /// ordinary month and teach Dan to click past it (L36).
    static let stalenessDays = 30

    /// The filename `BackupPlan` already declares, so an archive carries it.
    static let filename = "export-runs.jsonl"

    private let file: AppendOnlyLineFile

    init(url: URL, fileManager: FileManager = .default) {
        file = AppendOnlyLineFile(url: url, fileManager: fileManager)
    }

    /// Where a real launch keeps it, or nil when this launch may not touch
    /// anything real (plan 1.9, the isolation floor). The default argument reads
    /// THIS process, so a caller that passes nothing is refused rather than
    /// handed the real path.
    static func liveExportRunRecord(
        appSupport: URL = StoreLocation.appSupport,
        isDebugBuild: Bool = StoreLocation.isDebugBuild,
        isDisposableLaunch: Bool = AppEnvironment.isDisposableLaunch()
    ) -> URL? {
        guard !isDisposableLaunch else { return nil }
        return StoreLocation.dataDirectory(appSupport: appSupport, isDebugBuild: isDebugBuild)
            .appendingPathComponent(filename)
    }

    func append(_ run: ExportRun) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let line = String(data: try encoder.encode(run), encoding: .utf8) else {
            throw ExportRunLogError.couldNotWrite("the run did not encode as text")
        }
        do {
            try file.append(line)
        } catch let error as AppendOnlyLineFileError {
            switch error {
            case .couldNotWrite(let detail), .couldNotRead(let detail):
                throw ExportRunLogError.couldNotWrite(detail)
            }
        }
    }

    /// Every run, oldest first.
    ///
    /// A LINE THAT DOES NOT DECODE COSTS THAT LINE, never the file, and it is
    /// COUNTED, because a log quietly returning fewer records than it holds has
    /// the same shape as one returning none (L215). A damaged newest line would
    /// otherwise silently raise a staleness notice about a run that happened.
    func load() throws -> (runs: [ExportRun], skipped: Int) {
        let lines: [String]
        do {
            lines = try file.lines()
        } catch let error as AppendOnlyLineFileError {
            switch error {
            case .couldNotRead(let detail), .couldNotWrite(let detail):
                throw ExportRunLogError.couldNotRead(detail)
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var runs: [ExportRun] = []
        var skipped = 0
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let run = try? decoder.decode(ExportRun.self, from: data) else {
                skipped += 1
                continue
            }
            runs.append(run)
        }
        return (runs, skipped)
    }

    // MARK: what the store says about itself

    /// Whether the store has ever held something that belongs on a return: an
    /// issued invoice, or an expense.
    ///
    /// AN ISSUED INVOICE IS ONE WITH A NUMBER, because a number is allocated when
    /// an invoice is issued and a draft never has one (ovation#37). That is the
    /// same fact as "Sent was established", asked in the form a store predicate
    /// can actually express: `SentStatus` carries associated values and is stored
    /// as an opaque blob, so no predicate can read it.
    ///
    /// A FETCH THAT THROWS ANSWERS `true`, deliberately. The two answers are not
    /// symmetric: `false` SUPPRESSES the staleness question entirely, so a failed
    /// read that answered false would silence the notice for as long as the read
    /// kept failing, and nothing anywhere would say so (L42, L98).
    static func storeHasSomethingToExport(_ container: ModelContainer) -> Bool {
        let context = ModelContext(container)
        var issued = FetchDescriptor<Invoice>(predicate: #Predicate { $0.number != nil })
        issued.fetchLimit = 1
        if let count = try? context.fetch(issued).count, count > 0 { return true }

        var expenses = FetchDescriptor<Expense>()
        expenses.fetchLimit = 1
        guard let expenseCount = try? context.fetch(expenses).count else { return true }
        return expenseCount > 0
    }

    // MARK: what to say about it

    /// The notices this log justifies at `now`.
    ///
    /// - Parameter storeHasEverHeldSomethingToExport: whether the store has ever
    ///   held an issued invoice or an expense. THE STALENESS QUESTION IS
    ///   SUPPRESSED ENTIRELY until it has, and that is stated here rather than
    ///   left to be discovered: before then there is nothing an export could be
    ///   stale about, and a notice nobody can act on is one that teaches its
    ///   reader to skip the whole surface (L36).
    static func notices(from runs: [ExportRun], now: Date,
                        storeHasEverHeldSomethingToExport: Bool) -> [ExportNotice] {
        guard storeHasEverHeldSomethingToExport else { return [] }

        // The last run that FINISHED, whatever it produced. A failed run and a
        // record still saying `started` are both evidence somebody tried, and
        // neither is an export anybody can read, so neither clears the clock.
        let finished = runs
            .filter { $0.outcome == .finished }
            .sorted { ($0.finishedAt ?? $0.startedAt) < ($1.finishedAt ?? $1.startedAt) }

        guard let last = finished.last else {
            // Nobody has ever finished one, and the store holds something that
            // belongs on a return. That is the strongest form of the same fact,
            // and it is measured from the oldest evidence available rather than
            // asserted as a number: the store has held something since at least
            // the earliest run in the log, or since now if there are none.
            let since = runs.map(\.startedAt).min() ?? now
            return [.stale(days: max(days(from: since, to: now), stalenessDays))]
        }

        var notices: [ExportNotice] = []
        let elapsed = days(from: last.finishedAt ?? last.startedAt, to: now)
        if elapsed >= stalenessDays {
            notices.append(.stale(days: elapsed))
        }
        if last.producedNoRows, let manifest = last.manifest {
            notices.append(.foundNothing(firstDayKey: manifest.firstDayKey,
                                         lastDayKey: manifest.lastDayKey))
        }
        return notices
    }

    /// Whole days between two instants, never negative.
    ///
    /// Through the business calendar rather than a bare `timeIntervalSince`, so
    /// one date helper decides what a day is (L39).
    private static func days(from: Date, to: Date) -> Int {
        guard to > from else { return 0 }
        return BusinessCalendar.wholeDays(from: from, to: to)
    }
}
