// Plan 1.4, ovation#53. Money, hours, the one rounding rule, and the tax rate
// that is the only reason the rounding rule exists.
//
// NOT A PORT. Neither sibling has a money type: Downbeat books shoots and
// Overture chases them, and neither one prices anything.
//
// THE ABSENCE OF A FLOATING POINT CONSTRUCTOR IS THE FEATURE. A `Money(Double)`
// means every call site is one careless conversion away from a rounding error,
// and the errors are small enough to survive review and large enough to matter
// across a tax year. There is no such initialiser here, and no
// `ExpressibleByFloatLiteral`, so the mistake cannot be written rather than
// being discouraged by a comment (L27, L407).
//
// `scripts/check-money-types.sh` is the other half of that: a rule stated only
// in this header is enforced by nothing, so the guard refuses `Double`, `Float`
// and `Decimal` anywhere in the app's sources.
import Foundation

/// The ONE place a value is divided, and therefore the one place a fraction of a
/// cent has to become a whole one.
///
/// Both callers, sales tax and an hourly charge, go through this. Two
/// implementations of "round a division" is two decisions that can drift, and
/// the one that drifted would be the one believed (L107, L370).
enum Rounding {
    /// Half away from zero, stated for negatives as well as positives.
    ///
    /// Rounding half toward positive infinity would make a credit of the same
    /// size as a charge round by a different amount, which is the sort of
    /// asymmetry nobody finds until a refund is a cent out. Banker's rounding to
    /// even is the other defensible rule and it is deliberately NOT this one;
    /// `MoneyTests` asserts the difference so the choice is defended rather than
    /// inherited from whatever a platform would have done.
    static func halfAwayFromZero(_ numerator: Int64, over denominator: Int64) -> Int64 {
        precondition(denominator > 0, "the denominator is a fixed scale, never an input")

        let negative = numerator < 0
        let magnitude = negative ? -numerator : numerator
        let rounded = (magnitude * 2 + denominator) / (denominator * 2)
        return negative ? -rounded : rounded
    }
}

/// An amount of money, in whole US cents.
///
/// ONE CURRENCY, SAID IN THE TYPE rather than carried as a field nothing reads.
/// Dan invoices in US dollars and the tax rate here is New York City's. If a
/// second currency ever arrives, the amount and its currency are ONE fact and
/// this type gains a currency, so that no call site can ever hold an amount
/// beside a separate currency and get the pairing wrong (L544).
struct Money: Equatable, Hashable, Comparable, Codable, Sendable {
    let cents: Int64

    init(cents: Int64) { self.cents = cents }

    /// A whole number of dollars. There is deliberately no `init(dollars:cents:)`
    /// taking two numbers, because a caller writing `Money(dollars: 12, cents: 5)`
    /// means five cents about half the time and fifty the other half.
    init(dollars: Int64) { self.cents = dollars * 100 }

    static let zero = Money(cents: 0)

    static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }

    static func + (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents + rhs.cents) }

    static func - (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents - rhs.cents) }

    static prefix func - (value: Money) -> Money { Money(cents: -value.cents) }

    /// The sum of no amounts is zero, never a missing value: an empty invoice has
    /// a subtotal, and it is nothing (L215).
    /// How an amount is written into an export file: a plain decimal, no
    /// currency symbol and no thousands separator, so a spreadsheet reads it as
    /// a number in any locale (ovation#61).
    ///
    /// A NEGATIVE AMOUNT KEEPS ITS MINUS SIGN, which is the reason the CSV writer
    /// has two kinds of field: neutralising a leading minus as a formula would
    /// turn every credit into text nothing will total.
    var exportAmount: String {
        let sign = cents < 0 ? "-" : ""
        let magnitude = cents.magnitude
        return "\(sign)\(magnitude / 100).\(String(format: "%02d", magnitude % 100))"
    }

    static func sum(of amounts: [Money]) -> Money {
        amounts.reduce(Money.zero, +)
    }

    /// A whole number of identical charges. Exact, so it does not touch
    /// `Rounding` at all.
    func times(_ count: Int64) -> Money { Money(cents: cents * count) }

    /// What a stretch of shooting costs at a given hourly rate.
    ///
    /// It takes an `Hours` and a `Money`, so the two can never be passed the
    /// wrong way round, and it returns money. Exact wherever the rate is a whole
    /// number of dimes, which today's $250 is; it goes through the one rounding
    /// rule where it is not.
    ///
    /// The one hour minimum and the refusal of an implausible duration are
    /// pricing rules and live with the invoice (ovation#43). This is the
    /// arithmetic only.
    static func charge(for hours: Hours, at hourlyRate: Money) -> Money {
        Money(cents: Rounding.halfAwayFromZero(hourlyRate.cents * hours.hundredths, over: 100))
    }
}

/// A length of time billed for, in whole HUNDREDTHS of an hour.
///
/// Hundredths because ovation#127 corrected the unit, and the reason is set out
/// in full on `hundredths` below. This summary states the unit the type actually
/// carries rather than the tenths PRD 5.3 asked for and round 4 of ovation#111
/// made impossible: it is a value that decides money, and a header arguing for a
/// rejected unit reads as a considered decision rather than as something nobody
/// updated (L346).
///
/// A separate type from `Money` with no conversion between them, so an hourly
/// rate and a duration cannot be swapped at a call site: the compiler refuses
/// rather than the invoice being wrong by a factor of the rate.
struct Hours: Equatable, Hashable, Comparable, Codable, Sendable {

    /// HUNDREDTHS OF AN HOUR, and the unit is the whole of ovation#127.
    ///
    /// It was TENTHS, from PRD 5.3's "exact to one decimal", and that requirement
    /// was wrong by construction from the moment round 4 of ovation#111 settled
    /// on rounding to the nearest QUARTER hour, which Dan chose. A quarter is
    /// 0.25, and 1.25 and 1.75 hours are not representable in tenths at all.
    ///
    /// IT IS NOT A ROUNDING NICETY, IT IS MONEY. Measured from the FreshBooks
    /// export: quarter hour values appear throughout Dan's real history, 1.75 on
    /// eleven lines alone, and 2.25, 3.25, 4.25, 4.75 and 6.25 besides. At $250
    /// an hour, a 1.75 hour shoot forced onto a tenth prices at $425.00 or
    /// $450.00 against the $437.50 it ran.
    ///
    /// HUNDREDTHS AND NOT QUARTERS, because the history holds 2.15 and 1.15,
    /// which are on neither a quarter nor a tenth. Hundredths represent every
    /// value Dan has ever billed exactly, and tenths and quarters are both whole
    /// numbers of them, so nothing that used to be exact stopped being so.
    let hundredths: Int64

    init(hundredths: Int64) { self.hundredths = hundredths }

    /// Tenths remain a legitimate way to SAY a duration, and this is why every
    /// existing call site still reads correctly: a tenth is ten hundredths.
    init(tenths: Int64) { self.hundredths = tenths * 10 }

    /// The unit the rounding rule actually produces (docs/design/rules/duration.js).
    init(quarters: Int64) { self.hundredths = quarters * 25 }

    init(whole: Int64) { self.hundredths = whole * 100 }

    static let zero = Hours(hundredths: 0)

    static func < (lhs: Hours, rhs: Hours) -> Bool { lhs.hundredths < rhs.hundredths }

    static func + (lhs: Hours, rhs: Hours) -> Hours {
        Hours(hundredths: lhs.hundredths + rhs.hundredths)
    }
}

/// A sales tax rate, in thousandths of a percent, which is what it takes to hold
/// 8.875 exactly as an integer.
///
/// IT IS A VALUE SO AN INVOICE CAN CARRY THE ONE IT WAS CREATED WITH. PRD 9.5,
/// whether tax applies to rush and preview charges, is unresolved, so the rate
/// and its base are frozen onto the invoice rather than read from settings when
/// the document is rendered. A settings change must never silently rewrite an
/// invoice that has already been sent.
struct TaxRate: Equatable, Hashable, Codable, Sendable, CustomStringConvertible {
    let thousandthsOfAPercent: Int64

    init(thousandthsOfAPercent: Int64) {
        self.thousandthsOfAPercent = thousandthsOfAPercent
    }

    /// 8.875%. PRD 5: it applies to the subtotal AFTER any discount, matching
    /// real invoice 1057, and that base is pinned by an invoice rather than by
    /// argument because tax rounded per line and tax rounded on the total are
    /// different numbers and both look right.
    ///
    /// CORRECTED 2026-09-07 (ovation#60): this said the WHOLE subtotal, which was
    /// true until Dan settled the discount on 2026-09-06. A discount sits below
    /// the subtotal and the tax is charged on what is left (PRD 5.4a), so a
    /// caller passing the undiscounted subtotal now overcharges by the tax on the
    /// discount. `Discount` is the other half of this.
    static let newYorkCity = TaxRate(thousandthsOfAPercent: 8_875)

    var description: String {
        let whole = thousandthsOfAPercent / 1_000
        let fraction = abs(thousandthsOfAPercent % 1_000)
        guard fraction != 0 else { return "\(whole)%" }
        var digits = String(format: "%03d", fraction)
        while digits.hasSuffix("0") { digits.removeLast() }
        return "\(whole).\(digits)%"
    }

    /// The tax on an amount. The CALLER decides what that amount is, and PRD 5
    /// says it is the whole subtotal.
    func tax(on amount: Money) -> Money {
        Money(cents: Rounding.halfAwayFromZero(
            amount.cents * thousandthsOfAPercent, over: 100_000))
    }
}
