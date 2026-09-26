import Foundation
import SwiftData
import Testing

/// ovation#473, PRD 5.7. Writing the day an invoice falls due.
///
/// UNTIL THIS, THE DUE DATE WAS A FIGURE THE SCREEN PRINTED and nothing could
/// change. The design record draws it as a control with four terms and an
/// "Another date..." panel; this is the write behind both.
///
/// EVERY CASE DRIVES THE ACTOR FROM A DIFFERENT CONTEXT THAN THE ONE READING THE
/// RESULT BACK, because the defect this arrangement exists to prevent is two
/// contexts that do not merge.
@MainActor
struct InvoiceDueDateWriterTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    private static func draft() throws -> (ModelContainer, PersistentIdentifier) {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography,
                              invoiceDate: BusinessCalendar.day(forKey: "2026-11-12"),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        invoice.dueDate = BusinessCalendar.day(forKey: "2026-11-26")
        context.insert(invoice)
        try context.save()
        return (container, invoice.persistentModelID)
    }

    private static func read(_ id: PersistentIdentifier,
                             in container: ModelContainer) throws -> Invoice {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == id })
    }

    // MARK: the date lands

    @Test("a term picked from the list becomes the due date")
    func atermBecomesTheDueDate() async throws {
        let (container, invoiceID) = try Self.draft()
        let day = try #require(BusinessCalendar.day(forKey: "2026-12-12"))

        try await InvoiceDueDateWriter(modelContainer: container)
            .setDueDate(day, on: invoiceID)

        #expect(try Self.read(invoiceID, in: container).dueDate?.dayKey == "2026-12-12")
    }

    /// `On receipt` IS THE INVOICE DATE ITSELF and is a real term rather than a
    /// zero, so the same day is allowed where an earlier one is not.
    @Test("on receipt puts it due the day it was written, which is allowed")
    func onreceiptIsAllowed() async throws {
        let (container, invoiceID) = try Self.draft()
        let day = try #require(BusinessCalendar.day(forKey: "2026-11-12"))

        try await InvoiceDueDateWriter(modelContainer: container)
            .setDueDate(day, on: invoiceID)

        #expect(try Self.read(invoiceID, in: container).dueDate?.dayKey == "2026-11-12")
    }

    // MARK: what cannot be written

    /// DUE BEFORE IT EXISTS. Every reminder is counted from this date, so one
    /// before the invoice was written is already late the moment it is saved, and
    /// it renders as a well formed page that totals correctly against its own
    /// parts (PRD 5.42), which is why nothing downstream would catch it.
    @Test("a date before the invoice was written is refused, and nothing is saved")
    func anearlierDateIsRefused() async throws {
        let (container, invoiceID) = try Self.draft()
        let day = try #require(BusinessCalendar.day(forKey: "2026-11-11"))

        await #expect(throws: InvoiceDueDateRefusal.beforeTheInvoiceDate) {
            try await InvoiceDueDateWriter(modelContainer: container)
                .setDueDate(day, on: invoiceID)
        }
        #expect(try Self.read(invoiceID, in: container).dueDate?.dayKey == "2026-11-26",
                "the refused date was written anyway")
    }

    @Test("a sent invoice's due date is refused rather than rewritten")
    func asentInvoiceIsRefused() async throws {
        let (container, invoiceID) = try Self.draft()
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == invoiceID })
        invoice.number = 1_123
        invoice.sentStatus = .sent(route: .ovationSentIt, at: Self.noon)
        try context.save()
        let day = try #require(BusinessCalendar.day(forKey: "2026-12-12"))

        await #expect(throws: InvoiceDueDateRefusal.invoiceWasSent) {
            try await InvoiceDueDateWriter(modelContainer: container)
                .setDueDate(day, on: invoiceID)
        }
        #expect(try Self.read(invoiceID, in: container).dueDate?.dayKey == "2026-11-26")
    }

    /// AN UNSETTLED SEND IS REFUSED TOO, for ovation#460's reason: the message may
    /// already be with the client, so the render it would change is not Ovation's
    /// to rewrite until the send resolves.
    @Test("a send that has not settled refuses the change, by its own name")
    func anunsettledSendIsRefused() async throws {
        let (container, invoiceID) = try Self.draft()
        let context = ModelContext(container)
        let invoice = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == invoiceID })
        invoice.sentStatus = .couldNotDetermine(checkedAt: Self.noon)
        try context.save()
        let day = try #require(BusinessCalendar.day(forKey: "2026-12-12"))

        await #expect(throws: InvoiceDueDateRefusal.sendIsUnsettled) {
            try await InvoiceDueDateWriter(modelContainer: container)
                .setDueDate(day, on: invoiceID)
        }
    }

    @Test("an invoice that is no longer there is refused by name")
    func agoneInvoiceIsRefused() async throws {
        let (container, invoiceID) = try Self.draft()
        let context = ModelContext(container)
        for each in try context.fetch(FetchDescriptor<Invoice>()) { context.delete(each) }
        try context.save()
        let day = try #require(BusinessCalendar.day(forKey: "2026-12-12"))

        await #expect(throws: InvoiceDueDateRefusal.noSuchInvoice) {
            try await InvoiceDueDateWriter(modelContainer: container)
                .setDueDate(day, on: invoiceID)
        }
    }

    /// EVERY REFUSAL SAYS WHAT HAPPENED, so none can reach the screen mute, and
    /// the lookup is total so a case added later has to be answered rather than
    /// taking a default that reads as a deliberate silence (L109, L113).
    @Test("every refusal says what happened", arguments: [
        InvoiceDueDateRefusal.noSuchInvoice, .invoiceWasSent, .sendIsUnsettled,
        .beforeTheInvoiceDate,
    ])
    func everyRefusalSaysWhatHappened(refusal: InvoiceDueDateRefusal) {
        #expect(refusal.sentence.count > 20, "\(refusal) says \(refusal.sentence)")
        #expect(refusal.sentence.hasSuffix("."))
    }
}
