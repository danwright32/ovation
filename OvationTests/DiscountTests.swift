import Foundation
import Testing

/// ovation#60. A discount is ONE value with two forms, and it is taken off the
/// pre tax subtotal so the tax is charged on what is left (PRD 5.4a).
struct DiscountTests {

    // MARK: the two forms

    @Test("a discount in dollars takes exactly that amount off")
    func dollarsTakeTheirAmount() throws {
        let discount = try #require(Discount(dollars: Money(dollars: 50)))
        #expect(discount.amount(on: Money(dollars: 250)) == Money(dollars: 50))
    }

    @Test("a discount in percent is a share of the PRE TAX subtotal, not of the total")
    func percentIsAShareOfTheSubtotal() throws {
        let tenPercent = try #require(Discount(percentBasisPoints: 1_000))
        #expect(tenPercent.amount(on: Money(dollars: 250)) == Money(dollars: 25))
    }

    @Test("a fraction of a cent goes through the one rounding rule, half away from zero")
    func fractionsRoundHalfAwayFromZero() throws {
        let third = try #require(Discount(percentBasisPoints: 3_333))
        // 999 cents at 33.33% is 332.967 cents.
        #expect(third.amount(on: Money(cents: 999)) == Money(cents: 333))
        // And the same size the other way, because a credit line can carry a
        // subtotal below zero and a discount that rounded differently there
        // would not reverse the charge it was taken against.
        #expect(third.amount(on: Money(cents: -999)) == Money(cents: -333))
    }

    // MARK: what it refuses to be

    @Test("a discount below zero is refused, because that is a surcharge and there is no such thing")
    func negativeDiscountsAreRefused() {
        #expect(Discount(dollars: Money(cents: -1)) == nil)
        #expect(Discount(percentBasisPoints: -1) == nil)
    }

    @Test("everything from nothing off to the whole subtotal is allowed, a comped shoot included")
    func theWholeRangeIsAllowed() {
        #expect(Discount(percentBasisPoints: 0) != nil)
        #expect(Discount(percentBasisPoints: 10_000) != nil)
        #expect(Discount(percentBasisPoints: 10_001) == nil, "over the whole subtotal is nonsense")
    }

    @Test("a hundred percent takes the whole subtotal, which is a legitimate zero invoice")
    func aFullDiscountLeavesNothing() throws {
        let everything = try #require(Discount(percentBasisPoints: 10_000))
        #expect(everything.amount(on: Money(dollars: 250)) == Money(dollars: 250))
    }

    // MARK: the part a percentage cannot know at construction

    @Test("a fixed discount larger than the subtotal is reported rather than silently clamped")
    func anOversizedDiscountIsReported() throws {
        let fifty = try #require(Discount(dollars: Money(dollars: 50)))
        #expect(fifty.exceeds(Money(dollars: 40)))
        #expect(!fifty.exceeds(Money(dollars: 50)), "equal is not over, it is a zero invoice")
        #expect(!fifty.exceeds(Money(dollars: 60)))
    }

    @Test("a percentage can never exceed the subtotal it is a share of")
    func aPercentageNeverExceeds() throws {
        let everything = try #require(Discount(percentBasisPoints: 10_000))
        #expect(!everything.exceeds(Money(dollars: 250)))
        #expect(!everything.exceeds(Money.zero))
    }

    // MARK: the pairing the type exists to hold

    @Test("the two forms are distinguishable, so fifty dollars is never read as fifty percent")
    func theFormsStayApart() throws {
        let dollars = try #require(Discount(dollars: Money(dollars: 50)))
        let percent = try #require(Discount(percentBasisPoints: 5_000))
        #expect(dollars != percent)
        #expect(dollars.amount(on: Money(dollars: 250)) != percent.amount(on: Money(dollars: 250)))
    }

    // MARK: reading a discount back (ovation#457)

    /// A DISCOUNT IS READ BACK BY THE TWO ACCESSORS, one per form, so a control
    /// that has to show what was typed asks for it by name. Recovering a fixed
    /// amount by pricing the discount against a subtotal of nothing gives the
    /// right answer and asks the wrong question, and it would go on giving it
    /// until somebody decided a discount should clamp (L176, L263).
    @Test("a fixed amount is read back as the amount it is")
    func afixedAmountIsReadBack() throws {
        let fifty = try #require(Discount(dollars: Money(dollars: 50)))

        #expect(fifty.dollarsOff == Money(dollars: 50))
        #expect(fifty.percentBasisPoints == nil)
    }

    @Test("and a share has no amount of its own, because it has no meaning without one")
    func ashareHasNoAmountOfItsOwn() throws {
        let tenth = try #require(Discount(percentBasisPoints: 1_000))

        #expect(tenth.dollarsOff == nil)
        #expect(tenth.percentBasisPoints == 1_000)
    }

    /// EVERY DISCOUNT IS ONE FORM OR THE OTHER, never both and never neither,
    /// which is what the private form guarantees and what a reader of the two
    /// accessors is entitled to rely on (L517).
    @Test("every discount answers exactly one of the two")
    func everydiscountIsOneFormOrTheOther() throws {
        for discount in [try #require(Discount(dollars: Money(dollars: 50))),
                         try #require(Discount(dollars: .zero)),
                         try #require(Discount(percentBasisPoints: 0)),
                         try #require(Discount(percentBasisPoints: 10_000))] {
            let answers = [discount.dollarsOff != nil, discount.percentBasisPoints != nil]
            #expect(answers.filter { $0 }.count == 1)
        }
    }

}
