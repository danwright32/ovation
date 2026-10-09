// ovation#556, PRD 51d and 51o. What the system did to one invoice, one sentence a
// line, in the order it happened.
//
// EVERY ENTRY IS READ FROM THE STORE, never inferred. PRD 51d settled the wording as
// what the SYSTEM did (`Draft created`, `Sent`, `Payment recorded`, `Cleared`), kept
// against the same events said as what happened, and each entry here is a field the
// store actually holds: `Invoice.createdOn`, `SentStatus`, each allocation and its
// payment, a check's `clearedOn`, a release, a refund and the invoice's closure.
//
// EACH MESSAGE SENT IS LISTED FROM ITS OWN RECORD (ovation#596, schema version 7):
// the send that issued the invoice says who it went to, and every reminder and copy
// is an entry of its own, on the day Gmail accepted it, with who it went to as it
// left rather than the client's CURRENT addresses, which are a different fact that
// can have changed since (L443).
//
// A FACT THAT WAS NEVER RECORDED IS SAID TO BE MISSING, not drawn from a neighbour
// (L192). Two can be missing and both are named in `unrecorded`: the day an invoice
// written before schema version 4 was created (ovation#553), and who an invoice
// sent before version 7 (or found in the mailbox) first went to, together with any
// reminder or copy sent before version 7, which wrote nothing. Such a `Sent` carries
// no address rather than the client's.
//
// IT HOLDS NO CONTEXT AND WRITES NOTHING, for the reason the presenter it feeds
// gives (PRD 51l).
import Foundation

struct InvoiceHistory: Equatable {

    /// One line of the pane: when, what the system did, and a quieter line beneath.
    struct Entry: Identifiable, Equatable {
        /// Stable across re-reads of the same record, so the payment just recorded
        /// can be found again after the screen is rebuilt (PRD 51o, L15).
        let id: String
        /// "26 Sep", or empty where the day cannot be read (L11).
        let when: String
        let what: String
        let more: String?
        /// Whether this is a payment, the one kind Record marks (PRD 51o).
        let isPayment: Bool
    }

    let entries: [Entry]
    /// What this invoice's history cannot say because it was never recorded, each
    /// one sentence, said beneath the entries rather than guessed at.
    let unrecorded: [String]

    static let creationNotRecorded = "The day this invoice was created was not recorded."
    static let firstSendNotRecorded = "Who this invoice first went to was not recorded, and neither was any reminder or copy sent before Ovation began recording them."

    init(_ invoice: Invoice) {
        var found: [Sortable] = []

        if let created = invoice.createdOn {
            // FROM A BOOKING where any of its shoots carries one, which is the
            // shoot's own key rather than the invoice's, since `Shoot.bookingKey` is
            // that key's home (ovation#461).
            let fromBooking = invoice.shoots.contains { $0.bookingKey != nil }
            found.append(Sortable(day: created, rank: 0, id: "created", what: "Draft created",
                                  more: fromBooking ? "from a Downbeat booking" : nil))
        }

        let issuing = invoice.issuingMessage
        switch invoice.sentStatus {
        case .sent(let route, let at):
            let more: String?
            switch route {
            case .foundInTheMailbox: more = "found in Gmail's Sent folder"
            case .billedInQuickBooks: more = "billed in QuickBooks"
            case .ovationSentIt: more = issuing.map { Self.goneTo($0.recipients) } ?? nil
            }
            found.append(Sortable(day: .stamping(at), rank: 1, id: "sent", what: "Sent", more: more))
        case .attempting(let attempt):
            found.append(Sortable(day: .stamping(attempt.startedAt), rank: 1, id: "sent",
                                  what: "Send started", more: "Gmail has not said whether it went"))
        // THE MAILBOX MATCH LOOKING IS NOT A SEND, and a draft has nothing to say.
        case .notSent, .couldNotDetermine:
            break
        }

        // EVERY REMINDER AND COPY, each from its own record. The send that issued
        // the invoice is the `Sent` above, whose day is the sent state's.
        for message in invoice.orderedSentMessages where message.kind != .invoice {
            found.append(Sortable(day: message.sentOn, rank: 1, id: "message-\(message.id.uuidString)",
                                  what: message.kind == .reminder ? "Reminder sent" : "Copy sent",
                                  more: Self.goneTo(message.recipients)))
        }

        var clearedPayments: Set<String> = []
        for allocation in invoice.allocations {
            let figure = "$" + PDFText.amount(allocation.amount)
            let key = allocation.id.uuidString
            if allocation.isHeldMoney {
                found.append(Sortable(day: allocation.allocatedOn, rank: 2, id: "held-\(key)",
                                      what: "Held money applied", more: figure))
            } else if let payment = allocation.payment {
                // ON THE DAY THE MONEY ARRIVED, which is the day the invoice's own
                // payment line says ("Paid 26 Sep by Zelle", PRD 51n), so the pane and
                // the line cannot name two different days for one payment.
                found.append(Sortable(day: payment.receivedOn, rank: 2, id: "payment-\(key)",
                                      what: "Payment recorded",
                                      more: figure + " by " + payment.method.inASentence,
                                      isPayment: true))
                // ONE CLEARED ENTRY PER CHECK, however many of its allocations are on
                // this invoice, because clearing belongs to the payment (PRD 5.15).
                let paymentKey = payment.id.uuidString
                if let cleared = payment.clearedOn, !clearedPayments.contains(paymentKey) {
                    clearedPayments.insert(paymentKey)
                    found.append(Sortable(day: cleared, rank: 3, id: "cleared-\(paymentKey)",
                                          what: "Cleared", more: nil))
                }
            }
            if let released = allocation.releasedOn {
                found.append(Sortable(day: released, rank: 4, id: "released-\(key)",
                                      what: allocation.isHeldMoney ? "Held money removed" : "Payment released",
                                      more: figure))
            }
        }

        for refund in invoice.refunds {
            found.append(Sortable(day: refund.refundedOn, rank: 5, id: "refund-\(refund.id.uuidString)",
                                  what: "Refund recorded", more: "$" + PDFText.amount(refund.amount)))
        }

        switch invoice.closure {
        case .cancelled(let on, _):
            found.append(Sortable(day: on, rank: 6, id: "closed", what: "Cancelled", more: nil))
        case .deleted(let on, _):
            found.append(Sortable(day: on, rank: 6, id: "closed", what: "Deleted", more: nil))
        case nil:
            break
        }

        // IN A DECLARED ORDER, never whatever the store returned (L343): by day, then
        // by the order events of one day happen in, then by identity so two payments
        // on one day always come out the same way.
        entries = found
            .sorted { ($0.day.dayKey, $0.rank, $0.day.instant, $0.id)
                    < ($1.day.dayKey, $1.rank, $1.day.instant, $1.id) }
            .map { Entry(id: $0.id, when: BusinessCalendar.dayAndMonth($0.day) ?? "",
                         what: $0.what, more: $0.more, isPayment: $0.isPayment) }

        var missing: [String] = []
        if invoice.createdOn == nil { missing.append(Self.creationNotRecorded) }
        if invoice.sentStatus.wasSent, issuing == nil { missing.append(Self.firstSendNotRecorded) }
        unrecorded = missing
    }

    /// "to a@b.example, c@d.example", or nil where no address was recorded.
    private static func goneTo(_ recipients: [String]) -> String? {
        recipients.isEmpty ? nil : "to " + recipients.joined(separator: ", ")
    }

    /// The payments in `after` that were not in `before`: what Record just wrote.
    ///
    /// BY IDENTITY, NEVER BY POSITION OR BY BEING LAST, because two payments on one
    /// day sort by identity and the new one is not necessarily at the end (L237).
    static func newlyRecorded(before: [Entry], after: [Entry]) -> Set<String> {
        let known = Set(before.map(\.id))
        return Set(after.filter { $0.isPayment && !known.contains($0.id) }.map(\.id))
    }

    private struct Sortable {
        let day: BusinessDate
        let rank: Int
        let id: String
        let what: String
        let more: String?
        var isPayment = false
    }
}
