import Foundation
import SwiftData
import Testing

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

        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) == nil)
    }

    @Test("a client whose tax status was never recorded is waiting on that")
    func anunrecordedTaxStatusRefuses() throws {
        // ovation#128: a missing status is not the same as not exempt. The tax is
        // charged AND the send is refused until it is answered.
        let invoice = try Self.invoice(taxStatus: .neverRecorded)

        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) == "Waiting on this client's tax status.")
    }

    @Test("a discount larger than the invoice is named as what it is")
    func anoversizedDiscountRefuses() throws {
        let invoice = try Self.invoice(discountDollars: 10_000)

        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) ==
                "The discount is larger than everything on this invoice.")
    }

    @Test("with both wrong it says the tax status, because that is the one Dan answers")
    func theorderIsWrittenDown() throws {
        // Both are real refusals and the control can say one. The tax status comes
        // first because answering it is a fact about the client that outlives this
        // invoice, while the discount is a number on this one.
        let invoice = try Self.invoice(taxStatus: .neverRecorded, discountDollars: 10_000)

        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) == "Waiting on this client's tax status.")
    }

    // MARK: what Settings stops (ovation#319)

    @Test("with no payment instructions in Settings, no invoice can be reviewed")
    func nopaymentInstructionsRefuses() throws {
        let invoice = try Self.invoice()
        var footer = InvoiceFooter.fixed
        footer.payment = ""

        #expect(ReviewGate.refusal(for: invoice, footer: footer) ==
                "Settings has no payment instructions, so no invoice can be sent.")
    }

    @Test("with no contact details in Settings, no invoice can be reviewed")
    func nocontactDetailsRefuses() throws {
        let invoice = try Self.invoice()
        var footer = InvoiceFooter.fixed
        footer.contact = ""

        #expect(ReviewGate.refusal(for: invoice, footer: footer) ==
                "Settings has no contact details, so no invoice can be sent.")
    }

    @Test("an empty note in Settings stops nothing, because the note is optional")
    func anemptyNoteDoesNotRefuse() throws {
        let invoice = try Self.invoice()
        var footer = InvoiceFooter.fixed
        footer.note = ""

        #expect(ReviewGate.refusal(for: invoice, footer: footer) == nil)
    }

    // THE ORDER IS THE DECISION, and this is the case that pins it. A settings
    // problem stops EVERY invoice and is fixed once, on another screen, so telling
    // Dan about this client's tax status while nothing can be sent at all would
    // send him to the wrong place (L111).
    @Test("a settings problem is said before anything about this invoice")
    func settingsComesBeforeTheInvoice() throws {
        let invoice = try Self.invoice(taxStatus: .neverRecorded, discountDollars: 10_000)
        var footer = InvoiceFooter.fixed
        footer.payment = ""

        #expect(ReviewGate.refusal(for: invoice, footer: footer) ==
                "Settings has no payment instructions, so no invoice can be sent.")
    }

    // AND THE INVOICE IS STILL HEARD once Settings is complete, so the case above
    // cannot be satisfied by a gate that simply always answers about the footer
    // (L159).
    @Test("and once Settings is complete the invoice's own reason is heard again")
    func theinvoiceIsHeardOnceSettingsIsComplete() throws {
        let invoice = try Self.invoice(taxStatus: .neverRecorded)

        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) ==
                "Waiting on this client's tax status.")
    }

    // MARK: an invoice that comes to less than nothing (ovation#136, PRD 5.4c)

    @Test("an invoice whose total is below zero is refused, and the credit is named")
    func anegativeTotalRefuses() throws {
        let invoice = try Self.invoice(creditHours: 1, lineDollars: 100)

        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) ==
                "The credit is larger than everything charged, so this invoice comes to less than nothing.")
    }

    @Test("and an invoice coming to exactly zero is reviewed like any other")
    func azeroTotalIsReviewedLikeAnyOther() throws {
        // The positive control PRD 5.1b requires: a comped shoot is drafted,
        // numbered and sent at zero, and no guard may refuse one (L159).
        let invoice = try Self.invoice(creditHours: 1, lineDollars: 250)

        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) == nil)
    }

    @Test("an oversized discount is still said as the discount, not as a negative total")
    func thediscountKeepsItsOwnSentence() throws {
        // Both refusals are present, and the order decides. The discount names the
        // number somebody typed wrong, and the negative total sentence is left for
        // the case where the discount is NOT the cause, which is what lets that
        // sentence name the credit at all (L111).
        let invoice = try Self.invoice(discountDollars: 10_000)

        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) ==
                "The discount is larger than everything on this invoice.")
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
                                discountDollars: Int64? = nil,
                                creditHours: Int64? = nil,
                                lineDollars: Int64? = nil) throws -> Invoice {
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
        // The lines are REPLACED rather than added to, because the fixture carries
        // its own and a credit sized against those would be a different case from
        // the one the test names.
        if let lineDollars {
            for item in invoice.lineItems { context.delete(item) }
            invoice.lineItems = []
            invoice.add(LineItem.flat(Money(dollars: lineDollars), describedAs: "Photography"))
        }
        // THE SHOOTS ARE TIMED, because every case in this suite is about a refusal
        // that is NOT the times, and an untimed shoot would answer first and make
        // each of them assert the wrong sentence (ovation#117, PRD 51b). The
        // fixture's own line prices one hour, so 19:00 to 20:00 changes no figure
        // in it.
        for shoot in invoice.shoots {
            shoot.shotFrom = ClockTime("19:00")
            shoot.shotUntil = ClockTime("20:00")
        }
        if let creditHours {
            invoice.referralCredit = ReferralCredit(hours: Hours(whole: creditHours),
                                                    at: invoice.hourlyRate, earnedFrom: nil)
        }
        try context.save()
        return invoice
    }
}
