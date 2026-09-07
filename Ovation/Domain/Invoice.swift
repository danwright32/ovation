// ovation#60. The invoice, the shoots it covers, the lines it charges, and the
// arithmetic that decides what a client is asked to pay.
//
// NO @Attribute(.unique) ANYWHERE, INCLUDING ON id. PRD 42c: the attribute does
// not prevent a duplicate, it chooses which failure the duplicate becomes, and
// with it a colliding id destroys the row that was there. Without it the
// collision leaves two rows, which the export reconciliation can find and a
// person can repair. `SwiftDataBehaviourTests` holds both halves against each
// other so the choice is defended rather than inherited.
//
// EXTERNAL IDENTIFIERS ARE ORDINARY LOOKUP FIELDS AND NEVER THE IDENTITY. A
// booking id or a QuickBooks row key is stored so a re-run can FIND an existing
// invoice through Ovation's own lookup, never land on it by construction. A
// lookup needing exactly one row refuses on more than one rather than taking the
// first (L521).
//
// THE RATES ARE FROZEN AT CREATION rather than read from settings when the
// document is rendered, so a settings change can never silently rewrite an
// invoice that has already been sent. PRD 9.5, whether tax applies to rush and
// preview charges, is still open, which is exactly why the rate AND its base
// travel with the invoice.
import Foundation
import SwiftData

/// How an invoice ended, where it ended at all.
///
/// ONE VALUE RATHER THAN TWO OPTIONAL DATES. Cancelled and dismissed are
/// mutually exclusive and each carries its own date and reason, so a pair of
/// nullable fields would allow a row that is both, and would let a reader answer
/// "was it dismissed" by testing a field that means something else (L163).
enum InvoiceClosure: Equatable, Hashable, Codable, Sendable {
    /// A sent invoice withdrawn. PRD 5.13: if it was issued in a filed tax year
    /// this is a refusal to be raised with the accountant, not a quiet edit.
    case cancelled(on: BusinessDate, reason: String)
    /// A draft Dan decided never to bill. PRD 5.1b: dismissing keeps the row and
    /// records the decision, which is what lets Ovation tell a comped shoot from
    /// an invoice he forgot.
    case dismissed(on: BusinessDate, reason: String)

    var closedOn: BusinessDate {
        switch self {
        case .cancelled(let on, _), .dismissed(let on, _): return on
        }
    }
}

/// Something wrong enough that the invoice must not go out as it stands.
enum InvoiceRefusal: String, CaseIterable, Codable, Hashable, Sendable {
    /// PRD 5.4a. Reported rather than clamped, because clamping destroys the
    /// evidence that somebody typed the wrong number (L340).
    case discountExceedsSubtotal
}

/// Something Dan should see before sending, which does not stop the send.
enum InvoiceWarning: String, CaseIterable, Codable, Hashable, Sendable {
    /// PRD 5. A missing status is not the same as not exempt, and the invoice
    /// says so rather than quietly charging as though the answer were known.
    case taxStatusNeverRecorded
}

@Model
final class Invoice {
    /// Ovation's own identity, minted fresh and never derived from anything
    /// outside the app.
    var id: UUID = UUID()

    /// Allocated from the one continuous sequence when the invoice is issued.
    /// NIL WHILE IT IS A DRAFT, which is what lets Dan combine two drafts without
    /// burning a number (PRD 5.1a). The allocator itself is ovation#37.
    var number: Int64?

    /// What the money is for. PRD 5.2a.
    var kind: InvoiceKind = InvoiceKind.photography

    var client: Client?

    /// The date that decides the tax year, stamped at write. Nil only while a
    /// draft has no date at all, which is a real state the invoice list has to
    /// have a group for (ovation#49).
    var invoiceDate: BusinessDate?

    /// PRD 5.7, fourteen days after the invoice date, overridable per client and
    /// per invoice, which is why it is stored rather than derived at read.
    var dueDate: BusinessDate?

    /// Frozen at creation. See the header.
    var hourlyRate: Money = Money.zero
    var taxRate: TaxRate = TaxRate.newYorkCity

    /// PRD 5.4a. Below the subtotal, never a line.
    var discount: Discount?

    /// PRD 5.10a. Only ever observed.
    var sentStatus: SentStatus = SentStatus.notSent

    var closure: InvoiceClosure?

    var noteToClient: String?

    /// The booking this was drafted from, for LOOKUP only. See the header.
    var bookingKey: String?

    /// The QuickBooks row this was imported from, for lookup only. ovation#68
    /// owns what goes in it.
    var importKey: String?

    @Relationship(deleteRule: .cascade, inverse: \Shoot.invoice)
    var shoots: [Shoot] = []

    @Relationship(deleteRule: .cascade, inverse: \LineItem.invoice)
    var lineItems: [LineItem] = []

    init(
        client: Client?,
        kind: InvoiceKind,
        invoiceDate: BusinessDate?,
        hourlyRate: Money,
        taxRate: TaxRate
    ) {
        self.client = client
        self.kind = kind
        self.invoiceDate = invoiceDate
        self.hourlyRate = hourlyRate
        self.taxRate = taxRate
    }

    // MARK: the order things are read in

    /// A collection read from a store carries no order unless the read declares
    /// one (L343), and a relationship is a collection. Both accessors below sort
    /// explicitly rather than rendering whatever came back.
    ///
    /// MEASURED, NOT ASSUMED. Removing the sort here and re-running returns three
    /// lines inserted first, second, third as `["third", "second", "first"]`, so
    /// an invoice rendered straight from the relationship would print its charges
    /// backwards. The rule is not theoretical in this store.
    var orderedLineItems: [LineItem] { lineItems.sorted { $0.sortIndex < $1.sortIndex } }

    var orderedShoots: [Shoot] { shoots.sorted { $0.sortIndex < $1.sortIndex } }

    func add(_ item: LineItem) {
        item.sortIndex = (lineItems.map(\.sortIndex).max() ?? -1) + 1
        lineItems.append(item)
    }

    func add(_ shoot: Shoot) {
        shoot.sortIndex = (shoots.map(\.sortIndex).max() ?? -1) + 1
        shoots.append(shoot)
    }

    // MARK: what it comes to

    /// The sum of the lines, referral credits included, because a credit is a
    /// negative LINE and sits inside the subtotal (PRD 5.4b).
    var subtotal: Money { Money.sum(of: lineItems.map(\.amount)) }

    /// What the discount takes off. Zero where there is none.
    var discountAmount: Money { discount?.amount(on: subtotal) ?? .zero }

    /// What the tax is charged on. PRD 5.4a: the subtotal AFTER the discount.
    var taxableAmount: Money { subtotal - discountAmount }

    /// The tax, or nothing at all for an exempt client.
    var tax: Money {
        guard client?.taxStatus.isTaxed ?? true else { return .zero }
        return taxRate.tax(on: taxableAmount)
    }

    var total: Money { taxableAmount + tax }

    // MARK: what it says about itself

    var refusals: Set<InvoiceRefusal> {
        var found: Set<InvoiceRefusal> = []
        if discount?.exceeds(subtotal) == true { found.insert(.discountExceedsSubtotal) }
        return found
    }

    var warnings: Set<InvoiceWarning> {
        var found: Set<InvoiceWarning> = []
        if client?.taxStatus == .neverRecorded { found.insert(.taxStatusNeverRecorded) }
        return found
    }
}
