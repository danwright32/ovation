import Foundation
import SwiftData
import Testing
@testable import Ovation

/// ovation#60. The invoice and what hangs off it, and the arithmetic that decides
/// what a client is asked to pay.
struct InvoiceTests {

    // MARK: a store to put them in

    /// One container per test, in memory. Nothing here can reach the live store:
    /// the resolver on the isolation floor already refuses under a disposable
    /// launch, and this never asks it for a path at all.
    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    /// A shoot on a fixed evening, so nothing here depends on the clock.
    /// 2026-11-12, 20:00 to 22:30 America/New_York, two and a half hours.
    private static let shootStart = Date(timeIntervalSince1970: 1_794_531_600)
    private static let shootEnd = Date(timeIntervalSince1970: 1_794_540_600)

    private static func client(_ context: ModelContext, tax: TaxStatus = .notExempt) -> Client {
        let client = Client(name: "A company", taxStatus: tax)
        context.insert(client)
        return client
    }

    private static func invoice(
        _ context: ModelContext, for client: Client, dated: Date = shootStart
    ) -> Invoice {
        let invoice = Invoice(
            client: client,
            kind: .fromABooking,
            invoiceDate: .stamping(dated),
            hourlyRate: Money(dollars: 250),
            taxRate: .newYorkCity
        )
        context.insert(invoice)
        return invoice
    }

    // MARK: what a line costs

    @Test("an hourly line is the rate frozen on the invoice times the hours shot")
    func anHourlyLineIsRateTimesHours() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        let when = try #require(ShootWhen(startsAt: Self.shootStart, endsAt: Self.shootEnd))
        #expect(when.billableHours == Hours(tenths: 25))

        invoice.add(LineItem.hourly(hours: when.billableHours!, at: invoice.hourlyRate,
                                    describedAs: "Photography"))
        #expect(invoice.subtotal == Money(dollars: 625))
    }

    @Test("a flat line is its own amount")
    func flatLinesCarryTheirAmount() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        invoice.add(LineItem.flat(Money(dollars: 100), describedAs: "Rush turnaround"))
        invoice.add(LineItem.flat(Money(dollars: 75), describedAs: "Preview images"))
        #expect(invoice.subtotal == Money(dollars: 175))
    }

    // MARK: the referral credit, which is NOT a line (ovation#126)

    @Test("a referral credit is not a line item, and the lines do not know about it")
    func aCreditIsNotALine() throws {
        // Round 6 of ovation#111, settled with Dan on 2026-09-07: the credit
        // comes OUT of the line items and sits in its own block between the lines
        // and the subtotal. He chose it having been shown that it contradicts
        // PRD 5.8 and the shipped model.
        let context = try Self.store()
        let earnedFrom = Client(name: "Yarrow Street Collective", taxStatus: .notExempt)
        context.insert(earnedFrom)
        let invoice = Self.invoice(context, for: Self.client(context))
        invoice.add(LineItem.hourly(hours: Hours(whole: 4), at: invoice.hourlyRate,
                                    describedAs: "Photography"))
        invoice.referralCredit = ReferralCredit(hours: Hours(whole: 1),
                                                at: invoice.hourlyRate, earnedFrom: earnedFrom)

        #expect(invoice.orderedLineItems.count == 1, "the credit added no line")
        #expect(invoice.referralCreditAmount == Money(dollars: 250))
    }

    @Test("the credit still reduces the subtotal, which is the arithmetic that must not change")
    func aCreditIsStillInsideTheSubtotal() throws {
        // PRD 5.4b's conclusion survives round 6 and its reason does not: the
        // credit is still INSIDE the subtotal, it is simply not a line. A
        // discount is below the subtotal and the two net to the same tax, which
        // is exactly why they are easy to merge and must not be.
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        invoice.add(LineItem.flat(Money(dollars: 1_000), describedAs: "Photography"))
        invoice.referralCredit = ReferralCredit(hours: Hours(whole: 1),
                                                at: invoice.hourlyRate, earnedFrom: nil)

        #expect(invoice.subtotal == Money(dollars: 750), "$1,000 less the $250 credit")
        #expect(invoice.taxableAmount == Money(dollars: 750), "and no discount below it")
    }

    @Test("a credit and a discount are kept apart, and the discount applies to what is LEFT")
    func aCreditAndADiscountStayApart() throws {
        // The case PRD 5.4b exists to protect. Merging the two nets to the same
        // tax on this invoice and gives the export a different answer to "how
        // much was given away in a year", which is the question it has to answer
        // with credits and discounts kept apart.
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        invoice.add(LineItem.flat(Money(dollars: 1_000), describedAs: "Photography"))
        invoice.referralCredit = ReferralCredit(hours: Hours(whole: 1),
                                                at: invoice.hourlyRate, earnedFrom: nil)
        invoice.discount = Discount(percentBasisPoints: 1_000)

        #expect(invoice.subtotal == Money(dollars: 750))
        #expect(invoice.referralCreditAmount == Money(dollars: 250))
        #expect(invoice.discountAmount == Money(cents: 7_500), "10% of what is left, not of $1,000")
        #expect(invoice.taxableAmount == Money(cents: 67_500))
    }

    @Test("a credit names the client it was earned on, frozen, because the invoice prints it")
    func aCreditNamesWhereItCameFrom() throws {
        // Frozen for the same reason the rate is: a client renamed in 2029 must
        // not rewrite an invoice sent in 2026. The id keeps the link for the
        // ledger and the export; the name is what was printed.
        let context = try Self.store()
        let earnedFrom = Client(name: "Yarrow Street Collective", taxStatus: .notExempt)
        context.insert(earnedFrom)
        let invoice = Self.invoice(context, for: Self.client(context))
        invoice.referralCredit = ReferralCredit(hours: Hours(whole: 1),
                                                at: invoice.hourlyRate, earnedFrom: earnedFrom)
        try context.save()

        earnedFrom.name = "Renamed since"
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.id == invoice.id })
        #expect(read.referralCredit?.earnedFromClientName == "Yarrow Street Collective")
        #expect(read.referralCredit?.earnedFromClientID == earnedFrom.id)
        #expect(read.referralCredit?.hours == Hours(whole: 1))
    }

    @Test("a credit of nothing or less cannot be constructed, so no invoice can carry one")
    func aCreditMustBeWorthSomething() throws {
        // A credit of zero hours records no decision, and a negative one is a
        // CHARGE written the wrong way round, which would read on the invoice as
        // a credit while increasing what is owed.
        #expect(ReferralCredit(hours: Hours.zero, at: Money(dollars: 250), earnedFrom: nil) == nil)
        #expect(ReferralCredit(hours: Hours(tenths: -5), at: Money(dollars: 250),
                               earnedFrom: nil) == nil)
        #expect(ReferralCredit(hours: Hours(tenths: 5), at: Money(dollars: 250),
                               earnedFrom: nil) != nil)
    }

    @Test("line items keep the order they were given, which is declared and not inherited")
    func lineItemsKeepTheirOrder() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        invoice.add(LineItem.flat(Money(dollars: 10), describedAs: "first"))
        invoice.add(LineItem.flat(Money(dollars: 20), describedAs: "second"))
        invoice.add(LineItem.flat(Money(dollars: 30), describedAs: "third"))
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<Invoice>()).first)
        #expect(read.orderedLineItems.map(\.summary) == ["first", "second", "third"])
    }

    // MARK: the discount, and the tax base it changes

    @Test("the tax is charged on the subtotal AFTER the discount, not before it")
    func taxIsChargedOnWhatIsLeft() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        invoice.add(LineItem.flat(Money(dollars: 1_000), describedAs: "Photography"))
        invoice.discount = Discount(dollars: Money(dollars: 200))

        #expect(invoice.subtotal == Money(dollars: 1_000))
        #expect(invoice.discountAmount == Money(dollars: 200))
        #expect(invoice.taxableAmount == Money(dollars: 800))
        // 8.875% of $800.00 is $71.00 exactly.
        #expect(invoice.tax == Money(dollars: 71))
        #expect(invoice.total == Money(dollars: 871))
    }

    @Test("with no discount the taxable amount is the subtotal itself")
    func noDiscountLeavesTheSubtotal() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        invoice.add(LineItem.flat(Money(dollars: 1_000), describedAs: "Photography"))
        #expect(invoice.discountAmount == Money.zero)
        #expect(invoice.taxableAmount == invoice.subtotal)
    }

    @Test("a comped shoot invoiced at nothing is legitimate and nothing refuses it")
    func aZeroInvoiceIsLegitimate() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        invoice.add(LineItem.flat(Money(dollars: 625), describedAs: "Photography"))
        invoice.discount = Discount(percentBasisPoints: 10_000)

        #expect(invoice.total == Money.zero)
        #expect(invoice.tax == Money.zero, "there is nothing left to tax")
        #expect(invoice.refusals.isEmpty, "a zero total is not a fault")
    }

    @Test("a fixed discount larger than the subtotal is refused by name rather than clamped")
    func anOversizedDiscountIsRefusedByName() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        invoice.add(LineItem.flat(Money(dollars: 100), describedAs: "Photography"))
        invoice.discount = Discount(dollars: Money(dollars: 150))

        #expect(invoice.refusals.contains(.discountExceedsSubtotal))
    }

    // MARK: tax status, where a missing answer is not the same as no

    @Test("an exempt client is charged no tax at all")
    func anExemptClientIsNotTaxed() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context, tax: .exempt))
        invoice.add(LineItem.flat(Money(dollars: 1_000), describedAs: "Photography"))
        #expect(invoice.tax == Money.zero)
        #expect(invoice.total == Money(dollars: 1_000))
    }

    @Test("a client whose status was never recorded IS taxed, and the invoice says so")
    func anUnrecordedStatusIsTaxedAndFlagged() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context, tax: .neverRecorded))
        invoice.add(LineItem.flat(Money(dollars: 1_000), describedAs: "Photography"))
        #expect(invoice.tax == Money(cents: 8_875), "a missing status is not the same as exempt")
        #expect(invoice.warnings.contains(.taxStatusNeverRecorded))
    }

    @Test("a client known not to be exempt is taxed with nothing to warn about")
    func aKnownStatusWarnsAboutNothing() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context, tax: .notExempt))
        invoice.add(LineItem.flat(Money(dollars: 1_000), describedAs: "Photography"))
        #expect(invoice.warnings.isEmpty)
    }

    // MARK: the rates the invoice carries rather than reads

    @Test("the rate and the tax rate are frozen onto the invoice at creation")
    func ratesAreFrozenOntoTheInvoice() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<Invoice>()).first)
        #expect(read.hourlyRate == Money(dollars: 250))
        #expect(read.taxRate == TaxRate.newYorkCity)
    }

    // MARK: the parts and the total (PRD 5.42)

    @Test("no set of lines can make the total disagree with its own parts",
          arguments: [
            [0], [1_00], [-1_00], [1, 2, 3], [99_99, 1], [250_00, 100_00, -250_00],
            [33_33, 33_33, 33_34], [1_000_000_00], [-1, -1, -1], [7, 0, -7],
          ])
    func thePartsAlwaysMakeTheTotal(cents: [Int64]) throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        for (index, amount) in cents.enumerated() {
            invoice.add(LineItem.flat(Money(cents: amount), describedAs: "line \(index)"))
        }
        invoice.discount = Discount(percentBasisPoints: 1_000)
        invoice.referralCredit = ReferralCredit(hours: Hours(whole: 1),
                                                at: invoice.hourlyRate, earnedFrom: nil)

        // THE PARTS NOW INCLUDE THE CREDIT, which is the whole of ovation#126:
        // it left the line items and stayed inside the subtotal, so a sum over
        // the lines alone is no longer the subtotal and PRD 5.42 is about the
        // composed number rather than about the lines.
        let parts = Money.sum(of: invoice.orderedLineItems.map(\.amount))
        #expect(invoice.subtotal == parts - invoice.referralCreditAmount)
        #expect(invoice.total == invoice.taxableAmount + invoice.tax)
        #expect(invoice.taxableAmount == invoice.subtotal - invoice.discountAmount)
    }

    // MARK: shoots, and the duration that cannot be priced

    @Test("a shoot carries its venue and its two real instants, and any of them can be absent")
    func aShootCarriesWhatTheHandoffActuallyHas() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        let timed = Shoot(name: "Autumn concert",
                          when: ShootWhen(startsAt: Self.shootStart, endsAt: Self.shootEnd),
                          venue: nil)
        invoice.add(timed)
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<Invoice>()).first)
        let shoot = try #require(read.orderedShoots.first)
        #expect(shoot.name == "Autumn concert")
        #expect(shoot.venue == nil, "the handoff record proves a venue is sometimes absent")
        #expect(shoot.when?.billableHours == Hours(tenths: 25))
        #expect(shoot.day?.dayKey == BusinessCalendar.dayKey(for: Self.shootStart))
    }

    @Test("a duration of nothing or less is refused, so it can never be priced")
    func anImpossibleDurationIsRefused() {
        #expect(ShootWhen(startsAt: Self.shootStart, endsAt: Self.shootStart) == nil)
        #expect(ShootWhen(startsAt: Self.shootEnd, endsAt: Self.shootStart) == nil)
    }

    @Test("an invoice can cover several shoots, which is what combining drafts produces")
    func anInvoiceCanCoverSeveralShoots() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        invoice.add(Shoot(name: "Wednesday rehearsal", when: nil, venue: "A hall"))
        invoice.add(Shoot(name: "Saturday concert", when: nil, venue: "A hall"))
        #expect(invoice.orderedShoots.count == 2)
    }

    // MARK: a draft, and the number it does not have

    @Test("a draft carries no invoice number, so combining drafts burns none from the sequence")
    func aDraftHasNoNumber() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        #expect(invoice.number == nil)
        #expect(invoice.sentStatus == .notSent)
        #expect(invoice.closure == nil)
    }

    // MARK: identity, and the external keys that are never it

    @Test("two invoices for the same booking are two rows, not one replacing the other")
    func anExternalKeyNeverBecomesTheIdentity() throws {
        let context = try Self.store()
        let client = Self.client(context)
        let first = Self.invoice(context, for: client)
        let second = Self.invoice(context, for: client)
        first.bookingKey = "booking-9f2a"
        second.bookingKey = "booking-9f2a"
        try context.save()

        let all = try context.fetch(FetchDescriptor<Invoice>())
        #expect(all.count == 2, "the second did not land on the first by construction")
        #expect(Set(all.map(\.id)).count == 2, "and they have their own identities")
        #expect(all.filter { $0.bookingKey == "booking-9f2a" }.count == 2,
                "so a lookup can SEE both and refuse, rather than a row being gone")
    }

    // MARK: everything survives the round trip

    @Test("an invoice reads back with its discount, its send and its shoots intact")
    func anInvoiceRoundTrips() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, for: Self.client(context))
        invoice.discount = Discount(percentBasisPoints: 1_250)
        invoice.sentStatus = .sent(route: .foundInTheMailbox, at: Self.shootEnd)
        invoice.number = 1_123
        invoice.add(Shoot(name: "Autumn concert",
                          when: ShootWhen(startsAt: Self.shootStart, endsAt: Self.shootEnd),
                          venue: "A hall"))
        invoice.add(LineItem.flat(Money(dollars: 625), describedAs: "Photography"))
        try context.save()

        let read = try #require(try ModelContext(context.container)
            .fetch(FetchDescriptor<Invoice>()).first)
        #expect(read.number == 1_123)
        #expect(read.discount == Discount(percentBasisPoints: 1_250))
        #expect(read.sentStatus.route == .foundInTheMailbox)
        #expect(read.invoiceDate?.dayKey == BusinessCalendar.dayKey(for: Self.shootStart))
        #expect(read.orderedShoots.first?.venue == "A hall")
        #expect(read.subtotal == Money(dollars: 625))
    }
}
