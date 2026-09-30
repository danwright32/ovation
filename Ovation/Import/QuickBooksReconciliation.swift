// ovation#67. The invoice list and the sales lines, reconciled by invoice number.
//
// TWO REPORTS OF ONE SET OF INVOICES, and neither is believed alone. The list
// carries each invoice's total and no lines; the lines report carries lines and
// no totals. MEASURED on the custody files (ovation#66): the lines cover 33
// invoice numbers and the list 31, so a number in one and not the other is a
// refusal naming it, never an invoice made up from whichever half exists.
//
// A DIFFERENCE IS NAMED, NOT ABSORBED. No tax column exports, even with tax
// columns requested, so tax shows only as the gap between an invoice's lines and
// its total. The refusal carries that gap as an amount, for Dan's own screen,
// because an invoice whose lines were quietly scaled to meet its total would be
// a plausible invoice nobody could tell from a correct one (L340).
import Foundation

struct QuickBooksReconciliation: Equatable, Sendable {

    /// An invoice whose accepted lines sum exactly to its total.
    struct Agreed: Equatable, Sendable {
        let invoice: QuickBooksInvoiceRow
        let lines: [QuickBooksLineRow]
    }

    struct Refusal: Equatable, Sendable {
        let number: Int64
        /// The invoice list row, where the number has one.
        let invoiceRow: Int?
        /// The sales lines rows carrying the number, in file order.
        let lineRows: [Int]
        let reason: Reason
    }

    enum Reason: Equatable, Sendable {
        /// Accepted lines carry the number and no accepted invoice does.
        case onlyInSalesLines
        /// An accepted invoice carries the number and no accepted line does.
        case onlyInInvoiceList
        /// The invoice total minus the sum of its lines, which is where tax shows.
        case linesDoNotSumToTotal(difference: Money)
    }

    let agreed: [Agreed]
    let refusals: [Refusal]

    /// Over ACCEPTED rows only, and the reasons say so: a number whose lines were
    /// all refused reads as having no accepted line, which is what was measured,
    /// rather than as having none in the file (L11).
    static func reconcile(invoices: [QuickBooksInvoiceRow], lines: [QuickBooksLineRow]) -> QuickBooksReconciliation {
        let linesByNumber = Dictionary(grouping: lines, by: \.number)
        let invoiceByNumber = Dictionary(invoices.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })

        var agreed: [Agreed] = []
        var refusals: [Refusal] = []
        for number in Set(linesByNumber.keys).union(invoiceByNumber.keys).sorted() {
            let itsLines = (linesByNumber[number] ?? []).sorted { $0.row < $1.row }
            let lineRows = itsLines.map(\.row)
            guard let invoice = invoiceByNumber[number] else {
                refusals.append(Refusal(number: number, invoiceRow: nil, lineRows: lineRows, reason: .onlyInSalesLines))
                continue
            }
            guard !itsLines.isEmpty else {
                refusals.append(Refusal(number: number, invoiceRow: invoice.row, lineRows: [],
                                        reason: .onlyInInvoiceList))
                continue
            }
            let difference = invoice.amount - Money.sum(of: itsLines.map(\.amount))
            if difference == .zero {
                agreed.append(Agreed(invoice: invoice, lines: itsLines))
            } else {
                refusals.append(Refusal(number: number, invoiceRow: invoice.row, lineRows: lineRows,
                                        reason: .linesDoNotSumToTotal(difference: difference)))
            }
        }
        return QuickBooksReconciliation(agreed: agreed, refusals: refusals)
    }
}
