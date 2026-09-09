import Foundation
import SwiftData
import Testing
@testable import Ovation

/// ovation#158. The runner that joins the three parts of the export together and
/// is the only one of them that touches a disk.
///
/// TWO THINGS ARE ASSERTED HERE THAT NOTHING ELSE CAN BE. That a run which cannot
/// be reconciled writes NOTHING, because a short CSV looks exactly like an answer
/// and no file is a question somebody asks. And that a record is written on every
/// exit path, which is what lets the staleness notice tell a crash from a month
/// nobody ran anything (L514).
struct YearEndExportTests {

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: a good run

    @Test("a complete run writes both files and the manifest, and says which")
    func agoodRunWritesEverything() throws {
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-03-01", sent: true, number: 1)
        let expense = world.expense(dayKey: "2026-04-01", amount: Money(dollars: 20))

        let outcome = world.export().run(range: .calendarYear(2026), now: Self.now) {
            YearEndExport.StoreContents(invoices: [invoice], expenses: [expense],
                                        payments: [], refunds: [])
        }

        #expect(outcome == .wrote(files: ["income.csv", "expenses.csv", "manifest.json"]))
        for name in ["income.csv", "expenses.csv", "manifest.json"] {
            #expect(FileManager.default.fileExists(atPath: world.file(name).path),
                    Comment(rawValue: "\(name) is not on disk"))
        }
    }

    @Test("what is on the disk is what the export built, read back rather than assumed")
    func thefilesHoldTheRows() throws {
        // A write that returned without error is not a file that holds the rows,
        // and this is the last moment anything could notice (L12).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-03-01", sent: true, number: 77)

        _ = world.export().run(range: .calendarYear(2026), now: Self.now) {
            YearEndExport.StoreContents(invoices: [invoice], expenses: [],
                                        payments: [], refunds: [])
        }

        let text = try String(contentsOf: world.file("income.csv"), encoding: .utf8)
        #expect(text.contains("Invoice number"))
        #expect(text.contains("77"))
        let manifest = try JSONDecoder().decode(
            TaxExportManifest.self, from: Data(contentsOf: world.file("manifest.json")))
        #expect(manifest.incomeRows == 1)
        #expect(manifest.dateRule == TaxExport.dateRuleInForce)
    }

    @Test("the run record says it finished, and names the files it actually wrote")
    func therecordNamesTheFiles() throws {
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-03-01", sent: true, number: 1)

        _ = world.export().run(range: .calendarYear(2026), now: Self.now) {
            YearEndExport.StoreContents(invoices: [invoice], expenses: [],
                                        payments: [], refunds: [])
        }

        let (runs, _) = try world.log().load()
        #expect(runs.count == 2, "one when it started and one when it finished")
        #expect(runs.first?.outcome == .started)
        #expect(runs.last?.outcome == .finished)
        #expect(runs.last?.filesWritten == ["income.csv", "expenses.csv", "manifest.json"])
        #expect(runs.last?.manifest?.incomeRows == 1)
    }

    @Test("a finished run clears the staleness clock, which is what the record is for")
    func agoodRunClearsTheClock() throws {
        // The end to end statement: running an export makes the notice go away.
        // Without this, every part could be correct and the feature still do
        // nothing for the person it exists for (L3).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-03-01", sent: true, number: 1)

        _ = world.export().run(range: .calendarYear(2026), now: Self.now) {
            YearEndExport.StoreContents(invoices: [invoice], expenses: [],
                                        payments: [], refunds: [])
        }

        let (runs, _) = try world.log().load()
        #expect(ExportRunLog.notices(from: runs, now: Self.now,
                                     storeHasEverHeldSomethingToExport: true).isEmpty)
    }

    // MARK: a run that cannot be reconciled writes nothing

    @Test("a reconciliation finding REFUSES the run, and no file is written")
    func arefusedRunWritesNothing() throws {
        // The store holds an invoice the export was never given, so the file
        // would be short by one. It totals against its own parts perfectly, which
        // is exactly why a short file is worse than no file.
        let world = try World()
        let seen = world.invoice(dayKey: "2026-03-01", sent: true, number: 1)
        let unseen = world.invoice(dayKey: "2026-05-01", sent: true, number: 2)

        let outcome = world.export().run(range: .calendarYear(2026), now: Self.now) {
            // A reader that returns the whole store, while the DOCUMENTS below
            // are built from it: the finding comes from the invoice the export
            // itself cannot see, staged here as a short document.
            YearEndExport.StoreContents(invoices: [seen, unseen], expenses: [],
                                        payments: [], refunds: [],
                                        couldNotBeFullyRead: ["invoices": 1])
        }

        guard case .refused(let findings) = outcome else {
            Issue.record("a run that could not be reconciled returned \(outcome)")
            return
        }
        #expect(!findings.isEmpty)
        for name in ["income.csv", "expenses.csv", "manifest.json"] {
            #expect(!FileManager.default.fileExists(atPath: world.file(name).path),
                    Comment(rawValue: "\(name) was written by a refused run"))
        }
    }

    @Test("a refused run STILL writes its record, and does not clear the clock")
    func arefusedRunIsRecorded() throws {
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-03-01", sent: true, number: 1)

        _ = world.export().run(range: .calendarYear(2026), now: Self.now) {
            YearEndExport.StoreContents(invoices: [invoice], expenses: [],
                                        payments: [], refunds: [],
                                        couldNotBeFullyRead: ["invoices": 3])
        }

        let (runs, _) = try world.log().load()
        #expect(runs.count == 2)
        #expect(runs.last?.outcome == .failed)
        #expect(runs.last?.failure?.contains("refused") == true)
        #expect(runs.last?.filesWritten.isEmpty == true)
        // There is no export anybody can read, so the clock stands.
        #expect(!ExportRunLog.notices(from: runs, now: Self.now,
                                      storeHasEverHeldSomethingToExport: true).isEmpty)
    }

    @Test("the refused run's record still carries the manifest, so the findings are dateable")
    func arefusedRunKeepsItsManifest() throws {
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-03-01", sent: true, number: 1)

        _ = world.export().run(range: .calendarYear(2026), now: Self.now) {
            YearEndExport.StoreContents(invoices: [invoice], expenses: [],
                                        payments: [], refunds: [],
                                        couldNotBeFullyRead: ["invoices": 3])
        }

        let (runs, _) = try world.log().load()
        #expect(runs.last?.manifest?.findings == 1)
    }

    // MARK: a store that cannot be read

    @Test("a read that throws FAILS the run rather than exporting what it could reach")
    func afailedReadIsNotAPartialExport() throws {
        let world = try World()

        let outcome = world.export().run(range: .calendarYear(2026), now: Self.now) {
            throw ExportRunLogError.couldNotRead("the store is locked")
        }

        guard case .failed(let reason) = outcome else {
            Issue.record("a failed read returned \(outcome)")
            return
        }
        #expect(reason.contains("could not be read"))
        #expect(!FileManager.default.fileExists(atPath: world.file("income.csv").path))
    }

    @Test("a run that threw still leaves a closing record, which is what the defer is for")
    func afailedRunIsStillRecorded() throws {
        let world = try World()

        _ = world.export().run(range: .calendarYear(2026), now: Self.now) {
            throw ExportRunLogError.couldNotRead("the store is locked")
        }

        let (runs, _) = try world.log().load()
        #expect(runs.count == 2)
        #expect(runs.last?.outcome == .failed)
        #expect(runs.last?.finishedAt != nil)
    }

    @Test("a directory that cannot be written FAILS, and says so")
    func anunwritableDirectoryFails() throws {
        // The failure path the whole `defer` exists for, reached without damaging
        // anything: a path whose parent is a FILE cannot be made into a directory.
        let world = try World()
        let blocked = world.directory.appending(path: "a-file/exports")
        try Data("x".utf8).write(to: world.directory.appending(path: "a-file"))
        let export = YearEndExport(directory: blocked, log: world.log())

        let outcome = export.run(range: .calendarYear(2026), now: Self.now) {
            YearEndExport.StoreContents(invoices: [], expenses: [], payments: [], refunds: [])
        }

        guard case .failed(let reason) = outcome else {
            Issue.record("an unwritable directory returned \(outcome)")
            return
        }
        #expect(reason.contains("could not be written"))
        let (runs, _) = try world.log().load()
        #expect(runs.last?.outcome == .failed)
    }

    // MARK: an export with nothing in it is still an export

    @Test("an empty range writes both files, with their headers and no rows")
    func anemptyRangeStillWritesFiles() throws {
        // A zero row export is a legitimate answer and ovation#64 says so out
        // loud. What it must not do is produce nothing, because a missing file
        // and a failed write look the same on disk (L98).
        let world = try World()

        let outcome = world.export().run(range: .calendarYear(2026), now: Self.now) {
            YearEndExport.StoreContents(invoices: [], expenses: [], payments: [], refunds: [])
        }

        #expect(outcome == .wrote(files: ["income.csv", "expenses.csv", "manifest.json"]))
        let text = try String(contentsOf: world.file("income.csv"), encoding: .utf8)
        #expect(text.contains("Invoice number"))

        let (runs, _) = try world.log().load()
        #expect(ExportRunLog.notices(from: runs, now: Self.now,
                                     storeHasEverHeldSomethingToExport: true)
                == [.foundNothing(firstDayKey: "2026-01-01", lastDayKey: "2026-12-31")])
    }

    // MARK: privacy

    @Test("the outcome and the record carry no client name, though the file does")
    func nothingButTheFileCarriesAName() throws {
        // docs/PRIVACY-FLOOR.md. The CSV necessarily holds names; the outcome and
        // the run record are what reach a log, a terminal or a transcript (L222).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-03-01", sent: true, number: 1,
                                    clientNamed: "Ashgrove Chamber Players")

        let outcome = world.export().run(range: .calendarYear(2026), now: Self.now) {
            YearEndExport.StoreContents(invoices: [invoice], expenses: [],
                                        payments: [], refunds: [])
        }

        #expect(!"\(outcome)".contains("Ashgrove"))
        let recordText = try String(contentsOf: world.logURL, encoding: .utf8)
        #expect(!recordText.contains("Ashgrove"))
        let csv = try String(contentsOf: world.file("income.csv"), encoding: .utf8)
        #expect(csv.contains("Ashgrove"), "and the file itself DOES, which is the point")
    }

    // MARK: the isolation floor

    @Test("a disposable launch is refused the live export folder")
    func adisposableLaunchIsRefused() {
        #expect(YearEndExport.liveExportDirectory(appSupport: URL(fileURLWithPath: "/tmp"),
                                                  isDebugBuild: true,
                                                  isDisposableLaunch: true) == nil)
    }

    @Test("and a real launch is given one beside the store, not the backup folder")
    func areal_launchGetsAFolder() throws {
        let url = try #require(YearEndExport.liveExportDirectory(
            appSupport: URL(fileURLWithPath: "/tmp"), isDebugBuild: true,
            isDisposableLaunch: false))
        #expect(url.lastPathComponent == "exports")
        #expect(url.path.contains("Ovation-Debug"))
    }

    @Test("the floor names the export folder as BUILT now")
    func thefloorHasBeenExtended() {
        let entry = LiveDataFloor.entries.first { $0.name == "liveExportDirectory" }
        #expect(entry?.resolve != nil)
        #expect(entry?.issue == nil)
    }

    // MARK: fixtures

    private final class World {
        let directory: URL
        let context: ModelContext

        init() throws {
            directory = URL.temporaryDirectory
                .appending(path: "ovation-runner-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            context = ModelContext(try OvationSchema.container(inMemory: true))
        }

        var exportDirectory: URL { directory.appending(path: "exports", directoryHint: .isDirectory) }
        var logURL: URL { directory.appending(path: ExportRunLog.filename) }

        func file(_ name: String) -> URL { exportDirectory.appendingPathComponent(name) }
        func log() -> ExportRunLog { ExportRunLog(url: logURL) }
        func export() -> YearEndExport {
            YearEndExport(directory: exportDirectory, log: log())
        }

        @discardableResult
        func invoice(dayKey: String, sent: Bool, number: Int64,
                     clientNamed name: String = "A fictional ensemble") -> Invoice {
            let instant = BusinessCalendar.startOfDay(forDayKey: dayKey)!
            let client = Client(name: name, taxStatus: .notExempt)
            context.insert(client)
            let invoice = Invoice(client: client, kind: .photography,
                                  invoiceDate: .stamping(instant),
                                  hourlyRate: Money(dollars: 100), taxRate: .newYorkCity)
            context.insert(invoice)
            invoice.number = number
            invoice.add(LineItem.flat(Money(dollars: 100), describedAs: "Photography"))
            if sent {
                invoice.sentStatus = .sent(route: .ovationSentIt,
                                           at: Date(timeIntervalSince1970: 1_780_000_000))
            }
            return invoice
        }

        @discardableResult
        func expense(dayKey: String, amount: Money) -> Expense {
            let instant = BusinessCalendar.startOfDay(forDayKey: dayKey)!
            let expense = Expense(amount: amount, incurredOn: .stamping(instant),
                                  receipt: .noneRecorded)
            expense.category = .gear
            context.insert(expense)
            return expense
        }
    }
}
