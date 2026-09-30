import Foundation
import Testing

/// ovation#67. The invoice list and the sales lines are two reports of one set of
/// invoices, and they are reconciled by invoice number before anything is
/// believed.
///
/// MEASURED, ovation#66: the lines cover 33 invoice numbers and the list 31, and
/// no tax column exports, so tax shows only as a difference between an
/// invoice's lines and its total. A difference is NAMED, carrying its amount,
/// and never absorbed into a plausible invoice.
struct QuickBooksReconciliationTests {

    private typealias F = QuickBooksFixture

    private static func reconcile(invoices: [String], invoicesTotal: String,
                                  lines: [String], linesTotal: String) -> QuickBooksReconciliation {
        let list = QuickBooksExport.invoiceList(F.invoiceList(invoices, total: invoicesTotal))
        let sales = QuickBooksExport.salesLines(F.salesLines(lines, total: linesTotal))
        return QuickBooksReconciliation.reconcile(invoices: list.accepted, lines: sales.accepted)
    }

    @Test("an invoice whose lines sum to its total is agreed, carrying its lines")
    func linesThatSumAreAgreed() throws {
        let result = Self.reconcile(
            invoices: [F.invoice(number: "1001", amount: "475.00")], invoicesTotal: "$475.00",
            lines: [F.line(number: "1001", amount: "400.00"), F.line(number: "1001", amount: "75.00"),
                    F.groupTotal("--", amount: "$475.00")],
            linesTotal: "$475.00")
        #expect(result.refusals.isEmpty)
        let agreed = try #require(result.agreed.first)
        #expect(agreed.invoice.number == 1001)
        #expect(agreed.lines.map(\.row) == [6, 7])
    }

    @Test("lines that do not sum to the total are refused carrying the difference, which is where tax shows")
    func aDifferenceIsNamedWithItsAmount() {
        let result = Self.reconcile(
            invoices: [F.invoice(number: "1001", amount: "108.88"), F.invoice(number: "1002", amount: "50.00")],
            invoicesTotal: "$158.88",
            lines: [F.line(number: "1001", amount: "100.00"), F.line(number: "1002", amount: "50.00"),
                    F.groupTotal("--", amount: "$150.00")],
            linesTotal: "$150.00")
        #expect(result.agreed.map(\.invoice.number) == [1002])
        #expect(result.refusals == [
            QuickBooksReconciliation.Refusal(number: 1001, invoiceRow: 6, lineRows: [6],
                                             reason: .linesDoNotSumToTotal(difference: Money(cents: 888))),
        ])
    }

    @Test("a number in only one of the two files is refused by name, whichever file it is in")
    func aNumberInOneFileOnlyIsRefused() {
        let result = Self.reconcile(
            invoices: [F.invoice(number: "1001", amount: "100.00"), F.invoice(number: "1003", amount: "20.00")],
            invoicesTotal: "$120.00",
            lines: [F.line(number: "1001", amount: "100.00"), F.line(number: "0998", amount: "30.00"),
                    F.line(number: "0998", amount: "5.00"), F.groupTotal("--", amount: "$135.00")],
            linesTotal: "$135.00")
        #expect(result.agreed.map(\.invoice.number) == [1001])
        #expect(result.refusals == [
            QuickBooksReconciliation.Refusal(number: 998, invoiceRow: nil, lineRows: [7, 8], reason: .onlyInSalesLines),
            QuickBooksReconciliation.Refusal(number: 1003, invoiceRow: 7, lineRows: [], reason: .onlyInInvoiceList),
        ])
    }
}
