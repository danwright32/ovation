import Foundation
import SwiftData
import Testing

/// ovation#457, PRD 5.4a. What the Edit menu offers about the invoice on screen.
///
/// TWO RECORDED DECISIONS MEET HERE AND NEITHER IS OVERRULED. `docs/design/invoice.html`
/// round 5 puts the rare actions in this menu and draws "Add a discount" only
/// while there is no discount, because once there is one the row carries its own
/// controls and a second way to change it would be the same action twice, with
/// the menu copy further from the thing it acts on (L605).
///
/// `OvationApp`'s own rule for this menu is the opposite shape and is written
/// into it: an entry "IS NEVER HIDDEN, only disabled with a reason said out
/// loud, because a control that is not there cannot be asked why" (L49, L109).
///
/// So the entry stays, and when there is already a discount it is disabled and
/// SAYS WHERE THE DISCOUNT IS CHANGED. That keeps the design's concern, which is
/// that there is one place to edit a discount, and the app's, which is that a
/// menu never goes quiet (L542).
@MainActor
struct InvoiceEditCommandTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    private static func invoice(sent: Bool = false, discounted: Bool = false) throws -> Invoice {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography,
                              invoiceDate: BusinessCalendar.day(forKey: "2026-11-12"),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        invoice.add(LineItem.flat(Money(dollars: 400), describedAs: "Photography"))
        if discounted { invoice.discount = Discount(percentBasisPoints: 1_000) }
        if sent {
            invoice.number = 1_123
            invoice.sentStatus = .sent(route: .ovationSentIt, at: Self.noon)
        }
        context.insert(invoice)
        return invoice
    }

    // MARK: when it can be pressed

    @Test("an ordinary draft with no discount can have one added")
    func anordinaryDraftCanHaveOne() throws {
        let open = InvoiceEditCommand.Open(try Self.invoice())

        #expect(InvoiceEditCommand.whyADiscountCannotBeAdded(open) == nil)
    }

    // MARK: when it cannot, and what it says

    /// WITH NO INVOICE OPEN THE ENTRY IS STILL THERE. It is the state the menu is
    /// in most of the time, and an entry that appears only once you are already
    /// somewhere teaches nobody that it exists (L49).
    @Test("with no invoice open it says so rather than going away")
    func withnoinvoiceOpenItSaysSo() {
        let why = InvoiceEditCommand.whyADiscountCannotBeAdded(nil)

        #expect(why == "No invoice is open.")
    }

    /// AND IT NAMES WHERE THE DISCOUNT IS CHANGED, rather than only refusing. An
    /// instruction must name an action that changes the state you are stuck in,
    /// in the vocabulary of the place you will act (L111, L399).
    @Test("an invoice that already has one says where to change it")
    func analreadyDiscountedInvoiceSaysWhereToChangeIt() throws {
        let open = InvoiceEditCommand.Open(try Self.invoice(discounted: true))

        let why = InvoiceEditCommand.whyADiscountCannotBeAdded(open)

        #expect(why == "This invoice already has a discount, which is changed on the invoice.")
    }

    /// A SENT INVOICE'S FIGURES ARE WHAT THE CLIENT WAS TOLD, and the menu says
    /// the same thing the writer would, rather than a second wording of it
    /// (L118). `InvoiceDiscountWriter` refuses the same state, because a screen
    /// gating a write is not the write being guarded (L196).
    @Test("a sent invoice says what the writer would say")
    func asentInvoiceSaysWhatTheWriterSays() throws {
        let open = InvoiceEditCommand.Open(try Self.invoice(sent: true))

        let why = InvoiceEditCommand.whyADiscountCannotBeAdded(open)

        #expect(why == InvoiceDiscountRefusal.invoiceWasSent.sentence)
    }

    /// THE ORDER IS WRITTEN AND IT PUTS THE INVOICE'S STATE FIRST. A sent invoice
    /// carrying a discount cannot have one added for the stronger reason, and
    /// saying it already has one would send Dan to a control that is not offered
    /// on a sent invoice either (L111).
    @Test("a sent invoice that carries a discount is refused for being sent")
    func asentdiscountedInvoiceIsRefusedForBeingSent() throws {
        let open = InvoiceEditCommand.Open(try Self.invoice(sent: true, discounted: true))

        #expect(InvoiceEditCommand.whyADiscountCannotBeAdded(open)
                == InvoiceDiscountRefusal.invoiceWasSent.sentence)
    }

    // MARK: what it adds

    /// TEN PERCENT, because it is the commonest of the five discounts in the
    /// whole of Dan's history, which is round 5's own measurement.
    @Test("what it adds is a tenth off")
    func whatitaddsIsATenth() {
        #expect(InvoiceEditCommand.whatItAdds.percentBasisPoints == 1_000)
    }

    @Test("and the entry is called what the design record calls it")
    func theentryIsCalledWhatTheRecordCallsIt() {
        #expect(InvoiceEditCommand.addDiscountTitle == "Add a discount")
    }
}
