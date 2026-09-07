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

    init(name: String, taxStatus: TaxStatus) {
        self.name = name
        self.taxStatus = taxStatus
    }
}
