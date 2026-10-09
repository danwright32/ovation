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
// version it was stamped with, by that version's own rule (`fingerprint(of:version:)`).
import CryptoKit
import Foundation

enum ImportedState {

    /// The version new stamps are written under.
    static let version = 1

    /// The stamp for `invoice` under the current version, or nil where it could
    /// not be computed.
    static func fingerprint(of invoice: Invoice) -> String? {
        fingerprint(of: invoice, version: version)
    }

    /// The stamp for `invoice` under `version`'s own rule, or nil for a version
    /// this build has no rule for. EACH VERSION KEEPS ITS RULE: a version 2 adds a
    /// case here and leaves version 1's alone, so every row stamped under version 1
    /// is still compared the way it was stamped (L1013).
    static func fingerprint(of invoice: Invoice, version: Int) -> String? {
        switch version {
        case 1: return stamp(InvoiceSnapshot(invoice), version: 1)
        default: return nil
        }
    }

    static func fingerprint(of payment: Payment) -> String? {
        fingerprint(of: payment, version: version)
    }

    static func fingerprint(of payment: Payment, version: Int) -> String? {
        switch version {
        case 1: return stamp(PaymentSnapshot(payment), version: 1)
        default: return nil
        }
    }

    /// Whether `stored` still describes the invoice, recomputed under the version
    /// `stored` names. False for a stamp with no version this build can read, and
    /// for one it cannot recompute: an answer nobody has is not an answer that
    /// nothing changed, and the revert reads false as changed.
    static func matches(_ stored: String?, _ invoice: Invoice) -> Bool {
        guard let version = stampedVersion(stored) else { return false }
        return agree(stored: stored, computed: fingerprint(of: invoice, version: version))
    }

    static func matches(_ stored: String?, _ payment: Payment) -> Bool {
        guard let version = stampedVersion(stored) else { return false }
        return agree(stored: stored, computed: fingerprint(of: payment, version: version))
    }

    /// The fields each entity's stamp covers, by the names the model stores them
    /// under, read off the snapshots themselves so the answer cannot drift from what
    /// is stamped. `ImportedStateTests` holds it against the schema, so a field added
    /// to a model later fails there until it is stamped or deliberately left out.
    static func coverage(of invoice: Invoice, and payment: Payment) -> [String: Set<String>] {
        func labels(_ value: Any) -> Set<String> {
            Set(Mirror(reflecting: value).children.compactMap(\.label))
        }
        var found = ["Invoice": labels(InvoiceSnapshot(invoice)), "Payment": labels(PaymentSnapshot(payment))]
        if let line = invoice.lineItems.first { found["LineItem"] = labels(LineSnapshot(line)) }
        if let shoot = invoice.shoots.first { found["Shoot"] = labels(ShootSnapshot(shoot)) }
        return found
    }

    /// The one rule for whether a stored stamp and a recomputed one agree: both
    /// must exist and be equal. Two missing answers do not agree with each other.
    static func agree(stored: String?, computed: String?) -> Bool {
        guard let stored, let computed else { return false }
        return stored == computed
    }

    /// The version a stamp says it was written under, from its "vN:" prefix.
    private static func stampedVersion(_ stamp: String?) -> Int? {
        guard let stamp, stamp.hasPrefix("v"), let colon = stamp.firstIndex(of: ":") else { return nil }
        return Int(stamp[stamp.index(after: stamp.startIndex)..<colon])
    }

    /// Nil where the snapshot could not be encoded, never a stand in: a stamp of
    /// empty data would be written and recomputed alike, and match (review of
    /// 7c5bcda).
    private static func stamp<T: Encodable>(_ snapshot: T, version: Int) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "v\(version):\(digest)"
    }

    private struct ShootSnapshot: Encodable {
        let id: UUID
        let name: String
        let when: ShootWhen?
        let venue: String?
        let bookingKey: String?
        let sortIndex: Int
        let shotFrom: ClockTime?
        let shotUntil: ClockTime?

        init(_ shoot: Shoot) {
            id = shoot.id
            name = shoot.name
            when = shoot.when
            venue = shoot.venue
            bookingKey = shoot.bookingKey
            sortIndex = shoot.sortIndex
            shotFrom = shoot.shotFrom
            shotUntil = shoot.shotUntil
        }
    }

    private struct LineSnapshot: Encodable {
        let id: UUID
        let sortIndex: Int
        let summary: String
        let hours: Hours?
        let unitAmount: Money
        let serviceType: UUID?
        let shoot: UUID?

        init(_ line: LineItem) {
            id = line.id
            sortIndex = line.sortIndex
            summary = line.summary
            hours = line.hours
            unitAmount = line.unitAmount
            serviceType = line.serviceType?.id
            shoot = line.shoot?.id
        }
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
        let shoots: [ShootSnapshot]
        let lineItems: [LineSnapshot]

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
            // EVERY FIELD OF EVERY SHOOT, not its id alone (review of 42fdc47): a shoot
            // whose times or venue changed is an edit as much as a changed line.
            shoots = invoice.shoots
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map(ShootSnapshot.init)
            lineItems = invoice.lineItems
                .sorted { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
                .map(LineSnapshot.init)
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
