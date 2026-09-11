// ovation#162, PRD 23a. The one thing that RUNS a year end export, and the
// reason the staleness notice names a remedy somebody can reach.
//
// WHY IT EXISTS. `YearEndExport.run` shipped with ovation#158 and nothing called
// it: no menu item, no launch step, no schedule and no command. ovation#64 raises
// a notice through the launch presenter saying nobody has run an export in N
// days, so that notice named a remedy that could not be reached, and the only way
// to clear it was to make an export happen, which nothing could do. A refusal
// whose remedy has no control behind it leaves the person facing the same message
// with nothing to do, and pressing on is the only diagnosis available (L109,
// L111, L148). It also teaches its reader to ignore the surface every other
// launch problem uses (L36).
//
// THE CONTROL'S WORDS LIVE HERE, ONCE. The notice quotes them, so a rename that
// moved one and not the other would send Dan to a menu item that is not there
// (L70, L399).
//
// WORKING, STILL ALIVE AND FAILED ARE THREE VISIBLE STATES, and that is a
// standing rule rather than a detail of this feature. `progress` separates them,
// and `elapsed` is a MEASUREMENT taken from a clock the caller passes rather than
// a spinner, so a view can say how long a run has been going instead of only that
// it is going. A spinner that looks the same whether the work is progressing,
// hung or dead is a defect.
//
// IT REFUSES A SECOND PRESS WHILE ONE IS RUNNING. Two exports over one directory
// are two writers of the same three files, and the second would read back and
// verify against the first's partial write. That has to be impossible from the
// control rather than unlikely (L33).
//
// AND IT REFUSES A DISPOSABLE LAUNCH, with a reason. A throwaway run resolves no
// live export directory, and a control that silently did nothing would be
// indistinguishable from one that worked (plan 1.9, L2, L98).
//
// PRIVACY. Every sentence here carries counts, file names, a directory path and
// whatever `YearEndExport` already refused to put a client name into. The files
// themselves necessarily hold real names; nothing this SAYS does (L222,
// docs/PRIVACY-FLOOR.md).
import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class YearEndExportCommand {

    /// The words on the control. The staleness notice quotes this rather than
    /// spelling the name a second time.
    ///
    /// NOT ISOLATED, because the notice that quotes it is built during the launch
    /// sequence and has no business hopping to the main actor to read a constant.
    nonisolated static let title = "Run the year end export"

    /// Where a run has got to. Three cases, because three things have to be told
    /// apart at a glance: it started, it is still alive, and it ended.
    enum Progress: Equatable {
        case notStarted
        case running(since: Date)
        case finished(outcome: YearEndExport.Outcome, at: Date)
    }

    private(set) var progress: Progress = .notStarted

    /// Nil on a launch that may not touch anything real. Kept as the ABSENCE
    /// rather than as a flag beside a path, so there is no way to run with one
    /// and not the other (L544).
    ///
    /// THE RECORD IS HELD AS ITS URL rather than as an `ExportRunLog`, because
    /// the log holds a `FileManager` and is therefore not a value that can cross
    /// into the work below. One URL and one place that turns it into a log is
    /// also one fewer pair that could disagree (L544).
    let directory: URL?
    let runRecord: URL?

    init(directory: URL?, runRecord: URL?) {
        self.directory = directory
        self.runRecord = runRecord
    }

    /// The command for THIS launch, or one that can only explain why it cannot
    /// run because there is nowhere real to write.
    ///
    /// NOT CALLED `live`, and the name matters. In this codebase a static
    /// `live...` member answers "where does this live for a real launch" and
    /// returns a URL, and `check-isolation-floor.sh` requires every one of them
    /// to be registered in `LiveDataFloor`. This is not one: it RESOLVES nothing
    /// new, it composes the two resolvers that are already registered
    /// (`YearEndExport.liveExportDirectory` and `ExportRunLog.liveExportRunRecord`)
    /// and carries their refusal forward as a command that says why it cannot
    /// run. Registering it would put a third name in the floor for two paths
    /// already in it; naming it `live` while returning something else would make
    /// the convention the floor rests on untrue.
    static func forThisLaunch() -> YearEndExportCommand {
        guard let directory = YearEndExport.liveExportDirectory(),
              let record = ExportRunLog.liveExportRunRecord() else {
            return YearEndExportCommand(directory: nil, runRecord: nil)
        }
        return YearEndExportCommand(directory: directory, runRecord: record)
    }

    var mayRun: Bool {
        guard directory != nil, runRecord != nil else { return false }
        if case .running = progress { return false }
        return true
    }

    /// Why a press would do nothing, or nil when it would run.
    ///
    /// A DISABLED CONTROL WITH NO REASON IS A DEAD CONTROL (L109). Each cause is
    /// worded differently because the work each needs is different: one waits for
    /// a run to finish, the other cannot happen on this launch at all (L11).
    var whyItCannotRun: String? {
        if case .running(let since) = progress {
            return "An export started at \(BusinessCalendar.dayKey(for: since)) is still "
                + "running. Two at once would write the same three files over each other."
        }
        guard directory != nil, runRecord != nil else {
            return "This launch has nowhere to write an export. It is a throwaway run, "
                + "kept away from the real records on purpose, so there is no export "
                + "folder and no record of past runs to add to."
        }
        return nil
    }

    /// How long the run in progress has been going, or nil when none is.
    func elapsed(now: Date) -> TimeInterval? {
        guard case .running(let since) = progress else { return nil }
        return now.timeIntervalSince(since)
    }

    func began(at instant: Date) { progress = .running(since: instant) }

    func finished(outcome: YearEndExport.Outcome, at instant: Date) {
        progress = .finished(outcome: outcome, at: instant)
    }

    /// NOTHING BELOW THIS LINE TOUCHES THE COMMAND'S STATE, so none of it is
    /// isolated: the year a press covers, the sentence an outcome produces and
    /// the kind it is raised under are pure, and the staleness notice reads the
    /// title while the launch sequence is still building it, off the main actor.
    ///
    /// Which calendar year a press exports.
    ///
    /// FROM `BusinessCalendar`, which is this product's one timezone and one date
    /// helper (L39). A press in the first hours of January must not export
    /// whichever year the machine's own locale happens to be in.
    nonisolated static func range(for instant: Date) -> TaxExportRange {
        .calendarYear(BusinessCalendar.year(for: instant))
    }

    /// One press, and the ONE place a run is marked started, marked finished and
    /// reported. There is no second entry point: a synchronous one beside this
    /// would be a second copy of the same sequence, and the two would drift
    /// (L370).
    ///
    /// THE WORK HAPPENS OFF THIS ACTOR. It reads the whole store and writes three
    /// files, and doing that on the thread that would have to draw the result is
    /// how the whole window stops responding rather than the one surface that
    /// asked (L236, L241).
    ///
    /// NOTHING NON SENDABLE CROSSES BACK. The store's rows are SwiftData models
    /// and belong to the context that fetched them, so the read AND the export
    /// both happen inside the task and only the outcome, which is a value,
    /// returns.
    func press(now: Date, container: ModelContainer, problems: ProblemsStore,
               afterwards: @escaping @MainActor () -> Void = {}) {
        guard mayRun, let directory, let runRecord else {
            if let why = whyItCannotRun {
                _ = problems.raise(kind: .exportCouldNotBeRun, subject: "year-end-export",
                                   sentence: why, now: now)
                afterwards()
            }
            return
        }
        began(at: now)
        let range = Self.range(for: now)
        let year = BusinessCalendar.year(for: now)
        // THE TASK STAYS ON THIS ACTOR AND THE WORK DOES NOT. Only values cross
        // into the detached work below, so nothing main-actor-isolated (this
        // command, the problems store, the callback) is ever touched off it.
        Task { @MainActor in
            let outcome = await Self.offTheMainActor(directory: directory,
                                                     runRecord: runRecord,
                                                     range: range, now: now,
                                                     container: container)
            self.finished(outcome: outcome, at: Date())
            self.report(outcome: outcome, year: year, directory: directory,
                        problems: problems, now: Date())
            afterwards()
        }
    }

    /// Raises the outcome so it reaches Dan through the same presenter as every
    /// other condition, rather than as an alert of its own (L242).
    private func report(outcome: YearEndExport.Outcome, year: Int, directory: URL,
                        problems: ProblemsStore, now: Date) {
        _ = problems.raise(kind: Self.kind(for: outcome),
                           subject: "year-end-export-\(year)",
                           sentence: Self.sentence(for: outcome, year: year,
                                                   directory: directory),
                           now: now)
    }

    /// The work itself, with nothing isolated to an actor.
    ///
    /// A STORE THAT CANNOT BE READ IS A FAILED RUN, never an empty one. An export
    /// built from a read that threw would write files that are short, and a short
    /// CSV looks exactly like an answer (L215, L517).
    /// The same work, awaited from the main actor without running on it.
    ///
    /// IT TAKES THE RECORD'S URL RATHER THAN THE LOG, so that only values cross
    /// into the detached work: `ExportRunLog` holds a `FileManager`, which is not
    /// one, and passing it would be the compiler correctly refusing a race.
    nonisolated static func offTheMainActor(directory: URL, runRecord: URL,
                                            range: TaxExportRange, now: Date,
                                            container: ModelContainer)
        async -> YearEndExport.Outcome {
        // A DISPATCH QUEUE, NOT `Task.detached`. This work BLOCKS: it reads the
        // whole store and writes, reads back and verifies three files. The
        // cooperative pool is about one thread per core and does not grow, so a
        // blocked thread there is never given back and enough of them starve
        // every other await in the app (L241). `Task.detached` reads like "run
        // this somewhere else" and somewhere else is that same fixed pool; the
        // global queue grows. check-forbidden-constructs.sh holds the whole tree
        // to this, and caught this line being written the wrong way round.
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: perform(
                    directory: directory, log: ExportRunLog(url: runRecord),
                    range: range, now: now, container: container))
            }
        }
    }

    nonisolated static func perform(directory: URL, log: ExportRunLog,
                                    range: TaxExportRange, now: Date,
                                    container: ModelContainer) -> YearEndExport.Outcome {
        do {
            let contents = try YearEndExport.StoreContents.read(container)
            return YearEndExport(directory: directory, log: log)
                .run(range: range, now: now) { contents }
        } catch {
            return .failed("the store could not be read: \(error.localizedDescription)")
        }
    }

    /// One sentence per outcome, because each needs different work (L11).
    nonisolated static func sentence(for outcome: YearEndExport.Outcome, year: Int,
                                     directory: URL) -> String {
        switch outcome {
        case .wrote(let files):
            return "The \(year) export is written: \(files.joined(separator: ", ")) in "
                + "\(directory.path). Every row was read back off the disk and reconciled "
                + "against a second reading of the store before this was said."
        case .refused(let findings):
            return "Nothing was written for \(year). The reconciliation found "
                + "\(findings.count) thing(s) it could not account for, and a short CSV "
                + "looks exactly like an answer, so no file is better than a wrong one. "
                + "\(summarise(findings))"
        case .failed(let why):
            return "The \(year) export did not finish: \(why). Nothing was written, and "
                + "the attempt is in the record of past runs, so this is a failure rather "
                + "than a year nobody ran."
        case .wroteButTheRunWasNotRecorded(let files, let reason):
            return "The \(year) export is written (\(files.joined(separator: ", ")) in "
                + "\(directory.path)) and Ovation could not record that it ran: \(reason). "
                + "The staleness notice reads that record, so it will go on saying nobody "
                + "has run an export, and running it again will not clear it."
        }
    }

    /// What the findings were, without naming anybody. `TaxExportFinding` carries
    /// invoice numbers and day keys and no names, which is why this can print
    /// them at all (docs/PRIVACY-FLOOR.md).
    nonisolated private static func summarise(_ findings: [TaxExportFinding]) -> String {
        guard !findings.isEmpty else {
            return "The findings are in the record of past runs."
        }
        return "They are: " + findings.map { "\($0)" }.joined(separator: "; ") + "."
    }

    /// A kind per outcome, so no one of them answers for another on a screen that
    /// groups by kind (L11, L53).
    nonisolated static func kind(for outcome: YearEndExport.Outcome) -> ProblemKind {
        switch outcome {
        case .wrote: return .exportWritten
        case .refused: return .exportRefused
        case .failed: return .exportFailed
        case .wroteButTheRunWasNotRecorded: return .exportWrittenButNotRecorded
        }
    }
}

extension ProblemKind {
    /// An export Dan asked for, which ran and wrote its files (ovation#162).
    ///
    /// A SUCCESS IS RAISED HERE AND NOT ONLY LOGGED, because the launch presenter
    /// is the one surface this product tells Dan anything on, and an action that
    /// says nothing is indistinguishable from one that did not happen (L608).
    static let exportWritten = ProblemKind("export.written")

    /// The reconciliation found something, so nothing was written.
    static let exportRefused = ProblemKind("export.refused")

    /// The run failed part way. Its own kind because the remedy differs from a
    /// refusal: a refusal is about the data, this is about the run.
    static let exportFailed = ProblemKind("export.failed")

    /// The files are on disk and the run could not be recorded, so the staleness
    /// notice will stand and re-running will not clear it.
    static let exportWrittenButNotRecorded = ProblemKind("export.written-not-recorded")

    /// A press that could not run at all: a throwaway launch, or one already
    /// running. Its own kind because nothing was attempted.
    static let exportCouldNotBeRun = ProblemKind("export.could-not-be-run")
}
