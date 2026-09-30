import Foundation
import Testing

/// ovation#72. The report of an import run: rows read, accepted and refused per
/// file, a reason for every refusal, and what was written, in output that obeys
/// docs/PRIVACY-FLOOR.md.
///
/// PRINTED OUTPUT IS THE PRIVACY HALF THAT BIT (docs/PRIVACY-FLOOR.md, L222), so
/// the report carries row numbers, field names, counts and reasons, and never a
/// client name, a description, an invoice number or an amount. The typed run
/// keeps every value for Dan's own screen.
struct QuickBooksImportReportTests {

    private typealias F = QuickBooksFixture

    private static let names = ["Fictive", "Quartet", "\u{00C9}lan", "Imaginary", "Opera"]
    private static let values = ["1,234.56", "1234.56", "108.88", "100.00", "8.88", "1001", "1002", "0998"]

    private static func run(basis: String = "Accrual Basis") -> QuickBooksImportRun {
        QuickBooksImportRun(
            invoiceList: QuickBooksExport.invoiceList(F.invoiceList([
                F.invoice(number: "1001", name: "\"Fictive, Quartet\"", amount: "108.88"),
                F.invoice("12/31/2025", number: "0998", name: "=Imaginary Opera", amount: "25.68"),
                F.invoice(number: "1002", name: "Ensemble \u{00C9}lan Fictif", amount: "\"1,100.00\""),
            ], total: "\"$1,234.56\"")),
            payments: QuickBooksExport.payments(F.payments([
                F.payment(name: "\"Fictive, Quartet\"", amount: "\"1,234.56\""),
            ], total: "\"$1,234.56\"")),
            salesLines: QuickBooksExport.salesLines(F.salesLines([
                F.line(number: "1001", client: "\"Fictive, Quartet\"", description: "Imaginary gala",
                       amount: "100.00"),
                F.line(number: "1002", client: "Ensemble \u{00C9}lan Fictif", quantity: "2.00",
                       price: "400.00", amount: "\"1,100.00\""),
                F.groupTotal("--", amount: "\"$1,200.00\""),
            ], total: "\"$1,200.00\"", basis: basis)),
            invoicesAndPayments: Self.ledger)
    }

    private static let ledger = QuickBooksExport.invoicesAndPayments(F.invoicesAndPayments([
        F.client("\"Fictive, Quartet\""),
        F.ledgerInvoice(number: "1001", amount: "108.88"), F.ledgerPayment(amount: "108.88"),
        F.client("Ensemble \u{00C9}lan Fictif"),
        F.ledgerInvoice(number: "1002", amount: "\"1,100.00\""), F.ledgerPayment(amount: "\"1,000.00\""),
    ]))

    @Test("each file reports rows read, accepted and refused, and each refusal its row and reason")
    func eachFileReportsItsCounts() {
        let text = Self.run().report.joined(separator: "\n")
        #expect(text.contains("quickbooks-invoice-list-2026-09-29.csv: 3 read, 2 accepted, 1 refused"))
        #expect(text.contains("row 7: Date is before 2026-01-01, outside Ovation's record"))
        #expect(text.contains("quickbooks-sales-lines-accrual-2026-09-30.csv: 2 read, 1 accepted, 1 refused"))
        #expect(text.contains("row 7: Amount is not Quantity times Sales price"))
        #expect(text.contains("quickbooks-payments-2026-09-29.csv: 1 read, 1 accepted, 0 refused"))
    }

    @Test("each reason carries a count, so a class of refusal reads as one line")
    func reasonsAreCounted() {
        let text = Self.run().report.joined(separator: "\n")
        #expect(text.contains("refused before 2026: 1"))
        #expect(text.contains("refused amount is not quantity times price: 1"))
    }

    @Test("the reconciliation names what it refused by the rows in each file")
    func theReconciliationIsReportedByRow() {
        let text = Self.run().report.joined(separator: "\n")
        #expect(text.contains("reconciliation by invoice number: 0 agree, 2 refused"))
        #expect(text.contains("invoice list row 6, sales lines row 6: the lines do not sum to the invoice total"))
        #expect(text.contains("invoice list row 8: no accepted line in the sales lines file"))
    }

    @Test("a refused file says so first, and the reconciliation says it did not run")
    func aRefusedFileIsSaidFirst() {
        let lines = Self.run(basis: "Cash Basis").report
        let text = lines.joined(separator: "\n")
        #expect(text.contains("quickbooks-sales-lines-accrual-2026-09-30.csv: REFUSED, the report is on cash basis"))
        #expect(text.contains("reconciliation by invoice number: not run, the sales lines file was refused"))
    }

    @Test("an unchecked TOTAL is said as a refusal, never as a note beside accepted rows")
    func anUncheckedTotalIsARefusal() {
        let run = QuickBooksImportRun(
            invoiceList: QuickBooksExport.invoiceList(F.invoiceList([
                F.invoice(number: "1001", amount: "twelve"),
            ], total: "\"$1,234.56\"")),
            payments: QuickBooksExport.payments(F.payments([F.payment(amount: "\"1,234.56\"")],
                                                           total: "\"$1,234.56\"")),
            salesLines: QuickBooksExport.salesLines(F.salesLines([
                F.line(number: "1001", amount: "100.00"), F.groupTotal("--", amount: "$100.00"),
            ], total: "$100.00")),
            invoicesAndPayments: Self.ledger)
        let text = run.report.joined(separator: "\n")
        #expect(text.contains("REFUSED, the TOTAL could not be compared, 1 rows have no readable amount"))
        #expect(text.contains("reconciliation by invoice number: not run, the invoice list was refused"))
    }

    @Test("nothing written is said as nothing written, never as a zero that reads like success")
    func nothingWrittenIsSaid() {
        // L98. This build parses and reconciles; the store write is ovation#68 to
        // ovation#70. A report that said "0 written" would read the same as a run
        // where everything was already imported.
        let text = Self.run().report.joined(separator: "\n")
        #expect(text.contains("written: nothing, this build reads and reconciles only"))
        #expect(text.contains("already imported: not checked, nothing reads the store yet"))
        #expect(!text.contains("0 written"))
    }

    @Test("payments are tied to an invoice only where the client holds one, and every other case is named by row")
    func paymentsAreTiedByRow() {
        let text = Self.run().report.joined(separator: "\n")
        #expect(text.contains("quickbooks-invoices-and-payments-2026-09-30.csv: 4 read, 4 accepted, 0 refused"))
        #expect(text.contains("this report exports no TOTAL"))
        #expect(text.contains("payments by invoice: 1 invoices tied, 1 refused"))
        #expect(text.contains("invoice list row 8, invoices and payments rows 10, 11, client heading row 9: "
                              + "the payments do not add up to what the invoice was paid"))
    }

    @Test("payments say why they are not matched to invoices")
    func paymentsSayWhyTheyAreNotMatched() {
        let text = Self.run().report.joined(separator: "\n")
        #expect(text.contains("payments not matched to invoices: 1 of 1 carry no invoice number"))
    }

    @Test("the report prints no client name, description, invoice number or amount")
    func theReportObeysThePrivacyFloor() {
        // SEEN TO FAIL: the fixture carries every one of these values, so a render
        // that printed a name or an amount has something to leak.
        for basis in ["Accrual Basis", "Cash Basis"] {
            let text = Self.run(basis: basis).report.joined(separator: "\n")
            for needle in Self.names + Self.values {
                #expect(!text.contains(needle), "the report printed \(needle.count) characters it must not")
            }
        }
    }
}
