import Foundation
import SwiftData
import Testing

/// ovation#482, PRD 51j1. A sent invoice keeps the tax it went out with.
///
/// PRD 5a1 has an invoice read its client's sales tax status when it is drawn, and
/// the client's page can now correct that status. Dan decided on 2026-09-23 that
/// what went out is what it says, and that the correction applies to "drafts and
/// every invoice from now on". So the send records the status it went out under,
/// a sent invoice reads that, and a draft goes on reading its client.
///
/// EVERY FIGURE IS ASSERTED AFTER THE CLIENT'S STATUS HAS BEEN CHANGED, because
/// before a change the stamp and the client agree and a test that never changes
/// the status cannot tell reading one from reading the other (L159).
struct SentTaxStatusTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    /// One $1,000.00 flat line for a client under `status`, so the tax at 8.875%
    /// is $88.75 and an exempt client's is nothing.
    private static func invoice(_ context: ModelContext, client status: TaxStatus) -> Invoice {
        let client = Client(name: "Calder Street Theatre", taxStatus: status)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography,
                              invoiceDate: BusinessCalendar.day(forKey: "2026-11-12"),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        context.insert(invoice)
        invoice.add(LineItem.flat(Money(dollars: 1_000), describedAs: "Autumn gala"))
        return invoice
    }

    private static let attempt = SentStatus.attempting(SendAttempt(
        destination: ["box@calder.example"], wasRedirected: false, renderSHA256: "abc",
        startedAt: noon))

    private static func correct(_ invoice: Invoice, to status: TaxStatus) {
        let client = invoice.client
        client?.taxStatus = status
    }

    // MARK: a draft follows its client

    @Test("a draft follows its client's status, so a correction reaches it")
    func adraftFollowsItsClient() throws {
        let context = try Self.store()
        let draft = Self.invoice(context, client: .notExempt)
        #expect(draft.tax == Money(cents: 8_875))

        Self.correct(draft, to: .exempt)

        #expect(draft.taxStatusWhenSent == nil)
        #expect(draft.taxStatusCharged == .exempt)
        #expect(draft.tax == .zero)
    }

    // MARK: a send records what it went out under

    @Test("the moment a send is attempted, the client's status is recorded on the invoice",
          arguments: ["attempting", "sent"])
    func asendRecordsTheStatus(state: String) throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, client: .notExempt)

        invoice.recordSendState(state == "sent" ? .sent(route: .ovationSentIt, at: Self.noon)
                                                : Self.attempt)

        #expect(invoice.taxStatusWhenSent == .notExempt)
    }

    /// Review of ovation#600: "never recorded" is the ABSENCE of an answer, and a
    /// stamp of it would stick for ever while the invoice screen hides the tax row for
    /// it. The send gate refuses such a client, so only a route around the gate (a
    /// Sent folder match, ovation#41) could reach this, and it records nothing.
    @Test("a send for a client with no recorded status records none")
    func neverRecordedIsNeverStamped() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, client: .neverRecorded)

        invoice.recordSendState(.sent(route: .foundInTheMailbox, at: Self.noon))

        #expect(invoice.taxStatusWhenSent == nil)
        #expect(!invoice.stampSentTaxStatusIfMissing())
    }

    @Test("a sent invoice keeps the tax it went out with when the client is corrected")
    func asentInvoiceKeepsItsTax() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, client: .notExempt)
        invoice.recordSendState(Self.attempt)
        invoice.recordSendState(.sent(route: .ovationSentIt, at: Self.noon))

        Self.correct(invoice, to: .exempt)

        #expect(invoice.taxStatusCharged == .notExempt)
        #expect(invoice.tax == Money(cents: 8_875))
        #expect(invoice.total == Money(cents: 108_875))
    }

    @Test("and the other way: an invoice sent exempt stays untaxed when the client is corrected")
    func anexemptSendStaysUntaxed() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, client: .exempt)
        invoice.recordSendState(.sent(route: .ovationSentIt, at: Self.noon))

        Self.correct(invoice, to: .notExempt)

        #expect(invoice.tax == .zero)
        #expect(invoice.total == Money(dollars: 1_000))
    }

    @Test("settling an attempt as sent keeps the status recorded when it was attempted")
    func settlingKeepsTheFirstRecord() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, client: .notExempt)
        invoice.recordSendState(Self.attempt)

        Self.correct(invoice, to: .exempt)
        invoice.recordSendState(.sent(route: .ovationSentIt, at: Self.noon))

        #expect(invoice.taxStatusWhenSent == .notExempt,
                "the render that went out was taken under the status at the attempt")
    }

    @Test("a send that turns out not to have happened is a draft again, and follows its client")
    func anunsentInvoiceFollowsItsClientAgain() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, client: .notExempt)
        invoice.recordSendState(Self.attempt)

        invoice.recordSendState(.notSent)
        Self.correct(invoice, to: .exempt)

        #expect(invoice.taxStatusWhenSent == nil)
        #expect(invoice.tax == .zero)
    }

    // MARK: the invoices sent before version 6

    /// An invoice as version 5 left it: gone out, with no status recorded. The
    /// send can no longer be recorded without one, so the stamp is taken off again,
    /// which is exactly the state the stage carries forward.
    private static func sentBeforeVersionSix(_ invoice: Invoice, _ status: SentStatus) {
        invoice.recordSendState(status)
        invoice.taxStatusWhenSent = nil
    }

    @Test("an invoice already out with nothing recorded is stamped with its client's status",
          arguments: ["sent", "attempting", "could not determine"])
    func anearlierSendIsStamped(state: String) throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, client: .exempt)
        switch state {
        case "sent": Self.sentBeforeVersionSix(invoice, .sent(route: .ovationSentIt, at: Self.noon))
        case "attempting": Self.sentBeforeVersionSix(invoice, Self.attempt)
        default: Self.sentBeforeVersionSix(invoice, .couldNotDetermine(checkedAt: Self.noon))
        }

        #expect(invoice.stampSentTaxStatusIfMissing())
        #expect(invoice.taxStatusWhenSent == .exempt)
    }

    @Test("a draft is not stamped, and a recorded status is never overwritten")
    func thestampFillsOnlyWhatIsMissing() throws {
        let context = try Self.store()
        let draft = Self.invoice(context, client: .exempt)
        let sent = Self.invoice(context, client: .notExempt)
        sent.recordSendState(.sent(route: .ovationSentIt, at: Self.noon))
        Self.correct(sent, to: .exempt)

        #expect(!draft.stampSentTaxStatusIfMissing())
        #expect(draft.taxStatusWhenSent == nil)
        #expect(!sent.stampSentTaxStatusIfMissing())
        #expect(sent.taxStatusWhenSent == .notExempt)
    }

    @Test("the backfill stamps every earlier send once, and a second run changes nothing")
    func thebackfillIsIdempotent() throws {
        let context = try Self.store()
        let first = Self.invoice(context, client: .exempt)
        Self.sentBeforeVersionSix(first, .sent(route: .ovationSentIt, at: Self.noon))
        let second = Self.invoice(context, client: .notExempt)
        Self.sentBeforeVersionSix(second, .sent(route: .foundInTheMailbox, at: Self.noon))
        _ = Self.invoice(context, client: .notExempt)
        try context.save()

        #expect(try SentTaxStatusBackfill.run(in: context) == 2)
        #expect(try SentTaxStatusBackfill.run(in: context) == 0)
        #expect(first.taxStatusWhenSent == .exempt)
        #expect(second.taxStatusWhenSent == .notExempt)
    }
}
