// ovation#126, PRD 5.8 as CORRECTED by round 6 of ovation#111. Referral credit
// spent on one invoice.
//
// IT IS NOT A LINE ITEM, and that is Dan's decision of 2026-09-07, taken having
// been shown that it contradicts the requirement and the shipped model. The
// credit sits in its own block between the lines and the subtotal.
//
// THE ARITHMETIC DID NOT CHANGE, and that is the half worth stating. The credit
// is still INSIDE the subtotal and the discount still applies to what is left,
// which is the distinction PRD 5.4b exists to protect: the two net to the same
// tax, which is exactly why they are easy to merge and must not be. What changed
// is only where the credit lives, so 5.4b's conclusion survives and its reason
// ("a referral credit is a negative LINE") does not.
//
// ONE VALUE, NOT AN AMOUNT BESIDE ITS PROVENANCE, for the reason `Discount`
// records: a call site holding the parts separately can pair them wrongly
// (L544). The initialiser is failable and is the only way in, so a credit worth
// nothing cannot be constructed at all rather than being discouraged by a
// comment (L27).
//
// EARNED IN HOURS, SPENT AS MONEY. `ReferralLedgerEntry` is denominated in hours
// because that is what is earned, one hour per hour of the referred client's
// first booking, and turning it into money there would freeze it at whatever the
// rate was on the day. Here it IS that day: the invoice has frozen its rate, so
// the credit freezes with it.
import Foundation

struct ReferralCredit: Equatable, Hashable, Codable, Sendable {

    /// What is being spent, in the unit the ledger is kept in.
    let hours: Hours

    /// What that came to at the invoice's own frozen rate. Stored rather than
    /// recomputed so a rate change can never rewrite an invoice already sent,
    /// which is the same reason the rate itself travels with the invoice.
    let amount: Money

    /// Who the credit was earned on. The id keeps the link the ledger and the
    /// export need; the NAME is frozen because it is printed on the invoice and a
    /// client renamed in 2029 must not rewrite one sent in 2026. Both are absent
    /// where the credit was recorded without one, which an import can produce.
    let earnedFromClientID: UUID?
    let earnedFromClientName: String?

    /// Refuses a credit worth nothing or less. Zero records no decision, and a
    /// negative one is a CHARGE written the wrong way round: it would read on the
    /// invoice as a credit while increasing what is owed.
    init?(hours: Hours, at rate: Money, earnedFrom client: Client?) {
        guard hours > .zero else { return nil }
        self.hours = hours
        self.amount = Money.charge(for: hours, at: rate)
        self.earnedFromClientID = client?.id
        self.earnedFromClientName = client?.name
    }
}
