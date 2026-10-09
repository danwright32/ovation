import Foundation
import SwiftData
import Testing

/// ovation#68, ovation#69 and ovation#71. The QuickBooks import's store write: each
/// invoice the three exports agree about is written under the number QuickBooks
/// issued, with its lines and the payments QuickBooks recorded against it, keyed
/// on the rows it came from and stamped with the run that wrote it.
///
/// EVERY CASE RUNS IN AN IN MEMORY STORE (`QuickBooksImportFixture.store`), so no
/// case can reach Dan's own (L2).
struct QuickBooksImportWriterTests {

    private typealias Fixture = QuickBooksImportFixture
    private typealias Spec = QuickBooksImportFixture.Spec
    private typealias Line = QuickBooksImportFixture.Line

    private static func day(_ key: String) throws -> BusinessDate {
        try #require(BusinessCalendar.day(forKey: key))
    }

    // MARK: what is written

    @Test("an invoice the exports agree about is written under the number QuickBooks issued, with its lines")
    func anAgreedInvoiceIsWritten() async throws {
        let container = try Fixture.store()
        let run = Fixture.run([Spec(number: "1041", lines: [
            Line(description: "Imaginary gala", quantity: "2.50", price: "250.00", cents: 62_500),
            Line(description: "Rush delivery", cents: 15_000),
        ])])

        let write = try await Fixture.write(run, into: container)

        #expect(write.written == [6])
        let invoice = try #require(try Fixture.invoices(in: container).first)
        #expect(invoice.number == 1_041)
        #expect(invoice.client?.name == "Fictive Quartet")
        #expect(invoice.kind == .notRecorded, "PRD 2b: an import never asserts what the money was for")
        #expect(invoice.invoiceDate == (try Self.day("2026-01-19")))
        #expect(invoice.dueDate == (try Self.day("2026-02-18")))
        #expect(invoice.createdOn == nil, "QuickBooks never said when it was created (L192)")
        #expect(invoice.orderedLineItems.map(\.summary) == ["Imaginary gala", "Rush delivery"])
        #expect(invoice.orderedLineItems.map(\.hours) == [Hours(hundredths: 250), nil])
        #expect(invoice.orderedLineItems.map(\.amount) == [Money(cents: 62_500), Money(cents: 15_000)])
        #expect(invoice.total == Money(cents: 77_500), "Ovation's own arithmetic arrives at QuickBooks' total")
    }

    @Test("an imported invoice was billed in QuickBooks on its own date, and Ovation says so")
    func animportedInvoiceIsBilledInQuickBooks() async throws {
        let container = try Fixture.store()
        try await Fixture.write(Fixture.run([Spec(number: "1041")]), into: container)

        let invoice = try #require(try Fixture.invoices(in: container).first)
        let day = try Self.day("2026-01-19")
        #expect(invoice.sentStatus == .sent(route: .billedInQuickBooks, at: day.instant))
        #expect(invoice.taxStatusWhenSent == .exempt, "it went out under the status it was charged under")
        let history = InvoiceHistory(invoice)
        #expect(history.entries.first { $0.id == "sent" }?.more == "billed in QuickBooks")
    }

    @Test("the payments QuickBooks recorded come with the invoice, recorded with no method")
    func paymentsComeWithTheInvoice() async throws {
        let container = try Fixture.store()
        try await Fixture.write(Fixture.run([
            Spec(number: "1041", lines: [Line(cents: 40_000)], paidCents: 15_000),
            Spec(number: "1042", client: "Fictive Quartet", lines: [Line(cents: 20_000)], paidCents: 0),
        ]), into: container)

        let invoices = try Fixture.invoices(in: container)
        #expect(invoices.map(\.amountPaid) == [Money(cents: 15_000), .zero])
        #expect(invoices.map(\.paymentState) == [.partlyPaid, .unpaid])
        let payment = try #require(try Fixture.payments(in: container).first)
        #expect(try Fixture.payments(in: container).count == 1)
        #expect(payment.method == .notRecorded, "QuickBooks exports the account, never the method")
        #expect(payment.receivedOn == (try Self.day("2026-01-25")))
        #expect(!payment.isWaitingToClear, "an imported payment must never wait on Dan to confirm it")
        #expect(payment.allocations.first?.source == .recordedWithThePayment)
        let paid = try #require(invoices.first)
        #expect(InvoiceHistory(paid).entries.first(where: \.isPayment)?.more == "$150.00 by a method not recorded")
    }

    // MARK: the key and the batch (ovation#68, ovation#69)

    @Test("every row an import writes carries its key and the run that wrote it")
    func everyRowCarriesItsKeyAndBatch() async throws {
        let container = try Fixture.store()
        let run = Fixture.run([Spec(number: "1041", paidCents: 4_000)])
        let batch = UUID()
        try await Fixture.write(run, into: container, batch: batch)

        let candidate = try #require(run.candidates().first)
        let invoice = try #require(try Fixture.invoices(in: container).first)
        #expect(invoice.importKey == candidate.key.value)
        #expect(invoice.importBatchID == batch)
        let payment = try #require(try Fixture.payments(in: container).first)
        #expect(payment.importKey == candidate.payments.first?.key.value)
        #expect(payment.importBatchID == batch)
        #expect(payment.allocations.map(\.importBatchID) == [batch])
        // THE STATE A REVERT COMPARES AGAINST is recorded in the same save.
        #expect(ImportedState.matches(invoice.importedFingerprint, invoice))
        #expect(ImportedState.matches(payment.importedFingerprint, payment))
    }

    @Test("an invoice's key covers every row it came from, in every file")
    func theKeyCoversEveryContributingRow() throws {
        let run = Fixture.run([Spec(number: "1041", paidCents: 4_000)])
        let candidate = try #require(run.candidates().first)
        let sources = [
            QuickBooksImportKey.Source(fileSHA256: run.invoiceList.fileSHA256, row: candidate.invoice.row,
                                       rawRowSHA256: candidate.invoice.rawRowSHA256),
        ] + candidate.lines.map {
            QuickBooksImportKey.Source(fileSHA256: run.salesLines.fileSHA256, row: $0.row, rawRowSHA256: $0.rawRowSHA256)
        } + candidate.payments.map {
            QuickBooksImportKey.Source(fileSHA256: run.invoicesAndPayments.fileSHA256, row: $0.row.row,
                                       rawRowSHA256: $0.row.rawRowSHA256)
        }
        #expect(candidate.key == QuickBooksImportKey(sources: sources))
        #expect(candidate.payments.first?.key == QuickBooksImportKey(sources: [sources[2]]))
    }

    @Test("two payments written alike under two clients are two payments, and the second still comes in later")
    func identicalPaymentRowsAreTwoPayments() async throws {
        // REVIEW OF 1e824ef (L186): the same date and amount under two clients is the
        // same text twice. The second client is missing on the first run, added, and
        // the second run must write its invoice and its payment, not refuse the
        // payment as one an earlier batch already wrote.
        let container = try Fixture.store()
        let run = Fixture.run([Spec(number: "1041"), Spec(number: "1042", client: "Twin Ensemble")])
        let candidates = run.candidates()
        #expect(Set(candidates.flatMap(\.payments).map(\.key)).count == 2, "two payments, one key")

        let first = try await Fixture.write(run, into: container)
        #expect(first.refused == [.init(invoiceRow: 7, reason: .clientNotInOvation)])
        let context = ModelContext(container)
        context.insert(Client(name: "Twin Ensemble", taxStatus: .exempt))
        try context.save()

        let second = try await Fixture.write(run, into: container)

        #expect(second.written == [7])
        #expect(second.alreadyImported == [6])
        #expect(try Fixture.payments(in: container).count == 2)
    }

    @Test("the same import run twice writes nothing the second time, and says each was already imported")
    func aSecondRunWritesNothing() async throws {
        // Assume it runs twice (L33): an interrupted import started again must not
        // double every invoice.
        let container = try Fixture.store()
        let run = Fixture.run([Spec(number: "1041", paidCents: 4_000), Spec(number: "1042")])
        try await Fixture.write(run, into: container)

        let again = try await Fixture.write(run, into: container)

        #expect(again.written.isEmpty)
        #expect(again.alreadyImported == [6, 7])
        #expect(again.refused.isEmpty, "already imported is its own outcome, never a refusal")
        #expect(try Fixture.invoices(in: container).count == 2)
        #expect(try Fixture.payments(in: container).count == 2)
    }

    @Test("a corrected importer is a new key, and still cannot put a second invoice on a number")
    func aCorrectedImporterCannotDoubleAnInvoice() async throws {
        let container = try Fixture.store()
        let run = Fixture.run([Spec(number: "1041")])
        try await Fixture.write(run, into: container, version: 1)

        let corrected = try await Fixture.write(run, into: container, version: 2)

        #expect(corrected.alreadyImported.isEmpty, "a corrected importer is a different key (L121)")
        #expect(corrected.refused == [.init(invoiceRow: 6, reason: .numberAlreadyHeld(number: 1_041))])
        #expect(try Fixture.invoices(in: container).count == 1)
    }

    // MARK: a number already held (ovation#71)

    @Test("an import refuses a number Ovation already issued, and writes nothing for that invoice")
    func animportCannotTakeAnAllocatedNumber() async throws {
        // Plan 1.10's seen to fail: allocate 1130, then import a row carrying 1130.
        let container = try Fixture.store()
        let allocator = InvoiceNumberAllocator(modelContainer: container)
        var allocated: Int64 = 0
        while allocated < 1_130 { allocated = try await allocator.allocate(to: try Self.newDraft(in: container)) }

        let write = try await Fixture.write(Fixture.run([Spec(number: "1130", paidCents: 4_000), Spec(number: "1131")]),
                                            into: container)

        #expect(write.refused == [.init(invoiceRow: 6, reason: .numberAlreadyHeld(number: 1_130))])
        #expect(write.written == [7], "the other invoice is not held up by its neighbour's refusal")
        let numbers = try Fixture.invoices(in: container).compactMap(\.number)
        #expect(numbers.filter { $0 == 1_130 }.count == 1, "no two invoices share a number")
        let payments = try Fixture.payments(in: container)
        #expect(payments.flatMap(\.allocations).compactMap(\.invoice?.number) == [1_131],
                "the refused invoice's payment came in anyway")
    }

    @Test("and the allocator never takes a number an import brought in")
    func theallocatorSkipsAnImportedNumber() async throws {
        let container = try Fixture.store()
        try await Fixture.write(Fixture.run([Spec(number: "1123")]), into: container)

        let allocated = try await InvoiceNumberAllocator(modelContainer: container)
            .allocate(to: try Self.newDraft(in: container))

        #expect(allocated == 1_124, "it went above the imported one rather than onto it")
    }

    @Test("a number at or below zero is refused, because no invoice carries one")
    func anumberMustBeReal() async throws {
        let container = try Fixture.store()
        let write = try await Fixture.write(Fixture.run([Spec(number: "0")]), into: container)
        #expect(write.refused == [.init(invoiceRow: 6, reason: .numberIsNotPositive)])
        #expect(try Fixture.invoices(in: container).isEmpty)
    }

    // MARK: what else refuses an invoice

    @Test("a client Ovation does not hold, or holds twice under one name, refuses the invoice by name")
    func theclientMustResolveToOne() async throws {
        let container = try Fixture.store(clients: [("Fictive Quartet", .exempt),
                                                    ("Twin Ensemble", .exempt), ("Twin Ensemble", .exempt)])
        let write = try await Fixture.write(Fixture.run([
            Spec(number: "1041", client: "Imaginary Opera"),
            Spec(number: "1042", client: "Twin Ensemble"),
            Spec(number: "1043"),
        ]), into: container)

        #expect(write.refused == [.init(invoiceRow: 6, reason: .clientNotInOvation),
                                  .init(invoiceRow: 7, reason: .clientNameHeldBySeveral(count: 2))])
        #expect(write.written == [8])
    }

    @Test("an invoice Ovation would total differently is refused, and leaves nothing behind")
    func aDifferentTotalIsRefused() async throws {
        // A client Ovation charges tax, on an invoice QuickBooks charged none: the
        // invoice would read as owing tax nobody billed (L150).
        let container = try Fixture.store(clients: [("Fictive Quartet", .notExempt)])
        let write = try await Fixture.write(Fixture.run([Spec(number: "1041", paidCents: 4_000)]), into: container)

        guard case .totalDiffers(let ovation, let quickBooks)? = write.refused.first?.reason else {
            Issue.record("expected a total refusal, got \(write.refused)")
            return
        }
        #expect(quickBooks == Money(cents: 10_000))
        #expect(ovation > quickBooks)
        #expect(try Fixture.invoices(in: container).isEmpty)
        #expect(try ModelContext(container).fetch(FetchDescriptor<LineItem>()).isEmpty, "its lines were left behind")
        #expect(try Fixture.payments(in: container).isEmpty)
    }

    @Test("what was written is read back from the store, not from what the writer held")
    func theWriteIsReadBack() async throws {
        let container = try Fixture.store()
        let batch = UUID()
        let write = try await Fixture.write(Fixture.run([Spec(number: "1041"), Spec(number: "1042")]),
                                            into: container, batch: batch)
        let stored = try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .filter { $0.importBatchID == batch }
        #expect(stored.count == write.written.count)
        #expect(write.batch == batch)
    }

    // MARK: helpers

    private static func newDraft(in container: ModelContainer) throws -> PersistentIdentifier {
        let context = ModelContext(container)
        let draft = Invoice(client: nil, kind: .fromABooking, invoiceDate: try day("2026-03-02"),
                            hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        context.insert(draft)
        try context.save()
        return draft.persistentModelID
    }
}
