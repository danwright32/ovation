import Foundation
import SwiftData
import Testing

/// ovation#457, PRD 5.4a. What the Edit menu offers about the invoice on screen.
///
/// THE ENTRY IS DRAWN ONLY WHILE THERE IS NO DISCOUNT, which is
/// `docs/design/invoice.html` round 5 and was decided by Dan on 2026-09-23
/// (ovation#495): "The Edit menu draws `Add a discount` only while there is no
/// discount (hidden, not disabled, where one exists)." Once there is one the
/// row carries its own controls, and a second way to change it would be the
/// same action twice, with the menu copy further from the thing it acts on
/// (L605).
///
/// Where there is no discount and it still cannot be added, it stays and is
/// disabled with its reason said out loud, which is the menu's own rule for
/// every other entry (L49, L109).
@MainActor
struct InvoiceEditCommandTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    private static func invoice(sent: Bool = false, discounted: Bool = false,
                                credited: Bool = false, banked: Hours = .zero,
                                charging: Money = Money(dollars: 400)) throws -> Invoice {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography,
                              invoiceDate: BusinessCalendar.day(forKey: "2026-11-12"),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        if charging > .zero {
            invoice.add(LineItem.flat(charging, describedAs: "Photography"))
        }
        if banked > .zero {
            let entry = ReferralLedgerEntry(
                client: client, hours: banked,
                occurredOn: try #require(BusinessCalendar.day(forKey: "2026-10-01")),
                earnedFromBookingKey: "cedar-hill-2026-10-01", note: nil)
            context.insert(entry)
        }
        if credited {
            invoice.referralCredit = ReferralCredit(
                hours: Hours(whole: 1), at: Money(dollars: 250), earnedFrom: nil)
        }
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

    // MARK: where it is not drawn at all (ovation#495)

    @Test("an invoice with no discount is offered the entry")
    func anundiscountedInvoiceIsOfferedTheEntry() throws {
        let open = InvoiceEditCommand.Open(try Self.invoice())

        #expect(InvoiceEditCommand.offersToAddADiscount(open))
    }

    /// WITH NO INVOICE OPEN IT IS STILL DRAWN, disabled and saying why, because
    /// there is no discount for it to defer to and the record draws it whenever
    /// there is none.
    @Test("with no invoice open the entry is still drawn")
    func withnoinvoiceOpenTheEntryIsDrawn() {
        #expect(InvoiceEditCommand.offersToAddADiscount(nil))
    }

    /// HIDDEN, NOT DISABLED, where one exists: Dan's decision on ovation#495,
    /// following the design record's `if (!DISCOUNT)`.
    @Test("an invoice that already has a discount is not offered the entry")
    func analreadyDiscountedInvoiceIsNotOfferedTheEntry() throws {
        let open = InvoiceEditCommand.Open(try Self.invoice(discounted: true))

        #expect(InvoiceEditCommand.offersToAddADiscount(open) == false)
    }

    /// THE RECORD ASKS ONLY WHETHER THERE IS A DISCOUNT, so a sent invoice
    /// carrying one hides the entry as well, rather than drawing it to refuse.
    @Test("a sent invoice that carries a discount is not offered the entry either")
    func asentdiscountedInvoiceIsNotOfferedTheEntry() throws {
        let open = InvoiceEditCommand.Open(try Self.invoice(sent: true, discounted: true))

        #expect(InvoiceEditCommand.offersToAddADiscount(open) == false)
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

    // MARK: the referral credit, which has no controls of its own anywhere

    /// PRD 5.51e: the credit "keeps its menu entry, having no controls of its own
    /// anywhere", which is what makes this entry the whole of its interface and
    /// why its word changes with the state instead of a second entry appearing.
    @Test("the entry offers to apply a credit while the invoice has none")
    func theentryOffersToApply() throws {
        let open = InvoiceEditCommand.Open(try Self.invoice(banked: Hours(whole: 2)))

        #expect(InvoiceEditCommand.referralCreditTitle(open) == "Apply a referral credit")
        #expect(InvoiceEditCommand.whyTheReferralCreditCannotChange(open) == nil)
    }

    @Test("and offers to remove the one that is there")
    func andoffersToRemove() throws {
        let open = InvoiceEditCommand.Open(try Self.invoice(credited: true))

        #expect(InvoiceEditCommand.referralCreditTitle(open) == "Remove the referral credit")
        #expect(InvoiceEditCommand.whyTheReferralCreditCannotChange(open) == nil)
    }

    /// A CREDIT THAT IS ON THE INVOICE CAN ALWAYS COME OFF, whatever the balance
    /// or the charges now say. Those two decide whether one can be SPENT, and a
    /// removal spends nothing: refusing it would strand the credit on the invoice
    /// the moment its last line was deleted.
    @Test("removing is offered even when nothing could be spent now")
    func removingIsOfferedAnyway() throws {
        let open = InvoiceEditCommand.Open(
            try Self.invoice(credited: true, banked: .zero, charging: .zero))

        #expect(InvoiceEditCommand.referralCreditTitle(open) == "Remove the referral credit")
        #expect(InvoiceEditCommand.whyTheReferralCreditCannotChange(open) == nil)
    }

    @Test("with no invoice open the credit entry says so rather than going away")
    func withnoinvoiceOpenTheCreditEntrySaysSo() {
        #expect(InvoiceEditCommand.referralCreditTitle(nil) == "Apply a referral credit")
        #expect(InvoiceEditCommand.whyTheReferralCreditCannotChange(nil) == "No invoice is open.")
    }

    /// SAID IN THE WRITER'S OWN WORDS, never a second wording of one fact (L118).
    @Test("a client with nothing banked is said in the writer's words")
    func aclientWithNothingBankedIsSaidInTheWritersWords() throws {
        let open = InvoiceEditCommand.Open(try Self.invoice(banked: .zero))

        #expect(InvoiceEditCommand.whyTheReferralCreditCannotChange(open)
                == InvoiceReferralCreditRefusal.noCreditToSpend.sentence)
    }

    @Test("an invoice charging nothing is said in the writer's words too")
    func aninvoiceChargingNothingIsSaidInTheWritersWords() throws {
        let open = InvoiceEditCommand.Open(
            try Self.invoice(banked: Hours(whole: 2), charging: .zero))

        #expect(InvoiceEditCommand.whyTheReferralCreditCannotChange(open)
                == InvoiceReferralCreditRefusal.nothingIsBeingCharged.sentence)
    }

    /// THE ORDER IS WRITTEN, AND THE BALANCE COMES FIRST. With neither a balance
    /// nor a charge, naming the charge would send Dan to add a line and leave him
    /// exactly as stuck, because the client still has nothing to spend (L111).
    @Test("with neither a balance nor a charge, the balance is what it names")
    func withneitherTheBalanceIsNamed() throws {
        let open = InvoiceEditCommand.Open(try Self.invoice(banked: .zero, charging: .zero))

        #expect(InvoiceEditCommand.whyTheReferralCreditCannotChange(open)
                == InvoiceReferralCreditRefusal.noCreditToSpend.sentence)
    }

    @Test("a sent invoice says what the credit writer would say")
    func asentInvoiceSaysWhatTheCreditWriterSays() throws {
        let open = InvoiceEditCommand.Open(
            try Self.invoice(sent: true, credited: true, banked: Hours(whole: 2)))

        #expect(InvoiceEditCommand.whyTheReferralCreditCannotChange(open)
                == InvoiceReferralCreditRefusal.invoiceWasSent.sentence)
    }
}
