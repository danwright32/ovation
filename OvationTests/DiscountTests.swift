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
}
