import Foundation
import Testing
@testable import Ovation

/// Plan 1.4, ovation#53. Money is integer cents behind a type with no floating
/// point constructor at all, and every rounding decision in the app goes through
/// one implementation.
struct MoneyTests {

    // MARK: the representation

    @Test("money is stored as whole cents")
    func moneyIsWholeCents() {
        #expect(Money(cents: 25_000).cents == 25_000)
        #expect(Money.zero.cents == 0)
        #expect(Money(dollars: 250).cents == 25_000)
        #expect(Money(dollars: -250).cents == -25_000)
    }

    @Test("two amounts of the same cents are the same amount")
    func equalityIsByCents() {
        #expect(Money(cents: 1_234) == Money(cents: 1_234))
        #expect(Money(cents: 1_234) != Money(cents: 1_235))
    }

    @Test("amounts order the way numbers do, including below zero")
    func amountsCompare() {
        #expect(Money(cents: -100) < Money.zero)
        #expect(Money.zero < Money(cents: 1))
        #expect(Money(cents: 5_000) > Money(cents: 4_999))
    }

    // MARK: arithmetic

    @Test("amounts add, subtract and negate")
    func arithmeticIsExact() {
        #expect(Money(cents: 1_000) + Money(cents: 2_345) == Money(cents: 3_345))
        #expect(Money(cents: 1_000) - Money(cents: 2_345) == Money(cents: -1_345))
        #expect(-Money(cents: 1_000) == Money(cents: -1_000))
    }

    @Test("the sum of nothing is nothing, not a missing value")
    func theEmptySumIsZero() {
        #expect(Money.sum(of: []) == Money.zero)
    }

    @Test("a whole number of identical charges is a multiplication, never a repeated addition at the call site")
    func wholeMultiplesAreExact() {
        #expect(Money(cents: 2_500).times(4) == Money(cents: 10_000))
        #expect(Money(cents: 2_500).times(0) == Money.zero)
        #expect(Money(cents: 2_500).times(-2) == Money(cents: -5_000))
    }

    // MARK: the property PRD 42 asks for

    @Test("no sequence of line items can make the sum of the parts disagree with the total")
    func theSumOfPartsAlwaysAgreesWithTheTotal() {
        // What this proves is narrow and worth stating: that `sum` is addition
        // over every item, in any order, including negative lines (a referral
        // credit is one). It does not prove anything about a stored total, which
        // arrives with the invoice model. The seed is fixed, so a failure is
        // reproducible and two runs measure the same thing (L339).
        var rng = SeededGenerator(seed: 1_057)

        for _ in 0..<500 {
            let count = Int.random(in: 1...12, using: &rng)
            let lines = (0..<count).map { _ in
                Money(cents: Int64.random(in: -50_000...500_000, using: &rng))
            }

            var running = Money.zero
            for line in lines { running = running + line }

            #expect(Money.sum(of: lines) == running)
            #expect(Money.sum(of: lines.reversed()) == running)
            #expect(Money.sum(of: lines) - running == Money.zero)
        }
    }

    // MARK: rounding, in one place

    @Test("a half lands away from zero, so the same magnitude rounds the same way either side of zero")
    func halvesRoundAwayFromZero() {
        // Half up, stated for negatives too. Round half toward positive infinity
        // and a credit of the same size as a charge rounds by a different amount,
        // which is the kind of asymmetry nobody finds until a refund is a cent out.
        #expect(Rounding.halfAwayFromZero(5, over: 10) == 1)
        #expect(Rounding.halfAwayFromZero(15, over: 10) == 2)
        #expect(Rounding.halfAwayFromZero(25, over: 10) == 3)
        #expect(Rounding.halfAwayFromZero(-5, over: 10) == -1)
        #expect(Rounding.halfAwayFromZero(-15, over: 10) == -2)
        #expect(Rounding.halfAwayFromZero(-25, over: 10) == -3)
    }

    @Test("banker's rounding is NOT what this does, and the difference is asserted")
    func roundingIsNotToEven() {
        // 2.5 to even is 2. Half away from zero is 3. Both are defensible rules
        // and only one is the one Ovation states, so it is pinned rather than
        // left to whichever the platform would have chosen.
        #expect(Rounding.halfAwayFromZero(25, over: 10) != 2)
    }

    @Test("anything below a half rounds down, anything above it rounds up")
    func theOrdinaryCasesRound() {
        #expect(Rounding.halfAwayFromZero(4, over: 10) == 0)
        #expect(Rounding.halfAwayFromZero(6, over: 10) == 1)
        #expect(Rounding.halfAwayFromZero(-4, over: 10) == 0)
        #expect(Rounding.halfAwayFromZero(-6, over: 10) == -1)
    }

    @Test("an exact division is not disturbed by the rounding rule")
    func exactDivisionsAreLeftAlone() {
        #expect(Rounding.halfAwayFromZero(100, over: 10) == 10)
        #expect(Rounding.halfAwayFromZero(-100, over: 10) == -10)
        #expect(Rounding.halfAwayFromZero(0, over: 10) == 0)
    }
}

/// Sales tax, whose rate and base are the reason this type exists rather than a
/// number multiplied at the call site.
struct TaxRateTests {

    @Test("the New York City rate is 8.875 percent, held without floating point")
    func theRateIsExact() {
        #expect(TaxRate.newYorkCity.thousandthsOfAPercent == 8_875)
        #expect(TaxRate.newYorkCity.description == "8.875%")
    }

    @Test("tax on a round amount is exact")
    func taxOnARoundAmount() {
        // 8.875% of $1,000.00 is $88.75 exactly.
        #expect(TaxRate.newYorkCity.tax(on: Money(dollars: 1_000)) == Money(cents: 8_875))
    }

    @Test("tax that lands on half a cent rounds away from zero")
    func taxOnAHalfCent() {
        // 8.875% of $100.00 is 887.5 cents.
        #expect(TaxRate.newYorkCity.tax(on: Money(dollars: 100)) == Money(cents: 888))
    }

    @Test("tax on the whole subtotal is not the same number as tax on each line")
    func theBaseIsTheWholeSubtotalAndItMatters() {
        // The rule is pinned by a real invoice (1057) rather than by argument,
        // because a tax figure rounded per line and one rounded on the total are
        // different numbers and both look right. This asserts that they really do
        // differ, so the decision is defended by a test rather than by a comment.
        let lines = [Money(cents: 3_333), Money(cents: 3_333), Money(cents: 3_333)]
        let subtotal = Money.sum(of: lines)

        let onTheWhole = TaxRate.newYorkCity.tax(on: subtotal)
        let perLine = Money.sum(of: lines.map { TaxRate.newYorkCity.tax(on: $0) })

        #expect(onTheWhole == Money(cents: 887))
        #expect(perLine == Money(cents: 888))
        #expect(onTheWhole != perLine)
    }

    @Test("tax on nothing is nothing")
    func taxOnZero() {
        #expect(TaxRate.newYorkCity.tax(on: .zero) == Money.zero)
    }

    @Test("tax on a credit is a credit of the same magnitude")
    func taxOnANegativeAmount() {
        #expect(TaxRate.newYorkCity.tax(on: Money(dollars: -100)) == Money(cents: -888))
    }

    @Test("a rate is a value, so an invoice can carry the one it was created with")
    func aRateCanBeStoredRatherThanReadFromSettings() {
        // PRD 9.5 is unresolved, so the rate and its base are stored ON the
        // invoice. A settings change must never silently rewrite a document that
        // has already been sent.
        let frozen = TaxRate(thousandthsOfAPercent: 8_875)
        #expect(frozen == TaxRate.newYorkCity)
        #expect(TaxRate(thousandthsOfAPercent: 0).tax(on: Money(dollars: 500)) == Money.zero)
    }
}

/// Hours are tenths, for the same reason money is cents, and the two types
/// cannot be mistaken for one another: there is no conversion between them and
/// pricing takes one of each.
struct HoursTests {

    @Test("hours are stored as whole tenths")
    func hoursAreTenths() {
        #expect(Hours(tenths: 15).tenths == 15)
        #expect(Hours(whole: 2).tenths == 20)
        #expect(Hours.zero.tenths == 0)
    }

    @Test("hours order and add the way durations do")
    func hoursCompareAndAdd() {
        #expect(Hours(tenths: 9) < Hours(whole: 1))
        #expect(Hours(tenths: 15) + Hours(tenths: 5) == Hours(whole: 2))
    }

    @Test("an hourly charge is hours times a rate, and comes back as money")
    func pricingIsExactWhereItCanBe() {
        // $250.00 per hour, 1.5 hours.
        #expect(Money.charge(for: Hours(tenths: 15), at: Money(dollars: 250))
                == Money(cents: 37_500))
        #expect(Money.charge(for: Hours.zero, at: Money(dollars: 250)) == Money.zero)
    }

    @Test("an hourly charge that lands on half a cent uses the same rounding rule as tax")
    func pricingRoundsThroughTheOneImplementation() {
        // A rate of $249.95 for a tenth of an hour is 2499.5 cents. There is only
        // one rounding rule in the app and this is the same one, not a second
        // decision made where the multiplication happens.
        #expect(Money.charge(for: Hours(tenths: 1), at: Money(cents: 24_995))
                == Money(cents: 2_500))
    }
}

/// Deterministic, so a property failure is reproducible and two runs measure the
/// same thing. SplitMix64.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
