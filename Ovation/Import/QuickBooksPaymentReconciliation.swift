// Payments tied to invoices, from the Invoices and Received Payments report
// (Dan, 2026-09-30), checked against the invoice list.
//
// WHAT THE FILE CAN SAY, MEASURED before this was written. It groups rows by
// CLIENT, and a payment carries no transaction number, so a payment belongs to
// a client and to an invoice only where that client's group holds exactly one.
// Where a group holds several, which payment paid which invoice is not in the
// file, and it is named as a group this file cannot tie rather than split by a
// rule the file does not state: splitting by date or by amount would produce a
// plausible allocation nobody could tell from a recorded one (L340).
//
// WHAT "PAID" MEANS HERE. An invoice's amount paid is its total minus its open
// balance on the invoice list. A tie is claimed only where the payments under it
// add up to exactly that, so a payment missing from this report, or one that
// belongs to another invoice, shows as a named difference.
import Foundation

struct QuickBooksPaymentReconciliation: Equatable, Sendable {

    struct Tied: Equatable, Sendable {
        let invoice: QuickBooksInvoiceRow
        let payments: [QuickBooksLedgerRow]
    }

    struct Refusal: Equatable, Sendable {
        /// The client heading row in the payments report, where one applies.
        let groupRow: Int?
        /// Invoice list rows involved.
        let invoiceListRows: [Int]
        /// Payments report rows involved, invoices and payments, in file order.
        let ledgerRows: [Int]
        let reason: Reason
    }

    enum Reason: Equatable, Sendable {
        /// An accepted invoice list invoice the payments report does not carry.
        case invoiceNotInPaymentsReport
        /// An invoice in the payments report the invoice list does not carry.
        case onlyInPaymentsReport
        /// The invoice list total minus the payments report's amount.
        case amountDiffersFromInvoiceList(difference: Money)
        /// What the invoice list says was paid, minus the payments under it.
        case paymentsDoNotMatchAmountPaid(difference: Money)
        /// The client group holds several invoices, so this file does not say
        /// which payment paid which. Whether the group's payments add up to
        /// what its invoices were paid is said, so a whole group that agrees
        /// reads differently from one that does not.
        case paymentsNotTiedToOneInvoice(invoices: Int, payments: Int, groupAgrees: Bool)
        /// Payments under a client with no accepted invoice in scope, for
        /// example one whose only invoices were dated 2025.
        case paymentsWithNoInvoice
        /// Payments under a client one of whose invoices was refused above, so
        /// nothing under that client can be tied.
        case groupHoldsAnInvoiceThatDoesNotReconcile
    }

    let tied: [Tied]
    let refusals: [Refusal]

    static func reconcile(invoices: [QuickBooksInvoiceRow],
                          ledger: [QuickBooksLedgerRow]) -> QuickBooksPaymentReconciliation {
        let listByNumber = Dictionary(invoices.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        let ledgerInvoices = ledger.filter { $0.kind == .invoice }
        let ledgerNumbers = Set(ledgerInvoices.compactMap(\.number))

        var refusals: [(Int64, Refusal)] = []
        var unsound = Set<Int>()
        for number in Set(listByNumber.keys).union(ledgerNumbers).sorted() {
            let listed = listByNumber[number]
            let carried = ledgerInvoices.filter { $0.number == number }
            switch (listed, carried.first) {
            case (let listed?, nil):
                refusals.append((number, Refusal(groupRow: nil, invoiceListRows: [listed.row], ledgerRows: [],
                                                 reason: .invoiceNotInPaymentsReport)))
            case (nil, let row?):
                unsound.insert(row.groupRow)
                refusals.append((number, Refusal(groupRow: row.groupRow, invoiceListRows: [],
                                                 ledgerRows: carried.map(\.row), reason: .onlyInPaymentsReport)))
            case (let listed?, let row?):
                let difference = listed.amount - row.amount
                if difference != .zero || carried.count > 1 {
                    unsound.insert(row.groupRow)
                    refusals.append((number, Refusal(groupRow: row.groupRow, invoiceListRows: [listed.row],
                                                     ledgerRows: carried.map(\.row),
                                                     reason: .amountDiffersFromInvoiceList(difference: difference))))
                }
            case (nil, nil):
                break
            }
        }

        var tied: [Tied] = []
        var groupRefusals: [Refusal] = []
        let groups = Dictionary(grouping: ledger, by: \.groupRow)
        for groupRow in groups.keys.sorted() {
            let rows = (groups[groupRow] ?? []).sorted { $0.row < $1.row }
            let payments = rows.filter { $0.kind == .payment }
            let groupInvoices = rows.filter { $0.kind == .invoice }.compactMap { row in
                row.number.flatMap { listByNumber[$0] }
            }
            let paid = groupInvoices.map { $0.amount - $0.openBalance }
            let received = Money.sum(of: payments.map(\.amount))
            let everyRow = rows.map(\.row)
            let listRows = groupInvoices.map(\.row).sorted()

            if unsound.contains(groupRow) {
                if !payments.isEmpty {
                    groupRefusals.append(Refusal(groupRow: groupRow, invoiceListRows: listRows, ledgerRows: everyRow,
                                                 reason: .groupHoldsAnInvoiceThatDoesNotReconcile))
                }
                continue
            }
            switch groupInvoices.count {
            case 0:
                if !payments.isEmpty {
                    groupRefusals.append(Refusal(groupRow: groupRow, invoiceListRows: [],
                                                 ledgerRows: payments.map(\.row), reason: .paymentsWithNoInvoice))
                }
            case 1:
                let difference = paid[0] - received
                if difference == .zero {
                    tied.append(Tied(invoice: groupInvoices[0], payments: payments))
                } else {
                    groupRefusals.append(Refusal(groupRow: groupRow, invoiceListRows: listRows, ledgerRows: everyRow,
                                                 reason: .paymentsDoNotMatchAmountPaid(difference: difference)))
                }
            default:
                // Nothing to allocate when nothing was paid and nothing received.
                if payments.isEmpty && paid.allSatisfy({ $0 == .zero }) {
                    tied += groupInvoices.map { Tied(invoice: $0, payments: []) }
                } else {
                    groupRefusals.append(Refusal(
                        groupRow: groupRow, invoiceListRows: listRows, ledgerRows: everyRow,
                        reason: .paymentsNotTiedToOneInvoice(invoices: groupInvoices.count, payments: payments.count,
                                                             groupAgrees: Money.sum(of: paid) == received)))
                }
            }
        }
        return QuickBooksPaymentReconciliation(tied: tied, refusals: refusals.map(\.1) + groupRefusals)
    }
}
