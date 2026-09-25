import Foundation
import SwiftData
import Testing

/// ovation#471. Dan saying an invoice whose send Ovation could not settle did not go.
///
/// HE MAY CLEAR ONE, NEVER ASSERT ONE (Dan, 2026-09-21), so this writes exactly one
/// transition, an unsettled send back to a draft, and refuses every other. The
/// number stays: he can be wrong, and a kept number turns a wrong answer into a
/// duplicate of one document rather than two invoices sharing a number.
///
/// EVERY CASE DRIVES THE ACTOR FROM A DIFFERENT CONTEXT THAN THE ONE READING THE
/// RESULT BACK, as the other writers' tests do.
@MainActor
struct SendSettlerTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    private static func invoice(_ status: SentStatus, number: Int64? = 1_123) throws
        -> (ModelContainer, PersistentIdentifier) {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography,
                              invoiceDate: BusinessCalendar.day(forKey: "2026-11-12"),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        invoice.number = number
        invoice.sentStatus = status
        context.insert(invoice)
        try context.save()
        return (container, invoice.persistentModelID)
    }

    private static let attempt = SentStatus.attempting(SendAttempt(
        destination: ["booker@client.example"], wasRedirected: false,
        renderSHA256: "abc", startedAt: noon))

    private static func read(_ id: PersistentIdentifier, in container: ModelContainer) throws -> Invoice {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Invoice>())
            .first { $0.persistentModelID == id })
    }

    @Test("an unsettled send goes back to a draft and keeps its number", arguments: [
        "attempting", "could not determine",
    ])
    func anunsettledSendBecomesADraft(state: String) async throws {
        let status = state == "attempting" ? Self.attempt : .couldNotDetermine(checkedAt: Self.noon)
        let (container, id) = try Self.invoice(status)

        try await SendSettler(modelContainer: container).markNotSent(id)

        let after = try Self.read(id, in: container)
        #expect(after.sentStatus == .notSent)
        #expect(after.number == 1_123)
    }

    @Test("a sent invoice is refused, and stays sent")
    func asentInvoiceIsRefused() async throws {
        let sent = SentStatus.sent(route: .ovationSentIt, at: Self.noon)
        let (container, id) = try Self.invoice(sent)

        await #expect(throws: SendSettleRefusal.invoiceWasSent) {
            try await SendSettler(modelContainer: container).markNotSent(id)
        }
        #expect(try Self.read(id, in: container).sentStatus == sent)
    }

    @Test("an ordinary draft is refused, because there is nothing to settle")
    func adraftIsRefused() async throws {
        let (container, id) = try Self.invoice(.notSent)

        await #expect(throws: SendSettleRefusal.nothingToSettle) {
            try await SendSettler(modelContainer: container).markNotSent(id)
        }
    }

    @Test("each refusal says what happened")
    func eachRefusalIsSaid() {
        #expect(SendSettleRefusal.invoiceWasSent.sentence == "This invoice was sent, so it cannot be marked unsent.")
        #expect(SendSettleRefusal.nothingToSettle.sentence == "This invoice is already a draft, so there is nothing to settle.")
        #expect(SendSettleRefusal.noSuchInvoice.sentence == "That invoice is no longer there, so nothing changed.")
    }

    /// WHAT THE CONFIRMATION SAYS is derived from the invoice it acts on (L180), and
    /// names both halves of the consequence: what changes, and the risk Dan takes.
    @Test("the confirmation names the number it keeps and the risk of sending twice")
    func theconfirmationNamesTheConsequence() {
        #expect(SendSettler.confirmation(number: 1_123)
                == "Invoice 1123 goes back to being a draft and keeps its number. If it did reach the client, sending it again sends the same invoice twice.")
    }
}
