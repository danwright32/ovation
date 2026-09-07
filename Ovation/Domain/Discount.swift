// ovation#60, PRD 5.4a. A discount, which is one fact with two forms.
//
// IT IS NOT A LINE ITEM, and that is a decision with a consequence in the
// arithmetic rather than a presentational preference. It sits BELOW the
// subtotal, and the tax is charged on what is left, so an implementer who makes
// it a negative line changes the tax base and the invoice is wrong by the tax on
// the discount. A referral credit IS a negative line, inside the subtotal, and
// the two net to the same tax, which is exactly why they are easy to merge and
// must not be (PRD 5.4b): the export has to answer how much was given away in a
// year, and merging them makes that unanswerable.
//
// ONE VALUE, NOT AN AMOUNT BESIDE A KIND. An amount and the flag saying what the
// amount MEANS are one fact, and holding them as two properties lets a call site
// read fifty and charge fifty dollars where fifty percent was meant (L544). The
// form is private and the only ways in are the two initialisers below, so the
// pairing cannot be got wrong and an invalid discount cannot be constructed at
// all rather than being discouraged by a comment (L27).
import Foundation

struct Discount: Equatable, Hashable, Codable, Sendable {

    /// The two forms, private so that every discount in the app has been through
    /// one of the refusals below.
    private enum Form: Equatable, Hashable, Codable, Sendable {
        case dollars(Money)
        case percentBasisPoints(Int64)
    }

    private let form: Form

    /// A fixed amount off. Refuses a negative one: that is a surcharge, and
    /// nothing in the product has ever asked for one, so it is a mistake rather
    /// than an unsupported feature.
    init?(dollars: Money) {
        guard dollars >= .zero else { return nil }
        self.form = .dollars(dollars)
    }

    /// A share of the PRE TAX subtotal, in basis points, so 10% is 1,000 and
    /// 33.33% is 3,333.
    ///
    /// Basis points rather than a percentage figure because a percentage with a
    /// fraction is the case that forces a floating point type into the money
    /// path, which plan 1.4 exists to prevent.
    ///
    /// The range is nothing off up to the whole subtotal, inclusive at both ends.
    /// A hundred percent is legitimate: PRD 5.1b records that a comped shoot is
    /// occasionally invoiced at zero for a corporate client's accounts payable,
    /// and "no guard may refuse" that invoice.
    init?(percentBasisPoints: Int64) {
        guard (0...10_000).contains(percentBasisPoints) else { return nil }
        self.form = .percentBasisPoints(percentBasisPoints)
    }

    /// What comes off a subtotal of this size.
    ///
    /// A percentage goes through `Rounding`, the one implementation both the tax
    /// and the hourly charge use, so a discount and the charge it is taken
    /// against round the same way in both directions. That matters below zero: a
    /// subtotal can be negative when a referral credit line exceeds the charges,
    /// and a rule rounding half toward positive infinity would make the discount
    /// on a credit a different size from the discount on the charge reversing it.
    func amount(on subtotal: Money) -> Money {
        switch form {
        case .dollars(let fixed):
            return fixed
        case .percentBasisPoints(let points):
            return Money(cents: Rounding.halfAwayFromZero(
                subtotal.cents * points, over: 10_000))
        }
    }

    /// Whether this discount is larger than the subtotal it is being taken off.
    ///
    /// A percentage can never be, since it is a share of that very subtotal. A
    /// fixed amount can, and nothing at the moment it is entered knows the
    /// subtotal, so the question is asked here rather than at construction.
    ///
    /// IT REPORTS RATHER THAN CLAMPING. Silently reducing an oversized discount
    /// to the subtotal would destroy the only evidence that somebody typed the
    /// wrong number, and the clamped invoice is indistinguishable from one where
    /// a full discount was meant (L340). Equal is not over: that is the zero
    /// invoice PRD 5.1b says is legitimate.
    func exceeds(_ subtotal: Money) -> Bool {
        switch form {
        case .dollars(let fixed):
            return fixed > subtotal
        case .percentBasisPoints:
            return false
        }
    }
}
