// ovation#60. Who is invoiced.
//
// TAX STATUS LIVES HERE AND NOT ON THE INVOICE, which is one of the facts PRD
// 5.83 says must have a single declared home. It is a property of the client
// rather than of a job, which is why ovation#40's roster pass is per client, and
// why an invoice reads it rather than copying it.
//
// MONEY HELD ON A CLIENT IS DERIVED, NEVER STORED. See `Payment` (ovation#60
// step 3b): it is what was received minus what is allocated, computed from one
// predicate so a count and the rows it promises can never disagree (L16).
import Foundation
import SwiftData

@Model
final class Client {
    var id: UUID = UUID()

    var name: String = ""

    /// PRD 5. Three answers, because a missing one is not a no.
    var taxStatus: TaxStatus = TaxStatus.neverRecorded

    /// Where invoices go. PRD 5.38 refuses a send with none, and refuses one
    /// where two clients share an address; ovation#40 clears both before those
    /// refusals start speaking.
    var contractEmail: String?

    /// PRD 5.7's per client override of the fourteen day default. Nil means the
    /// default, and it is a real absence rather than a zero.
    var paymentTermDays: Int?

    @Relationship(deleteRule: .nullify, inverse: \Invoice.client)
    var invoices: [Invoice] = []

    @Relationship(deleteRule: .nullify, inverse: \Payment.client)
    var payments: [Payment] = []

    @Relationship(deleteRule: .nullify, inverse: \ReferralLedgerEntry.client)
    var referralEntries: [ReferralLedgerEntry] = []

    init(name: String, taxStatus: TaxStatus) {
        self.name = name
        self.taxStatus = taxStatus
    }

    /// Money Ovation is holding on this client's behalf: what arrived, less what
    /// is spoken for. PRD 5.14a says this is a real state rather than an error,
    /// and it is where a deposit taken before the shoot sits.
    ///
    /// DERIVED, NEVER STORED, and computed from the same predicate every payment
    /// uses, so this number and the payments a screen lists cannot disagree (L16).
    ///
    /// IT IS NOT REFERRAL CREDIT. See the header on `Payment`.
    var moneyHeld: Money { Money.sum(of: payments.map(\.unallocated)) }

    /// Referral credit standing to this client, in hours. PRD 5.8.
    ///
    /// A SUM OVER THE LEDGER, never a stored field, so nothing has to remember to
    /// keep a total in step and no edit can leave the two disagreeing.
    ///
    /// IT IS NOT MONEY HELD, and the two never add up (PRD 5.14c). Credit was
    /// earned against a ledger and is spent as a negative line inside an invoice;
    /// held money actually arrived and is owed back if it is never used. They
    /// will look alike on the Clients screen, which is why they are two accessors
    /// of two different types rather than one number.
    var referralBalance: Hours {
        referralEntries.reduce(Hours.zero) { $0 + $1.hours }
    }
}
