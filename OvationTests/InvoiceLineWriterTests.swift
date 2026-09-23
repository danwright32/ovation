import Foundation
import SwiftData
import Testing

/// ovation#457, PRD 5.4. Adding a line to an invoice.
///
/// IT IS A WRITER OF MONEY AGAINST AN INVOICE, so it takes the store's
/// `MoneyWriteGate` like the other two. `PaymentAllocator` refuses an allocation
/// larger than `invoice.amountOutstanding`, which is derived from the invoice's
/// total, and a line changes that total: a line written while an allocation is
/// deciding leaves the allocation's ceiling describing an invoice that no longer
/// exists (ovation#175, L157).
///
/// EVERY CASE DRIVES THE ACTOR FROM A DIFFERENT CONTEXT THAN THE ONE READING THE
/// RESULT BACK, the arrangement the other writers' suites use, because the defect
/// it exists to prevent is two contexts that do not merge.
///
/// NOTHING HERE REFUSES A NEGATIVE AMOUNT, and that is a decision rather than a
/// gap. `LineItem.flat` says in terms that a flat line may be negative, and the
/// design record's own control refuses only an amount it cannot READ. A refusal
/// written here would contradict a recorded decision on the reasoning that a
/// negative line is a discount by another name, which is sound and is not mine to
/// settle (L542). `Invoice.refusals` still catches the harmful end of it with
/// `totalBelowZero`.
@MainActor
struct InvoiceLineWriterTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    private static func draft() throws
        -> (ModelContainer, PersistentIdentifier, PersistentIdentifier) {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography,
                              invoiceDate: BusinessCalendar.day(forKey: "2026-11-12"),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        context.insert(invoice)
        let type = ServiceType(name: "Rush turnaround", role: .ordinary,
                               defaultUnitAmount: Money(dollars: 150))
        context.insert(type)
        try context.save()
        return (container, invoice.persistentModelID, type.persistentModelID)
    }

    private static func read(_ id: PersistentIdentifier,
                             in container: ModelContainer) throws -> Invoice {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == id })
    }

    // MARK: the line lands

    @Test("a line carries the type's name, its amount and the type itself")
    func alineCarriesItsTypeAndAmount() async throws {
        let (container, invoiceID, typeID) = try Self.draft()

        try await InvoiceLineWriter(modelContainer: container)
            .addLine(ofType: typeID, amount: Money(dollars: 150), to: invoiceID)

        let lines = try Self.read(invoiceID, in: container).lineItems
        #expect(lines.count == 1)
        #expect(lines.first?.summary == "Rush turnaround")
        #expect(lines.first?.amount == Money(dollars: 150))
        #expect(lines.first?.serviceType?.name == "Rush turnaround")
    }

    /// A FLAT LINE HAS NO HOURS, and the whole charge is its unit amount, which
    /// is what `LineItem.flat` means by flat. The screen draws its hours and rate
    /// columns blank for exactly this reason: a quantity of nothing is not drawn.
    ///
    /// AND IT IS FOR NO SHOOT. PRD 4 puts rush turnaround and preview images on
    /// the invoice rather than on a shoot, and `LineItem.flat` takes no shoot at
    /// all so that none can be assigned: a flat charge that reached a shoot was
    /// priced as hours times its amount, and $150 of rush turnaround on a three
    /// hour shoot came to $450 on an invoice that totalled correctly against its
    /// own parts (ovation#431).
    @Test("an added line has no hours and belongs to no shoot")
    func anaddedLineHasNoHoursAndNoShoot() async throws {
        let (container, invoiceID, typeID) = try Self.draft()

        try await InvoiceLineWriter(modelContainer: container)
            .addLine(ofType: typeID, amount: Money(dollars: 75), to: invoiceID)

        let line = try #require(try Self.read(invoiceID, in: container).lineItems.first)
        #expect(line.hours == nil)
        #expect(line.shoot == nil)
        #expect(line.amount == Money(dollars: 75))
    }

    /// A ZERO IS A LEGITIMATE COMPED LINE (PRD 5.1b), so it is written rather
    /// than refused. This is the case a guard written as "an amount must be
    /// positive" would silently take away.
    @Test("a line worth nothing is written, because a comped line is a real one")
    func azeroLineIsWritten() async throws {
        let (container, invoiceID, typeID) = try Self.draft()

        try await InvoiceLineWriter(modelContainer: container)
            .addLine(ofType: typeID, amount: .zero, to: invoiceID)

        #expect(try Self.read(invoiceID, in: container).lineItems.count == 1)
    }

    // MARK: what cannot be written

    @Test("a sent invoice is refused a new line, and keeps the lines it has")
    func asentInvoiceIsRefused() async throws {
        let (container, invoiceID, typeID) = try Self.draft()
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == invoiceID })
        invoice.number = 1_123
        invoice.sentStatus = .sent(route: .ovationSentIt, at: Self.noon)
        try context.save()

        await #expect(throws: InvoiceLineRefusal.invoiceWasSent) {
            try await InvoiceLineWriter(modelContainer: container)
                .addLine(ofType: typeID, amount: Money(dollars: 150), to: invoiceID)
        }
        #expect(try Self.read(invoiceID, in: container).lineItems.isEmpty)
    }

    /// RETIRED RATHER THAN DELETED (PRD 5.30), so the type is still there to be
    /// asked for and must be refused by name rather than not found.
    @Test("a retired service type is refused by its own name")
    func aretiredTypeIsRefused() async throws {
        let (container, invoiceID, typeID) = try Self.draft()
        let context = ModelContext(container)
        let type = try #require(try context.fetch(FetchDescriptor<ServiceType>())
            .first { $0.persistentModelID == typeID })
        type.retiredOn = BusinessCalendar.day(forKey: "2026-11-01")
        try context.save()

        await #expect(throws: InvoiceLineRefusal.serviceTypeIsRetired) {
            try await InvoiceLineWriter(modelContainer: container)
                .addLine(ofType: typeID, amount: Money(dollars: 150), to: invoiceID)
        }
    }

    @Test("an invoice that is no longer there is refused by name")
    func agoneInvoiceIsRefused() async throws {
        let (container, invoiceID, typeID) = try Self.draft()
        let context = ModelContext(container)
        for each in try context.fetch(FetchDescriptor<Invoice>()) { context.delete(each) }
        try context.save()

        await #expect(throws: InvoiceLineRefusal.noSuchInvoice) {
            try await InvoiceLineWriter(modelContainer: container)
                .addLine(ofType: typeID, amount: Money(dollars: 150), to: invoiceID)
        }
    }

    @Test("a service type that is no longer there is refused by name")
    func agoneTypeIsRefused() async throws {
        let (container, invoiceID, typeID) = try Self.draft()
        let context = ModelContext(container)
        for each in try context.fetch(FetchDescriptor<ServiceType>()) { context.delete(each) }
        try context.save()

        await #expect(throws: InvoiceLineRefusal.noSuchServiceType) {
            try await InvoiceLineWriter(modelContainer: container)
                .addLine(ofType: typeID, amount: Money(dollars: 150), to: invoiceID)
        }
    }

    @Test("every refusal carries a sentence, and none of them is empty")
    func everyrefusalSaysSomething() {
        for refusal in InvoiceLineRefusal.allCases {
            #expect(refusal.sentence.isEmpty == false)
            #expect(refusal.sentence.hasSuffix("."))
        }
    }

    // MARK: it waits for the money gate

    /// THE EXCLUSION IS REAL OR IT IS DECORATION (L1). The wait is on the gate's
    /// own count of who is queued on it, never on a duration, so this measures
    /// the exclusion rather than the machine's load (L290).
    @Test("a line waits while something else is writing money against the store")
    func alineWaitsForTheGate() async throws {
        let (container, invoiceID, typeID) = try Self.draft()
        let gate = MoneyWriteGates.gate(for: container)
        await gate.lock()

        let writing = Task {
            try await InvoiceLineWriter(modelContainer: container)
                .addLine(ofType: typeID, amount: Money(dollars: 150), to: invoiceID)
        }
        // WAIT UNTIL IT IS DEMONSTRABLY QUEUED, which is what makes the absence
        // below mean something rather than meaning it had not started (L159).
        //
        // AND THE WAIT ENDS ON EITHER OUTCOME, so a writer that stops taking the
        // gate fails this case with a sentence instead of spinning here until
        // the suite times out and names the assertion that was running rather
        // than the cost that caused it (L511). The bound is a count of turns
        // rather than a duration, so it is not a measurement of the machine.
        var queued = false
        for _ in 0 ..< 10_000 {
            if gate.waiting > 0 { queued = true; break }
            if try !Self.read(invoiceID, in: container).lineItems.isEmpty { break }
            await Task.yield()
        }

        #expect(queued, "the line writer never queued on the money gate")
        #expect(try Self.read(invoiceID, in: container).lineItems.isEmpty,
                "the line was written while the gate was held")

        gate.unlock()
        try await writing.value

        #expect(try Self.read(invoiceID, in: container).lineItems.count == 1)
    }
}
