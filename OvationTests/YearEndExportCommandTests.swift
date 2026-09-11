import Foundation
import Testing

/// ovation#162. `YearEndExport.run` existed from ovation#158 and NOTHING called
/// it: no menu item, no launch step, no schedule and no command. So the staleness
/// notice ovation#64 raises named a remedy that could not be reached, and the
/// only way to clear it was to make an export happen, which nothing could do.
///
/// A refusal whose remedy has no control behind it leaves the person facing the
/// same message with nothing to do, and pressing on is the only diagnosis
/// available (L109, L111, L148). It also teaches its reader to ignore the surface
/// every other launch problem uses (L36).
///
/// WHAT IS ASSERTED HERE is the part that is not SwiftUI: which year a press
/// exports, what Dan is told about each outcome, which kind it is raised under,
/// and that a run in progress is distinguishable from one that has finished and
/// from one that failed. That last one is a standing rule rather than a detail of
/// this feature: a spinner that looks the same whether work is progressing, hung
/// or dead is a defect.
struct YearEndExportCommandTests {

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: what it is called, and where that name is allowed to live

    @Test("the control's words come from one place, so the notice cannot rename it")
    func onevocabulary() {
        // The notice that sends Dan to this control quotes the control. Two
        // copies of that name is two things drifting apart (L70, L399).
        #expect(ExportNotice.stale(days: 40).sentence.contains(YearEndExportCommand.title))
    }

    // MARK: which year a press exports

    @Test("a press exports the calendar year the clock is in")
    func exportsthisYear() {
        // The year comes from BusinessCalendar, which is the one timezone and
        // the one date helper this product has (L39). A press in January must
        // not export the year the machine's locale happens to think it is in.
        #expect(YearEndExportCommand.range(for: Self.now)
                == .calendarYear(BusinessCalendar.year(for: Self.now)))
    }

    // MARK: what Dan is told, one sentence per outcome

    @Test("a run that wrote the files says where they are and what they are called")
    func saidwhatItWrote() {
        let said = YearEndExportCommand.sentence(
            for: .wrote(files: ["income.csv", "expenses.csv", "manifest.json"]),
            year: 2026, directory: URL(fileURLWithPath: "/tmp/exports"))
        #expect(said.contains("2026"))
        #expect(said.contains("income.csv"))
        #expect(said.contains("/tmp/exports"))
    }

    @Test("a refused run says nothing was written, and how many findings stopped it")
    func saidwhyItRefused() {
        let said = YearEndExportCommand.sentence(
            for: .refused(findings: [.expenseRowsDisagree(expected: 3, found: 2)]),
            year: 2026, directory: URL(fileURLWithPath: "/tmp/exports"))
        #expect(said.lowercased().contains("nothing was written"))
        #expect(said.contains("1 "))
    }

    @Test("a failure says so, and is not confused with a refusal")
    func afailureIsItsOwnSentence() {
        let failed = YearEndExportCommand.sentence(for: .failed("the disk is full"),
                                                   year: 2026,
                                                   directory: URL(fileURLWithPath: "/tmp/e"))
        let refused = YearEndExportCommand.sentence(
            for: .refused(findings: []), year: 2026,
            directory: URL(fileURLWithPath: "/tmp/e"))
        #expect(failed.contains("the disk is full"))
        #expect(failed != refused)
    }

    @Test("an export that ran and was not recorded says the notice will not clear")
    func thewroteButUnrecordedCase() {
        // Its own sentence because the consequence outlives the run: the
        // staleness notice reads the record, so running it again does not clear
        // it and telling Dan it worked would hide the one thing he can act on.
        let said = YearEndExportCommand.sentence(
            for: .wroteButTheRunWasNotRecorded(files: ["income.csv"], reason: "read only"),
            year: 2026, directory: URL(fileURLWithPath: "/tmp/e"))
        #expect(said.contains("read only"))
        #expect(said != YearEndExportCommand.sentence(for: .wrote(files: ["income.csv"]),
                                                      year: 2026,
                                                      directory: URL(fileURLWithPath: "/tmp/e")))
    }

    // MARK: which kind each outcome is raised under

    @Test("each outcome is raised under its own kind, so none answers for another")
    func distinctkinds() {
        let kinds = [
            YearEndExportCommand.kind(for: .wrote(files: [])),
            YearEndExportCommand.kind(for: .refused(findings: [])),
            YearEndExportCommand.kind(for: .failed("x")),
            YearEndExportCommand.kind(for: .wroteButTheRunWasNotRecorded(files: [],
                                                                        reason: "y"))
        ]
        #expect(Set(kinds).count == kinds.count)
    }

    // MARK: working, still alive, and failed are three visible states

    @MainActor
    @Test("a run that has not started, one in progress and one finished are three states")
    func threestates() throws {
        let command = try Harness().command()
        #expect(command.progress == .notStarted)

        command.began(at: Self.now)
        #expect(command.progress == .running(since: Self.now))

        // STILL ALIVE IS A MEASUREMENT, not a spinner. The elapsed time is read
        // from a clock the caller passes, so the view can say how long it has
        // been going rather than only that it is going.
        #expect(command.elapsed(now: Self.now.addingTimeInterval(9)) == 9)

        command.finished(outcome: .wrote(files: ["income.csv"]), at: Self.now)
        if case .finished(let outcome, _) = command.progress {
            #expect(outcome == .wrote(files: ["income.csv"]))
        } else {
            Issue.record("a finished run is not reported as finished")
        }
        #expect(command.elapsed(now: Self.now.addingTimeInterval(9)) == nil)
    }

    @MainActor
    @Test("a press while one is already running is refused rather than run twice")
    func nottwiceAtOnce() throws {
        // Two exports over one directory are two writers of the same three files,
        // and the second would be read back and verified against the first's
        // partial write. It must be impossible from the control rather than
        // unlikely (L33).
        let command = try Harness().command()
        command.began(at: Self.now)
        #expect(command.mayRun == false)
        command.finished(outcome: .failed("x"), at: Self.now)
        #expect(command.mayRun == true)
    }

    // MARK: a press on a launch that may not touch anything real

    @MainActor
    @Test("a disposable launch has nowhere to write and says so rather than writing")
    func adisposableLaunchIsRefused() {
        // The isolation floor: a throwaway run must not write into Dan's real
        // export folder, and a control that silently did nothing would be
        // indistinguishable from one that worked (plan 1.9, L2, L98).
        let command = YearEndExportCommand(directory: nil, runRecord: nil)
        #expect(command.mayRun == false)
        #expect(command.whyItCannotRun(container: nil) != nil)
    }

    // MARK: a press that cannot run always says so

    @MainActor
    @Test("a press that cannot run raises a problem rather than doing nothing")
    func arefusalIsNeverSilent() {
        // THE CONTROL MUST NEVER JUST NOT WORK. This branch used to be written as
        // "if there is a reason, say it", which is a control that does nothing
        // and cannot be asked why the moment that reason is ever nil (L109).
        let command = YearEndExportCommand(directory: nil, runRecord: nil)
        let problems = ProblemsStore(journal: InMemoryProblemsJournal())
        var cameBack = false

        command.press(now: Self.now, container: nil, problems: problems) { cameBack = true }

        #expect(problems.open.count == 1)
        #expect(problems.open.first?.kind == .exportCouldNotBeRun)
        // AND THE CALLER IS TOLD, or a screen waiting on this refresh never does.
        #expect(cameBack)
    }

    // MARK: the sentence a run in flight shows

    @MainActor
    @Test("a run in flight counts seconds, so a number that stops moving is a run that stopped")
    func stillAliveIsAMeasurement() throws {
        // A spinner that looks the same whether the work is progressing, hung or
        // dead is a defect. This is the part of that rule which can be asserted
        // without a window: the sentence carries elapsed time, and it changes.
        let command = try Harness().command()
        command.began(at: Self.now)
        let view = RunningExportView(command: command)
        let early = view.sentence(at: Self.now.addingTimeInterval(2))
        let later = view.sentence(at: Self.now.addingTimeInterval(41))
        #expect(early.contains("2s"))
        #expect(later.contains("41s"))
        #expect(early != later)
    }

    private struct Harness {
        let directory: URL

        init() throws {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ovation-export-command-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
        }

        @MainActor
        func command() -> YearEndExportCommand {
            YearEndExportCommand(directory: directory,
                                 runRecord: directory.appendingPathComponent("runs.jsonl"))
        }
    }
}
