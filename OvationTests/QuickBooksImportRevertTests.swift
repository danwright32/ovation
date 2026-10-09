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
        private var _parked = false
        var task: Task<Void, Error>? { lock.withLock { _task } }
        /// Whether the writer was seen queued on the gate before the window closed.
        var parked: Bool { lock.withLock { _parked } }
        func set(_ task: Task<Void, Error>) { lock.withLock { _task = task } }
        func markParked(_ parked: Bool) { lock.withLock { _parked = parked } }
    }

    /// How long the window case waits for its writer to queue on the gate before
    /// calling the window untested. Named so it is one decision, read in one place.
    private static let writerReachesTheGate: Duration = .seconds(30)

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
            // WAITS ON THE CONDITION ITSELF (L290), the writer being queued on the
            // gate, and the deadline exists only so a revert that does not hold the
            // gate (which lets the writer straight through) fails here instead of
            // hanging. It is generous because a starved runner can take a long time
            // to start a task, and reaching it means something is wrong, not slow.
            let deadline = ContinuousClock.now + Self.writerReachesTheGate
            while gate.waiting == 0 && ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(1))
            }
            started.markParked(gate.waiting > 0)
        }

        let outcome = try await allocator.revertImport(batch, takeVerifiedBackup: Backups(container).take)

        guard case .reverted = outcome else {
            Issue.record("expected the revert to go through, got \(outcome)")
            return
        }
        let cancel = try #require(started.task, "the hook never ran, so the window was never opened")
        // THE WRITER WAS IN THE WINDOW, or nothing below says anything about it
        // (L475): one that never reached the gate before the delete ran afterwards,
        // and its refusal would read exactly like one that waited.
        #expect(started.parked, "the cancellation never queued on the gate, so the window was not tested")
        await #expect(throws: CancellationRefusal.noSuchInvoice) { try await cancel.value }
        #expect(try Fixture.invoices(in: container).isEmpty)
    }

    /// THE LIST OF WRITERS IS A CLAIM THE REVERT'S SAFETY RESTS ON, so it is checked
    /// against the app rather than trusted (L96, L247). EACH SAVE IS JUDGED WHERE IT
    /// SITS, never by its file: the declaration it sits in must take the gate the
    /// revert holds before it saves, or be named here with the reason it cannot
    /// change a row an import wrote. A file with one gated writer and a second that
    /// saves without the gate is two sites, and the second fails (L135). A new writer
    /// that does neither fails until somebody decides which it is.
    private static let savesThatCannotReachAnImportedRow: [String: String] = [
        "Ovation/Domain/InvoiceDueDateWriter.swift#setDueDate":
            "refuses a sent invoice, and an imported invoice is sent from the moment it is written",
        "Ovation/Domain/ShootTimesWriter.swift#write":
            "refuses a sent invoice's shoots, and an imported invoice is sent and has none",
        "Ovation/Mail/SendSettler.swift#markNotSent": "refuses an invoice already sent",
        "Ovation/Mail/InvoiceSender.swift#send": "refuses an invoice already sent before it writes anything",
        "Ovation/Mail/InvoiceSender.swift#settle": "called only by send, which refuses an invoice already sent",
        "Ovation/Mail/InvoiceSender.swift#savingRecord":
            "the save resend makes after it has taken the gate and found the invoice still there",
        "Ovation/Booking/BookingDrafter.swift#draft": "writes new drafts only",
        "Ovation/Domain/InvoiceNumberAllocator.swift#write":
            "numbers a draft for allocate, which refuses an invoice already numbered, and an imported one always is",
        "Ovation/Domain/InvoiceNumberAllocator.swift#release":
            "refuses an imported invoice's number before it writes anything",
        "Ovation/Domain/ClientStandingWriter.swift#setPaymentTerm": "writes a client, never an invoice's rows",
        "Ovation/Domain/ClientStandingWriter.swift#acknowledgeSharedAddress":
            "writes a client, never an invoice's rows",
        "Ovation/Domain/ClientTaxStatusWriter.swift#setTaxStatus": "writes a client, never an invoice's rows",
        "Ovation/Domain/ReferralLedger.swift#earn":
            "writes an earning against a client and a booking, never an invoice, and nothing in the app calls it",
        "Ovation/Domain/ReferralLedger.swift#withdrawEarning":
            "withdraws an earning by its booking, never an invoice's, and nothing in the app calls it",
        "Ovation/Domain/ReferralLedger.swift#spend":
            "called only by InvoiceReferralCreditWriter, which holds the gate while it calls",
        "Ovation/Domain/ReferralLedger.swift#returnSpend":
            "called only by InvoiceReferralCreditWriter, which holds the gate while it calls",
        "Ovation/Domain/ServiceTypeSeed.swift#seedIfEmpty": "writes service types only",
        "Ovation/Domain/ServiceTypeWriter.swift#create": "writes service types only",
        "Ovation/App/OvationApp.swift#startLaunch": "saves only the client import at launch, before any screen",
        "Ovation/Document/ReviewSampleWorld.swift#presenter": "an in memory sample world, never the store",
        "Ovation/Persistence/OvationSchema.swift#run": "a migration stage, before the store opens",
    ]

    /// Every `.save()` in the app, as "path#declaration", with whether the
    /// declaration it sits in takes the gate before that save.
    private static func saveSites(in app: URL) throws -> [(site: String, file: String, gated: Bool)] {
        let declaration = try Regex(#"^ {0,4}(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:private|fileprivate|nonisolated|static|public|internal|override|final)\s+)*(?:func|let|var)\s+(\w+)"#)
        // RESOLVED ON BOTH SIDES, because the temporary folder a case writes into
        // sits behind a symlink, and a prefix measured on one spelling and cut from
        // the other names every file wrongly.
        let root = app.resolvingSymlinksInPath().path
        let walker = try #require(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        var sites: [(String, String, Bool)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
            let path = "Ovation/" + url.resolvingSymlinksInPath().path.dropFirst(root.count + 1)
            for (index, line) in lines.enumerated() where line.contains(".save()") {
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                var start = index
                var name = "(file)"
                while start >= 0 {
                    if let match = lines[start].firstMatch(of: declaration), let captured = match.output[1].substring {
                        name = String(captured)
                        break
                    }
                    start -= 1
                }
                let region = lines[max(start, 0)...index].joined(separator: "\n")
                sites.append((path + "#" + name, path, region.contains("MoneyWriteGates.gate")))
            }
        }
        return sites
    }

    @Test("every save either takes the gate the revert holds, or cannot reach an imported row")
    func everyWriterIsAccountedFor() throws {
        let sites = try Self.saveSites(in: Self.repository().appending(path: "Ovation"))
        let exempt = Self.savesThatCannotReachAnImportedRow
        // BY DECLARATION ONLY, never a whole file (L362): an exemption names the one
        // place it reasons about, so a new save added beside it is a new site.
        #expect(exempt.keys.allSatisfy { $0.contains("#") }, "an exemption names a whole file")
        let unaccounted = sites.filter { !$0.gated && exempt[$0.site] == nil }.map(\.site)
        #expect(sites.count > 20, "the scan found \(sites.count) saves, so it is not reading the app")
        #expect(unaccounted.isEmpty, "these save without the gate and are not accounted for: \(unaccounted.sorted())")
        let named = Set(sites.map(\.site))
        let stale = exempt.keys.filter { !named.contains($0) }
        #expect(stale.isEmpty, "named as saving but no save sits there any more: \(stale.sorted())")
    }

    @Test("and the scan judges each save on its own, so a second ungated save beside a gated one is found")
    func theScanJudgesEachSave() throws {
        // SEEN TO FAIL ON PURPOSE (L1): a file whose first writer takes the gate and
        // whose second does not, which the file level scan this replaced passed.
        let folder = FileManager.default.temporaryDirectory.appending(path: "save-scan-\(UUID().uuidString)")
        let app = folder.appending(path: "Ovation")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("""
        actor Writer {
            func gated() async throws {
                let gate = MoneyWriteGates.gate(for: modelContainer)
                await gate.lock()
                try modelContext.save()
            }

            func ungated() throws {
                try modelContext.save()
            }
        }
        """.utf8).write(to: app.appending(path: "Writer.swift"))

        let sites = try Self.saveSites(in: app)

        #expect(sites.map(\.site) == ["Ovation/Writer.swift#gated", "Ovation/Writer.swift#ungated"])
        #expect(sites.map(\.gated) == [true, false])
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
