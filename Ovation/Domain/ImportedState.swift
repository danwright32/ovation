// ovation#70. What an imported invoice or payment said when the import wrote it,
// reduced to one value a revert can compare against.
//
// WHY A FINGERPRINT RATHER THAN AN "EDITED" FLAG. A flag would have to be set by
// every writer that can change an invoice, a line, a date, a discount or a closure,
// and a behaviour each writer must opt into is enforced by nothing: the first new
// writer that forgets it makes an edited invoice read as untouched, and the revert
// then deletes Dan's work (L621, L384). Comparing what the row says now against
// what it said when it was written needs nothing from any writer.
//
// EVERY FIELD THE INVOICE CARRIES, AND ITS LINES AND SHOOTS. A field left out is a
// field Dan can change without the revert noticing. Money that arrived since is not
// read here: a payment, a refund, a referral credit and a message sent are records
// of their own, and the revert enumerates them by name (ovation#70, L38).
//
// THE ENCODING IS VERSIONED. A later field added to `Invoice` must not change the
// fingerprint of a row written before it, or every earlier import would read as
// edited and could never be reverted (L1013). So the snapshot below lists its
// fields itself rather than encoding the model, and its version is part of what is
// stored: a new field goes into a version 2, and a row is compared under the
// version it was stamped with.
import CryptoKit
import Foundation

enum ImportedState {

    static let version = 1

    static func fingerprint(of invoice: Invoice) -> String {
        stamp(InvoiceSnapshot(invoice))
    }

    static func fingerprint(of payment: Payment) -> String {
        stamp(PaymentSnapshot(payment))
    }

    /// Whether `stored` still describes the invoice. False for a stamp written
    /// under a version this build cannot compute, which a revert treats as
    /// changed: an answer it cannot give is not an answer that nothing changed.
    static func matches(_ stored: String?, _ invoice: Invoice) -> Bool {
        stored != nil && stored == fingerprint(of: invoice)
    }

    static func matches(_ stored: String?, _ payment: Payment) -> Bool {
        stored != nil && stored == fingerprint(of: payment)
    }

    private static func stamp<T: Encodable>(_ snapshot: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // ENCODING CANNOT FAIL for these value types, and if it ever did the stamp
        // must not read as a match: an empty encoding stamps a value no real row
        // produces, so the revert refuses rather than deleting.
        let data = (try? encoder.encode(snapshot)) ?? Data()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "v\(version):\(digest)"
    }

    private struct LineSnapshot: Encodable {
        let id: UUID
        let sortIndex: Int
        let summary: String
        let hours: Hours?
        let unitAmount: Money
        let serviceType: UUID?
        let shoot: UUID?
    }

    private struct InvoiceSnapshot: Encodable {
        let number: Int64?
        let numberHeldByAReview: Bool
        let kind: InvoiceKind
        let client: UUID?
        let invoiceDate: String?
        let dueDate: String?
        let hourlyRate: Money
        let taxRate: TaxRate
        let discount: Discount?
        let referralCredit: ReferralCredit?
        let sentStatus: SentStatus
        let taxStatusWhenSent: TaxStatus?
        let closure: InvoiceClosure?
        let bookingKey: String?
        let createdOn: String?
        let heldMoneyRemovedOn: String?
        let shoots: [UUID]
        let lines: [LineSnapshot]

        init(_ invoice: Invoice) {
            number = invoice.number
            numberHeldByAReview = invoice.numberHeldByAReview
            kind = invoice.kind
            let client = invoice.client
            self.client = client?.id
            invoiceDate = invoice.invoiceDate?.dayKey
            dueDate = invoice.dueDate?.dayKey
            hourlyRate = invoice.hourlyRate
            taxRate = invoice.taxRate
            discount = invoice.discount
            referralCredit = invoice.referralCredit
            sentStatus = invoice.sentStatus
            taxStatusWhenSent = invoice.taxStatusWhenSent
            closure = invoice.closure
            bookingKey = invoice.bookingKey
            createdOn = invoice.createdOn?.dayKey
            heldMoneyRemovedOn = invoice.heldMoneyRemovedOn?.dayKey
            // IN A DECLARED ORDER, never the store's (L343), so the same invoice
            // read twice stamps the same value.
            shoots = invoice.shoots.map(\.id).sorted { $0.uuidString < $1.uuidString }
            lines = invoice.lineItems
                .sorted { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
                .map { line in
                    LineSnapshot(id: line.id, sortIndex: line.sortIndex, summary: line.summary,
                                 hours: line.hours, unitAmount: line.unitAmount,
                                 serviceType: line.serviceType?.id, shoot: line.shoot?.id)
                }
        }
    }

    private struct PaymentSnapshot: Encodable {
        let client: UUID?
        let amount: Money
        let receivedOn: String
        let method: PaymentMethod
        let clearedOn: String?
        let reference: String?

        init(_ payment: Payment) {
            let client = payment.client
            self.client = client?.id
            amount = payment.amount
            receivedOn = payment.receivedOn.dayKey
            method = payment.method
            clearedOn = payment.clearedOn?.dayKey
            reference = payment.reference
        }
    }
}
