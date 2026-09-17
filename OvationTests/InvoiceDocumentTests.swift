import Foundation
import SwiftData
import Testing

/// ovation#167, PRD 50 to 50f. WHAT THE INVOICE PDF SAYS, before anything is drawn.
///
/// THE EXPECTATION IS THE DESIGN'S OWN TEXT. `docs/design/invoice-pdf.expected.json`
/// is what the settled page draws for its seven fixture invoices, written by
/// `scripts/build-invoice-pdf-text.sh` from a rendering of `invoice-pdf.html`, and a
/// test asserting agreement with a design has to read the design (L638).
///
/// THE INVOICES ARE BUILT FROM THE SAME FILE. Each fixture carries the input the
/// design builds it from, and InvoiceFixtures builds it, the one builder this suite and
/// InvoicePDFRendererTests share, so no second copy of the fixtures can drift (L26).
/// What it asserts is that the app, given what the design was given, writes what the
/// design wrote.
struct InvoiceDocumentTests {

    // MARK: the design's invoices, from the one shared builder

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    // MARK: agreement with the design

    @Test("all seven design fixtures are read, so no comparison below runs over nothing")
    func theFixturesAreThere() throws {
        #expect(try InvoiceFixtures.expected().count == 7)
    }

    @Test("each fixture's page says what the settled design draws, section by section")
    func eachFixtureSaysWhatTheDesignDraws() throws {
        for fixture in try InvoiceFixtures.expected() {
            let context = try Self.store()
            let document = try InvoiceDocument(invoice: try InvoiceFixtures.invoice(from: fixture.input, in: context),
                                               footer: .fixed)
            let name = fixture.label
            #expect(document.amountDueLabel == fixture.head.label, "\(name): the amount due label")
            #expect(document.amountDue == fixture.head.amount, "\(name): the amount due")
            #expect(document.dueLine == fixture.head.due, "\(name): the due line")
            #expect(document.strip == fixture.strip, "\(name): the strip")
            #expect(document.title == fixture.title, "\(name): the title")
            #expect(document.columns == fixture.columns, "\(name): the columns")
            #expect(document.items == fixture.items, "\(name): the lines, cell by cell and in order")
            #expect(document.money == fixture.money, "\(name): the money rows, in order")
            #expect(document.foot.map(\.label) == fixture.foot.map(\.label), "\(name): the footer blocks")
            #expect(document.foot.map(\.lines) == fixture.foot.map(\.lines), "\(name): the footer text")
        }
    }

    // MARK: refusals, each by name (L11, L100)

    private static func ordinary(_ context: ModelContext) throws -> Invoice {
        try InvoiceFixtures.invoice("Ordinary", in: context)
    }

    private static func refusal(_ invoice: Invoice) -> InvoiceDocument.Refusal? {
        do {
            _ = try InvoiceDocument(invoice: invoice, footer: .fixed)
            return nil
        } catch let refusal as InvoiceDocument.Refusal {
            return refusal
        } catch {
            return nil
        }
    }

    @Test("an invoice with no number is refused, because the number is printed on what ships")
    func noNumberIsRefused() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.number = nil
        #expect(Self.refusal(invoice) == .noNumber)
    }

    @Test("an invoice with no date is refused rather than printed undated")
    func noInvoiceDateIsRefused() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.invoiceDate = nil
        #expect(Self.refusal(invoice) == .noInvoiceDate)
    }

    @Test("an invoice with no due date is refused, because the page leads with it")
    func noDueDateIsRefused() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.dueDate = nil
        #expect(Self.refusal(invoice) == .noDueDate)
    }

    @Test("an invoice with no client is refused, because Bill to would be empty")
    func noClientIsRefused() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.client = nil
        #expect(Self.refusal(invoice) == .noClient)
    }

    @Test("a discount larger than the subtotal is refused rather than printing a negative amount due")
    func anOversizedDiscountIsRefused() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.discount = Discount(dollars: Money(dollars: 400))
        #expect(Self.refusal(invoice) == .discountExceedsSubtotal)
    }

    /// Dan, 2026-09-14: the footer's terms count the days between THIS invoice's date
    /// and its due date, because PRD 7 lets a due date move per client or per invoice
    /// and a fixed "14 days" would then contradict the date at the top of the page.
    /// Every design fixture is due in 14, so the moved date is asserted here (L101).
    @Test("a due date moved to 30 days is what the terms say, beside the due date at the top")
    func movedTermsFollowTheDueDate() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.dueDate = try InvoiceFixtures.businessDate("November 24, 2026")
        let document = try InvoiceDocument(invoice: invoice, footer: .fixed)
        #expect(document.dueLine == "by November 24, 2026")
        let payment = try #require(document.foot.first { $0.label == "Payment" })
        #expect(payment.lines.contains("Payment due within 30 days of the invoice date."))
        #expect(!payment.lines.contains { $0.contains("14") }, "no line may still state the old term")
    }

    // MARK: what an unwritten footer line does to the page (ovation#319)

    /// THE PAGE IS STILL BUILT WHEN SOMETHING REQUIRED IS MISSING, and that is a
    /// decision rather than an oversight. Dan reviews this page immediately before
    /// sending, so a page that refused to draw would leave him unable to SEE what is
    /// wrong with it; `ReviewGate` is what stops the send. These cases hold the page
    /// to leaving a block off rather than drawing a heading over a gap.

    @Test("an unwritten note leaves its block off the page rather than drawing an empty heading")
    func anEmptyNoteLeavesItsBlockOff() throws {
        let invoice = try Self.ordinary(try Self.store())
        var footer = InvoiceFooter.fixed
        footer.note = ""
        let document = try InvoiceDocument(invoice: invoice, footer: footer)

        // The others are untouched, so this is one block being left off rather than
        // the foot collapsing (L104).
        #expect(document.foot.map(\.label) == ["Payment", "Contact"])
    }

    @Test("unwritten contact details leave their block off the page")
    func anEmptyContactLeavesItsBlockOff() throws {
        let invoice = try Self.ordinary(try Self.store())
        var footer = InvoiceFooter.fixed
        footer.contact = ""
        let document = try InvoiceDocument(invoice: invoice, footer: footer)

        #expect(document.foot.map(\.label) == ["Payment", "Note"])
    }

    /// THE TERMS KEEP THE PAYMENT BLOCK ALIVE. They belong to the invoice and are
    /// never blank, so an unwritten payment line shortens that block rather than
    /// removing it, and the client is still told when the money is due.
    @Test("an unwritten payment line shortens its block but leaves the terms saying when it is due")
    func anEmptyPaymentKeepsTheTerms() throws {
        let invoice = try Self.ordinary(try Self.store())
        var footer = InvoiceFooter.fixed
        footer.payment = ""
        let document = try InvoiceDocument(invoice: invoice, footer: footer)

        let payment = try #require(document.foot.first { $0.label == "Payment" })
        #expect(payment.lines == ["Payment due within 14 days of the invoice date."])
    }

    /// SPACE IS NOT TEXT, and the page and the refusal read it the same way through
    /// one predicate (L70). A line of spaces would otherwise draw a blank gap under
    /// a heading while the send was allowed.
    @Test("a footer line holding only spaces is left off, exactly as an empty one is")
    func whitespaceIsLeftOffToo() throws {
        let invoice = try Self.ordinary(try Self.store())
        var footer = InvoiceFooter.fixed
        footer.note = "   \n  "
        let document = try InvoiceDocument(invoice: invoice, footer: footer)

        #expect(document.foot.map(\.label) == ["Payment", "Contact"])
    }

    /// AND A WRITTEN FOOTER STILL DRAWS ALL THREE, so none of the cases above can be
    /// satisfied by the foot simply having gone missing (L159).
    @Test("a footer with all three written still draws all three blocks")
    func acompleteFooterDrawsEverything() throws {
        let invoice = try Self.ordinary(try Self.store())
        let document = try InvoiceDocument(invoice: invoice, footer: .fixed)

        #expect(document.foot.map(\.label) == ["Payment", "Note", "Contact"])
    }

    @Test("a due date before the invoice date is refused rather than printed as a negative term")
    func aDueDateBeforeTheInvoiceIsRefused() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.dueDate = try InvoiceFixtures.businessDate("October 24, 2026")
        #expect(Self.refusal(invoice) == .dueBeforeInvoiceDate)
    }

    /// A day key is stored beside its instant, and a store can hold one that is not a
    /// calendar day. Both places a date is written are asserted, because each reaches
    /// the refusal by its own route (L173).
    @Test("a stored date that is not a calendar day is refused, on the invoice or on a shoot")
    func anUnreadableDateIsRefused() throws {
        let nonsense = BusinessDate(storedInstant: Date(timeIntervalSince1970: 1_798_000_000),
                                    storedDayKey: "2026-13-40")

        let undated = try Self.ordinary(try Self.store())
        #expect(Self.refusal(undated) == nil, "the ordinary fixture is a page, so the refusal below is the date's")
        undated.invoiceDate = nonsense
        #expect(Self.refusal(undated) == .unreadableDate)

        let badShoot = try Self.ordinary(try Self.store())
        let shoot = try #require(badShoot.orderedShoots.first)
        shoot.when = .dayOnly(nonsense)
        #expect(Self.refusal(badShoot) == .unreadableDate)
    }

    // MARK: the discount's label

    /// PRD 5.4a: a discount is given as a percentage or an amount, and the page says
    /// which. The seven fixtures only reach a whole ten percent, so a share with a
    /// fraction, and an amount, are asserted here where nothing else would (L101).
    /// Labels only, so no rounding of the figures can move what is judged.
    @Test("a percentage discount names its share to the precision given, and an amount names none")
    func theDiscountLabelSaysWhatWasGiven() throws {
        for (discount, label) in [
            (Discount(percentBasisPoints: 1_000), "Discount (10%)"),
            (Discount(percentBasisPoints: 1_250), "Discount (12.5%)"),
            (Discount(percentBasisPoints: 3_333), "Discount (33.33%)"),
            (Discount(dollars: Money(dollars: 50)), "Discount"),
        ] {
            let invoice = try Self.ordinary(try Self.store())
            invoice.discount = try #require(discount)
            let document = try InvoiceDocument(invoice: invoice, footer: .fixed)
            #expect(document.money.contains { $0.first == label }, "expected a row labelled \(label)")
        }
    }

    // MARK: PRD 5b

    /// The warning about an unrecorded status is Dan's and never the client's: the
    /// PDF charges the tax and shows it like any other invoice, and says nothing
    /// about the status.
    @Test("a client whose tax status was never recorded is charged and shown the tax, and told nothing")
    func anUnrecordedStatusChargesTaxSilently() throws {
        let invoice = try Self.ordinary(try Self.store())
        invoice.client?.taxStatus = .neverRecorded
        let document = try InvoiceDocument(invoice: invoice, footer: .fixed)
        #expect(document.money.contains(["Sales tax (8.875%)", "$22.19"]))
        let everything = ([document.amountDueLabel, document.amountDue, document.dueLine, document.title]
            + document.strip.flatMap { $0 } + document.items.flatMap { $0 }
            + document.money.flatMap { $0 } + document.foot.flatMap { [$0.label] + $0.lines })
            .joined(separator: " ").lowercased()
        #expect(!everything.contains("status"))
        #expect(!everything.contains("recorded"))
        #expect(!everything.contains("exempt"))
    }
}
