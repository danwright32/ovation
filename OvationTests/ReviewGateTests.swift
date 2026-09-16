import Foundation
import SwiftData
import Testing
@testable import Ovation

/// ovation#318 B4, PRD 51b and 52g. Whether Review can be pressed at all, and the
/// ONE sentence it says when it cannot.
///
/// A GREYED CONTROL WITH NO REASON IS A DEAD CONTROL (L109). The invoice screen's
/// foot says Review, and an invoice that cannot go out must not open a sheet whose
/// whole purpose is approving a send, so the refusal is stated where the control is.
///
/// ONE SENTENCE, NOT A LIST. Several reasons at once is the ordinary case for a
/// half filled draft, and a control cannot say four things; the ORDER is the
/// decision, and it is written down here rather than left to whichever the set
/// happens to yield first (L170, L343).
///
/// THE WORDS COME FROM THE SHARED VOCABULARY, `docs/design/rules/waiting.js`, which
/// the invoice screen's design already draws from, so the same condition cannot be
/// worded two ways on two surfaces (L118).
@MainActor
struct ReviewGateTests {

    @Test("an invoice with nothing wrong may be reviewed")
    func anordinaryInvoiceMayBeReviewed() throws {
        let invoice = try Self.invoice()

        #expect(ReviewGate.refusal(for: invoice) == nil)
    }

    @Test("a client whose tax status was never recorded is waiting on that")
    func anunrecordedTaxStatusRefuses() throws {
        // ovation#128: a missing status is not the same as not exempt. The tax is
        // charged AND the send is refused until it is answered.
        let invoice = try Self.invoice(taxStatus: .neverRecorded)

        #expect(ReviewGate.refusal(for: invoice) == "Waiting on this client's tax status.")
    }

    @Test("a discount larger than the invoice is named as what it is")
    func anoversizedDiscountRefuses() throws {
        let invoice = try Self.invoice(discountDollars: 10_000)

        #expect(ReviewGate.refusal(for: invoice) ==
                "The discount is larger than everything on this invoice.")
    }

    @Test("with both wrong it says the tax status, because that is the one Dan answers")
    func theorderIsWrittenDown() throws {
        // Both are real refusals and the control can say one. The tax status comes
        // first because answering it is a fact about the client that outlives this
        // invoice, while the discount is a number on this one.
        let invoice = try Self.invoice(taxStatus: .neverRecorded, discountDollars: 10_000)

        #expect(ReviewGate.refusal(for: invoice) == "Waiting on this client's tax status.")
    }

    @Test("every refusal the invoice can carry has a sentence, so none can be silent")
    func everyRefusalIsWorded() throws {
        // A vocabulary a lookup reads must be complete, or a new member takes the
        // default and reads as a deliberate silence (L113). This is what makes the
        // next refusal added to InvoiceRefusal fail here rather than ship mute.
        for refusal in InvoiceRefusal.allCases {
            #expect(ReviewGate.sentence(for: refusal).isEmpty == false,
                    "\(refusal) has no sentence")
            #expect(ReviewGate.order.contains(refusal),
                    "\(refusal) is not placed in the order a control says them")
        }
    }

    // MARK: staging

    private static func invoice(taxStatus: TaxStatus = .notExempt,
                                discountDollars: Int64? = nil) throws -> Invoice {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: "A Client", taxStatus: taxStatus)
        client.email = "booker@example.com"
        context.insert(client)
        let invoice = try InvoiceFixtures.invoice("Ordinary", in: context)
        invoice.client = client
        invoice.number = 1_123
        if let discountDollars {
            invoice.discount = Discount(dollars: Money(dollars: discountDollars))
        }
        try context.save()
        return invoice
    }
}
