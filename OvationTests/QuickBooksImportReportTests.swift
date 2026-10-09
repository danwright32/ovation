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

    @Test("a run that only read says it wrote nothing, never a zero that reads like success")
    func nothingWrittenIsSaid() {
        // L98. A run that read and reconciled and never reached the store says so,
        // because "0 written" would read the same as a run where everything was
        // already imported.
        let text = Self.run().report.joined(separator: "\n")
        #expect(text.contains("written: nothing, this run read and reconciled the files and did not write"))
        #expect(text.contains("already imported: not checked, this run did not read the store"))
        #expect(!text.contains("0 written"))
    }

    // MARK: after the write (ovation#72)

    private typealias Spec = QuickBooksImportFixture.Spec

    @Test("every invoice read is counted once: written, already imported or refused")
    func theFourNumbersPartitionTheInvoices() async throws {
        // Three agree with each other, and one of them carries a client Ovation
        // does not hold, so it is refused at the write.
        let container = try QuickBooksImportFixture.store()
        let base = [Spec(number: "1041"), Spec(number: "1042", client: "Imaginary Opera"),
                    Spec(number: "1043", paidCents: 5_000)]
        let run = QuickBooksImportFixture.run(base)
        let write = try await QuickBooksImportFixture.write(run, into: container)

        let text = run.report(after: write).joined(separator: "\n")
        #expect(text.contains("invoices: 3 read, 2 written, 0 already imported, 1 refused"))
        #expect(text.contains("written: 2 invoices and 2 payments, as import batch \(write.batch.uuidString)"))
        #expect(text.contains("  invoice list row 7: no client in Ovation carries the name QuickBooks billed"))
    }

    @Test("a second run says every invoice was already imported, never that it wrote nothing")
    func asecondRunSaysAlreadyImported() async throws {
        let container = try QuickBooksImportFixture.store()
        let run = QuickBooksImportFixture.run([Spec(number: "1041"), Spec(number: "1042")])
        try await QuickBooksImportFixture.write(run, into: container)
        let again = try await QuickBooksImportFixture.write(run, into: container)

        let text = run.report(after: again).joined(separator: "\n")
        #expect(text.contains("invoices: 2 read, 0 written, 2 already imported, 0 refused"))
        #expect(text.contains("written: nothing, every invoice was already imported"))
        #expect(text.contains("already imported: invoice list rows 6, 7"))
    }

    @Test("a run that wrote nothing because everything was refused says that instead")
    func aRunWhereEverythingWasRefusedSaysSo() async throws {
        let container = try QuickBooksImportFixture.store(clients: [])
        let run = QuickBooksImportFixture.run([Spec(number: "1041")])
        let write = try await QuickBooksImportFixture.write(run, into: container)

        let text = run.report(after: write).joined(separator: "\n")
        #expect(text.contains("written: nothing, every invoice was refused"))
    }

    @Test("an invoice list refused as a whole is said as refused, never as a file with nothing in it")
    func aRefusedListIsNotAnEmptyOne() async throws {
        // REVIEW OF 3a6ef9e (L11): a refused file reads zero rows, and "no rows to
        // import" would describe it as empty, which nothing measured.
        let container = try QuickBooksImportFixture.store()
        let good = QuickBooksImportFixture.run([Spec(number: "1041")])
        let run = QuickBooksImportRun(invoiceList: QuickBooksExport.invoiceList("not the measured report\r\n"),
                                      payments: good.payments, salesLines: good.salesLines,
                                      invoicesAndPayments: good.invoicesAndPayments)
        let write = try await QuickBooksImportFixture.write(run, into: container)

        let text = run.report(after: write).joined(separator: "\n")
        #expect(text.contains("written: nothing, the invoice list was refused as a whole, so none of it was imported"))
        #expect(!text.contains("no rows to import"))
    }

    @Test("a number already held is named by its row, and the number itself stays off the report")
    func aHeldNumberIsReportedByRow() async throws {
        let container = try QuickBooksImportFixture.store()
        let run = QuickBooksImportFixture.run([Spec(number: "1041")])
        try await QuickBooksImportFixture.write(run, into: container, version: 1)
        let corrected = try await QuickBooksImportFixture.write(run, into: container, version: 2)

        let text = run.report(after: corrected).joined(separator: "\n")
        #expect(text.contains("  invoice list row 6: another invoice in Ovation already holds its number"))
        #expect(!text.contains("1041"))
    }

    @Test("the report after a write prints no client name, invoice number or amount")
    func theReportAfterAWriteObeysThePrivacyFloor() async throws {
        let container = try QuickBooksImportFixture.store(clients: [("Fictive Quartet", .notExempt)])
        let run = QuickBooksImportFixture.run([Spec(number: "1041", paidCents: 4_000),
                                               Spec(number: "1042", client: "Imaginary Opera")])
        let write = try await QuickBooksImportFixture.write(run, into: container)
        #expect(!write.refused.isEmpty, "a refusal with nothing to leak measures nothing")

        let text = run.report(after: write).joined(separator: "\n")
        for needle in ["Fictive", "Imaginary", "1041", "1042", "100.00", "40.00", "108.88"] {
            #expect(!text.contains(needle), "the report printed \(needle.count) characters it must not")
        }
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
