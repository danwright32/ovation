// ovation#158. The one entry point that actually runs a year end export, and the
// only thing in this folder that touches a disk.
//
// WHY IT EXISTS. ovation#61 built the two documents, ovation#63 the
// reconciliation and the manifest, ovation#64 the run record. Each was tested and
// none of them wrote a file, so `ExportRun.filesWritten` was a field nothing
// filled and the export was three parts nobody had joined up. Built is not wired,
// and wired is not proven (L3).
//
// IT REFUSES RATHER THAN WRITING A SHORT FILE. If the reconciliation has any
// finding, nothing is written at all. A CSV that is short looks exactly like an
// answer: it opens, it totals against its own parts, and the number on the return
// is wrong by however many rows are missing (L517). No file is a question
// somebody asks; a short file is one nobody thinks to ask.
//
// EVERY EXIT PATH WRITES A RUN RECORD, in a `defer`, including the refusal above
// and any throw while writing (L514, L515). Without that, a crash and a month in
// which nobody ran anything are the same absence, and the staleness notice
// (ovation#64) cannot tell them apart.
//
// IT NEVER THROWS. Every way this can end is an outcome Dan has to be told about,
// and an `Error` at this boundary would arrive at the call site as one thing that
// has to be taken apart again to find out which of them it was.
//
// PRIVACY. The files necessarily hold real client names, because that is what an
// accountant needs. Nothing this ANSWERS may carry one: the outcome, the run
// record and the manifest hold counts, day keys and invoice numbers (L222,
// docs/PRIVACY-FLOOR.md).
import Foundation
import SwiftData

struct YearEndExport {

    /// What a run came to. Every case is durable in the run record as well.
    enum Outcome: Equatable, Sendable {
        /// Both files and the manifest are on disk, read back and verified.
        case wrote(files: [String])
        /// The reconciliation found something, so nothing was written.
        case refused(findings: [TaxExportFinding])
        /// Something failed. Never a client name.
        case failed(String)
        /// The files ARE on disk and the run could not be recorded.
        ///
        /// ITS OWN CASE, because the consequence outlives the run: the staleness
        /// notice reads the record, so an export that ran and was not recorded
        /// leaves that notice standing for ever with nothing saying why, and
        /// running the export again does not clear it (L11, L98). Reporting it as
        /// a plain success would make the one thing Dan could act on invisible.
        case wroteButTheRunWasNotRecorded(files: [String], reason: String)

        var filesWritten: [String] {
            switch self {
            case .wrote(let files), .wroteButTheRunWasNotRecorded(let files, _): return files
            case .refused, .failed: return []
            }
        }
    }

    static let incomeFilename = "income.csv"
    static let expensesFilename = "expenses.csv"
    static let manifestFilename = "manifest.json"

    /// Where a real launch writes the files, or nil when this launch may not
    /// touch anything real (plan 1.9, the isolation floor).
    ///
    /// NOT THE BACKUP FOLDER. That one is Dan's to choose and needs a panel and a
    /// security scoped bookmark (ovation#87). This is a folder beside the store,
    /// which needs neither, and keeping them apart means a test naming this one
    /// cannot reach the archives.
    static func liveExportDirectory(
        appSupport: URL = StoreLocation.appSupport,
        isDebugBuild: Bool = StoreLocation.isDebugBuild,
        isDisposableLaunch: Bool = AppEnvironment.isDisposableLaunch()
    ) -> URL? {
        guard !isDisposableLaunch else { return nil }
        return StoreLocation.dataDirectory(appSupport: appSupport, isDebugBuild: isDebugBuild)
            .appendingPathComponent("exports", isDirectory: true)
    }

    let directory: URL
    let log: ExportRunLog
    private let fileManager: FileManager

    init(directory: URL, log: ExportRunLog, fileManager: FileManager = .default) {
        self.directory = directory
        self.log = log
        self.fileManager = fileManager
    }

    /// Runs one export.
    ///
    /// - Parameter fetch: reads the WHOLE store. It is injected because the
    ///   reconciliation's independence depends on this being a different read
    ///   from anything the documents were built from (L70), and because a test
    ///   must be able to make it fail without damaging anything (L196).
    @discardableResult
    func run(range: TaxExportRange, now: Date,
             fetch: () throws -> StoreContents) -> Outcome {
        let started = ExportRun(id: UUID(), startedAt: now, finishedAt: nil,
                                outcome: .started, manifest: nil, failure: nil,
                                filesWritten: [])
        // A failure to write the OPENING record is not a reason to skip the
        // export. The closing one is what the staleness notice reads, and a
        // failure to write THAT is reported below rather than swallowed.
        try? log.append(started)

        var manifest: TaxExportManifest?
        let outcome = perform(range: range, now: now, fetch: fetch, manifest: &manifest)

        // THE CLOSING RECORD IS WRITTEN ON EVERY PATH, and there is exactly one
        // place it is written from, because `perform` returns rather than throws
        // (L514, L515). It is here rather than in a `defer` so that a failure to
        // write it can change what this answers: a `defer` runs after the return
        // value is settled and could only swallow it.
        do {
            try log.append(closing(after: started, outcome: outcome,
                                   manifest: manifest, now: now))
        } catch {
            if case .wrote(let files) = outcome {
                return .wroteButTheRunWasNotRecorded(
                    files: files,
                    reason: "the run record could not be written: "
                        + "\(error.localizedDescription)")
            }
        }
        return outcome
    }

    /// The export itself. Returns on every path and never throws, which is what
    /// makes the single closing write above cover all of them.
    private func perform(range: TaxExportRange, now: Date,
                         fetch: () throws -> StoreContents,
                         manifest: inout TaxExportManifest?) -> Outcome {
        let contents: StoreContents
        do {
            contents = try fetch()
        } catch {
            // A source that could not be read at all. Exporting what could be
            // reached would produce a file that is short for a reason nothing
            // records, and it would total against itself perfectly.
            return .failed("the store could not be read: \(error.localizedDescription)")
        }

        let income = TaxExport.income(from: contents.invoices, in: range)
        let expenses = TaxExport.expenses(from: contents.expenses, in: range)
        let reconciliation = TaxExportReconciliation.check(
            income: income, expenses: expenses,
            everyInvoice: contents.invoices, everyExpense: contents.expenses,
            everyPayment: contents.payments, everyRefund: contents.refunds,
            couldNotBeFullyRead: contents.couldNotBeFullyRead)
        manifest = reconciliation.manifest

        guard reconciliation.isComplete else {
            return .refused(findings: reconciliation.findings)
        }

        do {
            return .wrote(files: try write(income: income, expenses: expenses,
                                           manifest: reconciliation.manifest))
        } catch {
            return .failed("the files could not be written: \(error.localizedDescription)")
        }
    }

    private func closing(after started: ExportRun, outcome: Outcome,
                         manifest: TaxExportManifest?, now: Date) -> ExportRun {
        let finished: ExportRun.Outcome
        let failure: String?
        switch outcome {
        case .wrote, .wroteButTheRunWasNotRecorded:
            finished = .finished
            failure = nil
        case .refused(let findings):
            finished = .failed
            failure = "refused: \(findings.count) finding(s)"
        case .failed(let reason):
            finished = .failed
            failure = reason
        }
        return ExportRun(id: started.id, startedAt: started.startedAt, finishedAt: now,
                         outcome: finished, manifest: manifest, failure: failure,
                         filesWritten: outcome.filesWritten)
    }

    /// Everything the export and its reconciliation read, from ONE read of the
    /// store, so the documents and the check cannot be built from two reads that
    /// caught it in different states.
    ///
    /// NOT `Sendable`, deliberately: it holds model objects, which belong to the
    /// context that fetched them, and claiming otherwise would be a promise the
    /// compiler is right to refuse.
    struct StoreContents {
        let invoices: [Invoice]
        let expenses: [Expense]
        let payments: [Payment]
        let refunds: [Refund]
        /// How many rows each source could not consult, when the reader knows.
        /// A reader that could not read a source AT ALL throws instead.
        let couldNotBeFullyRead: [String: Int]

        init(invoices: [Invoice], expenses: [Expense], payments: [Payment],
             refunds: [Refund], couldNotBeFullyRead: [String: Int] = [:]) {
            self.invoices = invoices
            self.expenses = expenses
            self.payments = payments
            self.refunds = refunds
            self.couldNotBeFullyRead = couldNotBeFullyRead
        }

        /// One read of a real store.
        static func read(_ container: ModelContainer) throws -> StoreContents {
            let context = ModelContext(container)
            return StoreContents(
                invoices: try context.fetch(FetchDescriptor<Invoice>()),
                expenses: try context.fetch(FetchDescriptor<Expense>()),
                payments: try context.fetch(FetchDescriptor<Payment>()),
                refunds: try context.fetch(FetchDescriptor<Refund>()))
        }
    }

    /// Writes the three files and READS BACK what landed, so what is reported is
    /// what is on the disk rather than what was handed to the write (L12).
    private func write(income: IncomeExport, expenses: ExpenseExport,
                       manifest: TaxExportManifest) throws -> [String] {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let files: [(String, Data)] = [
            (Self.incomeFilename, income.document.data),
            (Self.expensesFilename, expenses.document.data),
            (Self.manifestFilename, try encoder.encode(manifest))
        ]

        var written: [String] = []
        for (name, data) in files {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            let readBack = try Data(contentsOf: url)
            guard DocumentStore.hash(of: readBack) == DocumentStore.hash(of: data) else {
                throw ExportRunLogError.couldNotWrite(
                    "\(name) does not hold what was written to it")
            }
            written.append(name)
        }
        return written
    }
}
