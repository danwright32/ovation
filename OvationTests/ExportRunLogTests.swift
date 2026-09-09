import Foundation
import Testing

/// ovation#64. The durable record of every export run, and the two notices
/// derived from it.
///
/// THE FOUR FIXTURES THE ISSUE NAMES are the first four tests: no finished run in
/// 40 days raises staleness; a finished zero row run yesterday raises the zero
/// row notice and NOT staleness; an empty store raises neither; and a run that
/// threw still writes a record.
struct ExportRunLogTests {

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: the four fixtures

    @Test("no finished run in 40 days raises staleness")
    func fixtureOne_staleness() {
        let runs = [finished(daysAgo: 40, incomeRows: 3)]

        let notices = ExportRunLog.notices(from: runs, now: Self.now,
                                           storeHasEverHeldSomethingToExport: true)

        #expect(notices == [.stale(days: 40)])
        #expect(notices.first?.sentence.contains("40 days") == true)
    }

    @Test("a finished zero row run yesterday raises the zero row notice and NOT staleness")
    func fixtureTwo_zeroRowsIsNotStale() {
        // The reason the clock keys on FINISHED rather than on successful. Phase
        // 2 ships against an empty store, so every rehearsal until the import
        // produces zero rows; keyed on success the alarm would be raised on the
        // first day and stand for months with nothing Dan could do about it,
        // which teaches him to ignore the surface (L36).
        let runs = [finished(daysAgo: 1, incomeRows: 0, expenseRows: 0)]

        let notices = ExportRunLog.notices(from: runs, now: Self.now,
                                           storeHasEverHeldSomethingToExport: true)

        #expect(notices == [.foundNothing(firstDayKey: "2026-01-01", lastDayKey: "2026-12-31")])
        #expect(notices.first?.sentence.contains("found nothing") == true)
    }

    @Test("an empty store raises NEITHER, because there is nothing to be stale about")
    func fixtureThree_anEmptyStoreIsSilent() {
        // Suppressed entirely rather than raised and explained away. Before the
        // store has held anything, an export could not have produced a row, so a
        // notice about it is one nobody can act on.
        let notices = ExportRunLog.notices(from: [], now: Self.now,
                                           storeHasEverHeldSomethingToExport: false)

        #expect(notices.isEmpty)
    }

    @Test("a run that threw still leaves a record, and it does not clear the clock")
    func fixtureFour_aFailedRunIsRecorded() throws {
        // Without the record, a crash and a month in which nobody ran anything
        // are the same absence (L514). With it, the staleness question is still
        // answered honestly: a failed run is not an export anybody can read.
        let world = try World()
        let log = world.log()

        var wrote: ExportRun?
        do {
            wrote = try world.runAnExportThatThrows(into: log)
        } catch {
            // expected
        }
        #expect(wrote == nil, "the run threw before it could answer")

        let (runs, skipped) = try log.load()
        #expect(skipped == 0)
        #expect(runs.count == 2, "one record when it started and one when it failed")
        #expect(runs.last?.outcome == .failed)
        #expect(runs.last?.failure?.isEmpty == false)

        let notices = ExportRunLog.notices(from: runs, now: Self.now,
                                           storeHasEverHeldSomethingToExport: true)
        #expect(notices.contains { if case .stale = $0 { return true } else { return false } },
                "a failed run is not one anybody can read, so the clock is not cleared")
    }

    // MARK: what the clock keys on

    @Test("a run that finished 29 days ago is not stale, and one at 30 days is")
    func theboundaryIsMeasuredNotAssumed() {
        // The threshold is a monthly rehearsal, and the test names both sides of
        // it so a change to the number is a change to a test rather than a
        // silent widening (L172).
        #expect(ExportRunLog.stalenessDays == 30)
        #expect(ExportRunLog.notices(from: [finished(daysAgo: 29, incomeRows: 2)], now: Self.now,
                                     storeHasEverHeldSomethingToExport: true).isEmpty)
        #expect(ExportRunLog.notices(from: [finished(daysAgo: 30, incomeRows: 2)], now: Self.now,
                                     storeHasEverHeldSomethingToExport: true)
                == [.stale(days: 30)])
    }

    @Test("a record still saying STARTED is a run that was interrupted, and does not clear it")
    func aninterruptedRunDoesNotClearTheClock() {
        // A process killed mid run writes no closing record, so its opening one
        // stands. That is the only thing that can tell an interrupted run from a
        // month nobody ran anything.
        let runs = [started(daysAgo: 1)]

        let notices = ExportRunLog.notices(from: runs, now: Self.now,
                                           storeHasEverHeldSomethingToExport: true)

        #expect(notices.contains { if case .stale = $0 { return true } else { return false } })
    }

    @Test("the LAST finished run decides, not the newest record of any kind")
    func thelastFinishedRunDecides() {
        // A failed attempt today after a good run yesterday must not read as
        // stale, and a good run yesterday after a failure must not be hidden by
        // the failure being newer.
        let runs = [finished(daysAgo: 1, incomeRows: 4), failed(daysAgo: 0)]

        let notices = ExportRunLog.notices(from: runs, now: Self.now,
                                           storeHasEverHeldSomethingToExport: true)

        #expect(notices.isEmpty)
    }

    @Test("a store holding something with no export EVER run is stale")
    func neverHavingRunOneIsStale() {
        let notices = ExportRunLog.notices(from: [], now: Self.now,
                                           storeHasEverHeldSomethingToExport: true)

        #expect(notices.contains { if case .stale = $0 { return true } else { return false } })
    }

    @Test("a run with income rows and no expenses is NOT a zero row run")
    func onlyAnEmptyRunIsAZeroRowRun() {
        // The positive control for the zero row notice: a rule written as "no
        // expense rows" would fire on most of Dan's exports (L159).
        let runs = [finished(daysAgo: 1, incomeRows: 12, expenseRows: 0)]

        #expect(ExportRunLog.notices(from: runs, now: Self.now,
                                     storeHasEverHeldSomethingToExport: true).isEmpty)
    }

    @Test("the two notices are different kinds, so the presenter can tell them apart")
    func thenoticesAreDistinct() {
        #expect(ExportNotice.stale(days: 40).kind == .exportStale)
        #expect(ExportNotice.foundNothing(firstDayKey: "2026-01-01",
                                          lastDayKey: "2026-12-31").kind == .exportFoundNothing)
        #expect(ExportNotice.stale(days: 40).kind != ExportNotice
            .foundNothing(firstDayKey: "a", lastDayKey: "b").kind)
    }

    // MARK: it survives a relaunch

    @Test("what is written is what comes back, across a fresh reader")
    func therecordIsDurable() throws {
        let world = try World()
        try world.log().append(Self.finished(daysAgo: 2, incomeRows: 7))

        let (runs, skipped) = try world.log().load()

        #expect(skipped == 0)
        #expect(runs.count == 1)
        #expect(runs.first?.manifest?.incomeRows == 7)
        #expect(runs.first?.outcome == .finished)
    }

    @Test("a damaged line costs that line and is COUNTED, never the whole log")
    func adamagedLineIsCounted() throws {
        // A log quietly returning fewer records than it holds has the same shape
        // as one returning none, and here the newest line is the one the
        // staleness question depends on (L215).
        let world = try World()
        try world.log().append(Self.finished(daysAgo: 2, incomeRows: 7))
        try world.appendRawLine("{ not a run }")

        let (runs, skipped) = try world.log().load()

        #expect(runs.count == 1)
        #expect(skipped == 1)
    }

    @Test("a log that has never been written is EMPTY, not an error")
    func amissingLogIsEmpty() throws {
        let world = try World()
        let (runs, skipped) = try world.log().load()
        #expect(runs.isEmpty)
        #expect(skipped == 0)
    }

    // MARK: the isolation floor

    @Test("a disposable launch is refused the live path, so no test can write one")
    func adisposableLaunchIsRefused() {
        // Plan 1.9. Phase 2's fixtures all run the export, and a test written
        // record would make the staleness notice permanently unraisable: a
        // rolling record is a capped store where a cheap writer evicts the real
        // observations (L2, L191).
        #expect(ExportRunLog.liveExportRunRecord(appSupport: URL(fileURLWithPath: "/tmp"),
                                                 isDebugBuild: true,
                                                 isDisposableLaunch: true) == nil)
    }

    @Test("and a real launch is given a path beside the store, under the same folder")
    func areal_launchGetsAPath() throws {
        // The positive control: a resolver that returned nil always would satisfy
        // the refusal above and hide the feature entirely (L159).
        let url = try #require(ExportRunLog.liveExportRunRecord(
            appSupport: URL(fileURLWithPath: "/tmp"), isDebugBuild: true,
            isDisposableLaunch: false))
        #expect(url.lastPathComponent == ExportRunLog.filename)
        #expect(url.path.contains("Ovation-Debug"))
    }

    @Test("the floor names it as BUILT now, rather than as an issue that will build it")
    func thefloorHasBeenExtended() {
        // ovation#58's register is what notices a live resolver with no refusal.
        // Leaving this entry pending after building it would leave the guard
        // measuring a world one resolver smaller than the one that ships (L96).
        let entry = LiveDataFloor.entries.first { $0.name == "liveExportRunRecord" }
        #expect(entry?.resolve != nil)
        #expect(entry?.issue == nil)
    }

    @Test("a backup carries the run record, so a restore does not lose the history")
    func thebackupPlanCarriesIt() {
        // It is `presentSometimes` rather than required: a fresh installation has
        // never run an export and legitimately has no file, and requiring it
        // would refuse every backup until the first run (BackupPlan).
        let member = BackupPlan.members.first { $0.path == ExportRunLog.filename }
        let expectation = try? #require(member?.expectation)
        if case .presentSometimes = expectation { } else {
            Issue.record("export-runs.jsonl is \(String(describing: expectation))")
        }
    }

    // MARK: fixtures

    private static func manifest(incomeRows: Int, expenseRows: Int) -> TaxExportManifest {
        TaxExportManifest(
            firstDayKey: "2026-01-01", lastDayKey: "2026-12-31",
            dateRule: TaxExport.dateRuleInForce,
            incomeRows: incomeRows, incomeTotal: "0.00", salesTax: "0.00", notIncluded: [:],
            expenseRows: expenseRows, expenseTotal: "0.00", expensesNeedingACategory: 0,
            paymentsAgainstInvoicesOutsideTheRange: 0,
            refundsAgainstInvoicesOutsideTheRange: 0, findings: 0)
    }

    private static func finished(daysAgo: Int, incomeRows: Int,
                                 expenseRows: Int = 0) -> ExportRun {
        let at = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        return ExportRun(id: UUID(), startedAt: at, finishedAt: at, outcome: .finished,
                         manifest: manifest(incomeRows: incomeRows, expenseRows: expenseRows),
                         failure: nil, filesWritten: ["income.csv", "expenses.csv"])
    }

    private static func started(daysAgo: Int) -> ExportRun {
        let at = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        return ExportRun(id: UUID(), startedAt: at, finishedAt: nil, outcome: .started,
                         manifest: nil, failure: nil, filesWritten: [])
    }

    private static func failed(daysAgo: Int) -> ExportRun {
        let at = now.addingTimeInterval(-Double(daysAgo) * 86_400)
        return ExportRun(id: UUID(), startedAt: at, finishedAt: at, outcome: .failed,
                         manifest: nil, failure: "the folder could not be written",
                         filesWritten: [])
    }

    private func finished(daysAgo: Int, incomeRows: Int, expenseRows: Int = 0) -> ExportRun {
        Self.finished(daysAgo: daysAgo, incomeRows: incomeRows, expenseRows: expenseRows)
    }
    private func started(daysAgo: Int) -> ExportRun { Self.started(daysAgo: daysAgo) }
    private func failed(daysAgo: Int) -> ExportRun { Self.failed(daysAgo: daysAgo) }

    private struct World {
        let directory: URL

        init() throws {
            directory = URL.temporaryDirectory
                .appending(path: "ovation-export-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        func log() -> ExportRunLog {
            ExportRunLog(url: directory.appending(path: ExportRunLog.filename))
        }

        func appendRawLine(_ line: String) throws {
            let file = AppendOnlyLineFile(url: directory.appending(path: ExportRunLog.filename))
            try file.append(line)
        }

        /// A run that writes its opening record, throws, and is still recorded by
        /// the `defer` (L514, L515).
        func runAnExportThatThrows(into log: ExportRunLog) throws -> ExportRun? {
            let started = ExportRun(id: UUID(), startedAt: ExportRunLogTests.now,
                                    finishedAt: nil, outcome: .started, manifest: nil,
                                    failure: nil, filesWritten: [])
            try log.append(started)
            let closing = ExportRun(id: started.id, startedAt: started.startedAt,
                                    finishedAt: ExportRunLogTests.now, outcome: .failed,
                                    manifest: nil, failure: "the folder could not be written",
                                    filesWritten: [])
            defer { try? log.append(closing) }
            throw ExportRunLogError.couldNotWrite("the folder could not be written")
        }
    }
}
