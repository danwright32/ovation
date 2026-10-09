import Foundation
import SwiftData
import Testing

/// ovation#70. Reverting an import batch is guarded at the moment it runs, not only
/// by a backup taken before the import.
///
/// EVERY CASE RUNS IN AN IN MEMORY STORE, and the backup is a closure the case
/// hands in, so nothing here can reach Dan's store or his backup folder (L2).
struct QuickBooksImportRevertTests {

    private typealias Fixture = QuickBooksImportFixture
    private typealias Spec = QuickBooksImportFixture.Spec

    /// A backup that records it was asked, and what the store held when it was.
    private final class Backups: @unchecked Sendable {
        private let lock = NSLock()
        private var _taken: [Int] = []
        let container: ModelContainer
        let fails: Bool
        init(_ container: ModelContainer, fails: Bool = false) {
            self.container = container
            self.fails = fails
        }
        var taken: [Int] { lock.withLock { _taken } }
        struct Refused: Error {}
        /// Answers a made up archive, after counting the invoices the store holds
        /// right now, which is how a case proves the backup came BEFORE the delete.
        func take() throws -> URL {
            let held = try ModelContext(container).fetch(FetchDescriptor<Invoice>()).count
            lock.withLock { _taken.append(held) }
            if fails { throw Refused() }
            return URL(fileURLWithPath: "/nonexistent/backup-\(UUID().uuidString)")
        }
    }

    /// The writer a hook started, handed back to the case that awaits it.
    private final class Started: @unchecked Sendable {
        private let lock = NSLock()
        private var _task: Task<Void, Error>?
        var task: Task<Void, Error>? { lock.withLock { _task } }
        func set(_ task: Task<Void, Error>) { lock.withLock { _task = task } }
    }

    private static func allocator(_ container: ModelContainer) -> InvoiceNumberAllocator {
        InvoiceNumberAllocator(modelContainer: container)
    }

    private static func day(_ key: String) throws -> BusinessDate {
        try #require(BusinessCalendar.day(forKey: key))
    }

    // MARK: seen to fail, the two ways the issue names

    @Test("a payment recorded against an imported invoice refuses the revert, and names that invoice")
    func aPaymentRecordedSinceRefuses() async throws {
        let container = try Fixture.store()
        let batch = UUID()
        try await Fixture.write(Fixture.run([Spec(number: "1041", paidCents: 0), Spec(number: "1042")]),
                                into: container, batch: batch)
        let target = try #require(try Fixture.invoices(in: container).first { $0.number == 1_041 })
        try await PaymentAllocator(modelContainer: container).record(
            Money(dollars: 40), method: .zelle, receivedOn: try Self.day("2026-03-03"),
            onto: target.persistentModelID, press: UUID())
        let backups = Backups(container)

        let outcome = try await Self.allocator(container).revertImport(batch, takeVerifiedBackup: backups.take)

        #expect(outcome == .refused([.init(row: .invoice(number: 1_041), reasons: [.paymentRecordedAgainstIt])]))
        #expect(try Fixture.invoices(in: container).count == 2, "a refused revert deleted something")
        #expect(backups.taken.isEmpty, "a revert that was always going to refuse took a backup first")
    }

    @Test("a clean batch reverted and imported again by a corrected importer comes back once")
    func aRevertedBatchComesBackOnce() async throws {
        let container = try Fixture.store()
        let run = Fixture.run([Spec(number: "1041", paidCents: 4_000), Spec(number: "1042")])
        let first = UUID()
        try await Fixture.write(run, into: container, batch: first, version: 1)
        let backups = Backups(container)

        let outcome = try await Self.allocator(container).revertImport(first, takeVerifiedBackup: backups.take)
        guard case .reverted(let invoices, let payments, _) = outcome else {
            Issue.record("expected the clean batch to revert, got \(outcome)")
            return
        }
        #expect((invoices, payments) == (2, 2))
        #expect(try Fixture.invoices(in: container).isEmpty)
        #expect(try Fixture.payments(in: container).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PaymentAllocation>()).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<LineItem>()).isEmpty)

        let again = try await Fixture.write(run, into: container, version: 2)

        #expect(again.written == [6, 7])
        #expect(try Fixture.invoices(in: container).compactMap(\.number) == [1_041, 1_042],
                "not zero times and not twice")
        #expect(try Fixture.payments(in: container).count == 2)
    }

    // MARK: every other reason, by name (L38)

    @Test("an imported invoice edited since the import refuses the revert")
    func anEditRefuses() async throws {
        let container = try Fixture.store()
        let batch = UUID()
        try await Fixture.write(Fixture.run([Spec(number: "1041")]), into: container, batch: batch)
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>()).first)
        invoice.dueDate = try Self.day("2026-04-30")
        try context.save()

        let outcome = try await Self.allocator(container).revertImport(batch, takeVerifiedBackup: Backups(container).take)

        #expect(outcome == .refused([.init(row: .invoice(number: 1_041), reasons: [.editedSinceImport])]))
    }

    @Test("a line changed since the import is an edit too")
    func aLineEditRefuses() async throws {
        let container = try Fixture.store()
        let batch = UUID()
        try await Fixture.write(Fixture.run([Spec(number: "1041")]), into: container, batch: batch)
        let context = ModelContext(container)
        let line = try #require(try context.fetch(FetchDescriptor<LineItem>()).first)
        line.summary = "Imaginary gala, corrected"
        try context.save()

        let outcome = try await Self.allocator(container).revertImport(batch, takeVerifiedBackup: Backups(container).take)

        #expect(outcome == .refused([.init(row: .invoice(number: 1_041), reasons: [.editedSinceImport])]))
    }

    @Test("a message sent and referral credit spent are named, each as its own reason")
    func messagesAndCreditAreNamed() async throws {
        let container = try Fixture.store()
        let batch = UUID()
        try await Fixture.write(Fixture.run([Spec(number: "1041")]), into: container, batch: batch)
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>()).first)
        let message = SentMessage(kind: .reminder, recipients: ["office@fictive.example"],
                                  sentAt: Date(timeIntervalSince1970: 1_794_531_600), subject: nil,
                                  gmailThreadID: nil, messageID: nil)
        context.insert(message)
        message.invoice = invoice
        context.insert(ReferralLedgerEntry(client: invoice.client, hours: Hours(hundredths: -100),
                                           occurredOn: try Self.day("2026-03-03"), earnedFromBookingKey: nil,
                                           spentOnInvoiceID: invoice.id, note: nil))
        try context.save()

        let outcome = try await Self.allocator(container).revertImport(batch, takeVerifiedBackup: Backups(container).take)

        #expect(outcome == .refused([.init(row: .invoice(number: 1_041),
                                           reasons: [.messageSentAboutIt, .referralCreditSpentOnIt])]))
    }

    // MARK: nothing lands between the last check and the delete (review of 3d585a0)

    @Test("an edit made since the import is seen even by the allocator that wrote the batch")
    func astaleContextDoesNotHideAnEdit() async throws {
        // THE SAME ALLOCATOR WROTE THE BATCH, so its own context still holds those
        // rows when another context edits one. On this OS a re-fetch there picks the
        // edit up (`OvationSchemaProbe`), and this case passes whichever context the
        // revert reads through; it stands so that a change to how rows are read, or
        // an OS where the re-fetch stops refreshing, cannot let an edit compare as
        // untouched and be deleted without a red case saying so (L443, L82).
        let container = try Fixture.store()
        let allocator = Self.allocator(container)
        let batch = UUID()
        _ = try await allocator.importInvoices(Fixture.run([Spec(number: "1041")]).candidates(), batch: batch)
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>()).first)
        invoice.dueDate = try Self.day("2026-04-30")
        try context.save()

        let outcome = try await allocator.revertImport(batch, takeVerifiedBackup: Backups(container).take)

        #expect(outcome == .refused([.init(row: .invoice(number: 1_041), reasons: [.editedSinceImport])]))
        #expect(try Fixture.invoices(in: container).count == 1)
    }

    @Test("a writer arriving after the last check waits until the delete is saved, and finds nothing to change")
    func awriterInTheWindowWaits() async throws {
        // THE WINDOW, OPENED ON PURPOSE (L157): the revert has made its last check and
        // has not deleted yet. A cancellation arriving now must not land in between,
        // or the delete would take a decision nobody has a copy of.
        let container = try Fixture.store()
        let allocator = Self.allocator(container)
        let batch = UUID()
        _ = try await allocator.importInvoices(Fixture.run([Spec(number: "1041", paidCents: 0)]).candidates(),
                                               batch: batch)
        let id = try #require(try Fixture.invoices(in: container).first).persistentModelID
        let gate = MoneyWriteGates.gate(for: container)
        let day = try Self.day("2026-03-03")
        let started = Started()
        await allocator.setBeforeDeletingImport {
            // STARTED INSIDE THE WINDOW, and held until it is demonstrably queued on
            // the gate, so what is asserted below is a writer that waited and not one
            // that had simply not started yet (L159).
            started.set(Task {
                try await InvoiceCloser(modelContainer: container).cancel(
                    id, reason: "the show was cancelled", money: nil, on: day,
                    now: Date(timeIntervalSince1970: 1_772_553_600))
            })
            // BOUNDED BY A COUNT, never a clock (L290): a revert that does not hold
            // the gate lets the writer straight through, and this then gives up
            // rather than spinning, so the case fails instead of hanging.
            var yields = 0
            while gate.waiting == 0 && yields < 100_000 { await Task.yield(); yields += 1 }
        }

        let outcome = try await allocator.revertImport(batch, takeVerifiedBackup: Backups(container).take)

        guard case .reverted = outcome else {
            Issue.record("expected the revert to go through, got \(outcome)")
            return
        }
        let cancel = try #require(started.task, "the hook never ran, so the window was never opened")
        await #expect(throws: CancellationRefusal.noSuchInvoice) { try await cancel.value }
        #expect(try Fixture.invoices(in: container).isEmpty)
    }

    /// THE LIST OF WRITERS IS A CLAIM THE REVERT'S SAFETY RESTS ON, so it is checked
    /// against the app rather than trusted (L96, L247). Every source that saves a
    /// context either takes the gate the revert holds, or is named here with the
    /// reason it cannot change a row an import wrote. A new writer that does neither
    /// fails this until somebody decides which it is.
    private static let writersThatCannotReachAnImportedRow: [String: String] = [
        "Ovation/Domain/InvoiceDueDateWriter.swift": "refuses a sent invoice, and an imported one is sent",
        "Ovation/Domain/ShootTimesWriter.swift": "refuses a sent invoice's shoots, and an imported invoice has none",
        "Ovation/Mail/SendSettler.swift": "refuses an invoice already sent",
        "Ovation/Booking/BookingDrafter.swift": "writes new drafts only",
        "Ovation/Domain/ClientStandingWriter.swift": "writes a client, never an invoice's rows",
        "Ovation/Domain/ClientTaxStatusWriter.swift": "writes a client, never an invoice's rows",
        "Ovation/Domain/ReferralLedger.swift": "spends on an invoice only when InvoiceReferralCreditWriter calls it, under the gate",
        "Ovation/Domain/ServiceTypeSeed.swift": "writes service types only",
        "Ovation/Domain/ServiceTypeWriter.swift": "writes service types only",
        "Ovation/App/OvationApp.swift": "saves only the client import at launch, before any screen",
        "Ovation/Document/ReviewSampleWorld.swift": "an in memory sample world, never the store",
        "Ovation/Persistence/OvationSchema.swift": "a migration stage, before the store opens",
    ]

    @Test("every writer either takes the gate the revert holds, or cannot reach an imported row")
    func everyWriterIsAccountedFor() throws {
        let root = Self.repository()
        let app = root.appending(path: "Ovation")
        let walker = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        var savers: [String] = []
        var ungated: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains(".save()") else { continue }
            let path = "Ovation/" + url.path.dropFirst(app.path.count + 1)
            savers.append(path)
            if !text.contains("MoneyWriteGates.gate"), Self.writersThatCannotReachAnImportedRow[path] == nil {
                ungated.append(path)
            }
        }
        #expect(savers.count > 10, "the scan found \(savers.count) writers, so it is not reading the app")
        #expect(ungated.isEmpty, "these save without the gate and are not accounted for: \(ungated.sorted())")
        let stale = Self.writersThatCannotReachAnImportedRow.keys.filter { !savers.contains($0) }
        #expect(stale.isEmpty, "named as writers but no longer saving anything: \(stale.sorted())")
    }

    private static func repository(_ file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
    }

    // MARK: the backup, at the moment of the revert

    @Test("the backup is taken after the guard passes and before anything is deleted")
    func theBackupComesFirst() async throws {
        let container = try Fixture.store()
        let batch = UUID()
        try await Fixture.write(Fixture.run([Spec(number: "1041"), Spec(number: "1042")]),
                                into: container, batch: batch)
        let backups = Backups(container)

        _ = try await Self.allocator(container).revertImport(batch, takeVerifiedBackup: backups.take)

        #expect(backups.taken == [2], "the backup saw a store the revert had already emptied, or was not taken")
    }

    @Test("a backup that fails stops the revert with nothing deleted")
    func aFailedBackupDeletesNothing() async throws {
        let container = try Fixture.store()
        let batch = UUID()
        try await Fixture.write(Fixture.run([Spec(number: "1041")]), into: container, batch: batch)

        let outcome = try await Self.allocator(container)
            .revertImport(batch, takeVerifiedBackup: Backups(container, fails: true).take)

        guard case .backupFailed = outcome else {
            Issue.record("expected the failed backup to stop the revert, got \(outcome)")
            return
        }
        #expect(try Fixture.invoices(in: container).count == 1)
    }

    // MARK: only this batch, and only when there is one

    @Test("a revert removes its own batch and leaves another batch and Dan's own invoices alone")
    func onlyItsOwnBatch() async throws {
        let container = try Fixture.store()
        let first = UUID()
        let second = UUID()
        try await Fixture.write(Fixture.run([Spec(number: "1041")]), into: container, batch: first)
        try await Fixture.write(Fixture.run([Spec(number: "1050")]), into: container, batch: second)
        let context = ModelContext(container)
        context.insert(Invoice(client: nil, kind: .photography, invoiceDate: nil,
                               hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil))
        try context.save()

        _ = try await Self.allocator(container).revertImport(first, takeVerifiedBackup: Backups(container).take)

        let left = try Fixture.invoices(in: container)
        #expect(left.count == 2)
        #expect(left.compactMap(\.number) == [1_050])
    }

    @Test("a batch nothing in the store carries is said as such, never as a revert that worked")
    func nothingToRevertIsItsOwnOutcome() async throws {
        let container = try Fixture.store()
        let backups = Backups(container)
        let outcome = try await Self.allocator(container).revertImport(UUID(), takeVerifiedBackup: backups.take)
        #expect(outcome == .nothingToRevert)
        #expect(backups.taken.isEmpty)
    }

    @Test("the preview says what the revert would remove and what stops it, from the store as it is")
    func thePreviewIsDerived() async throws {
        let container = try Fixture.store()
        let batch = UUID()
        try await Fixture.write(Fixture.run([
            Spec(number: "1041", lines: [.init(cents: 10_000), .init(description: "Rush", cents: 5_000)],
                 paidCents: 0),
            Spec(number: "1042"),
        ]), into: container, batch: batch)

        let preview = try await Self.allocator(container).previewRevert(of: batch)

        #expect(preview == ImportRevertPreview(batch: batch, invoices: 2, lines: 3, payments: 1, blockers: []))
    }
}
