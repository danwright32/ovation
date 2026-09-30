import Foundation
import Testing

/// The Invoices and Received Payments report (Dan, 2026-09-30), and what it can
/// and cannot say about which invoice a payment paid.
///
/// MEASURED on the custody file before this was written, shape only: rows are
/// grouped by CLIENT, a payment carries no transaction number, and the report
/// exports no TOTAL. So a payment belongs to a client, and to an invoice only
/// where its client group holds exactly one. A group holding several invoices
/// is named as one whose payments this file cannot tie, never split across its
/// invoices by a rule the file does not state (L340).
struct QuickBooksInvoicesAndPaymentsTests {

    private typealias F = QuickBooksFixture

    // MARK: reading

    @Test("rows read into invoices and payments under the client heading they sit in")
    func rowsReadUnderTheirClient() throws {
        let read = QuickBooksExport.invoicesAndPayments(F.invoicesAndPayments([
            F.client("\"Fictive, Quartet\""),
            F.ledgerInvoice(number: "1001", amount: "\"1,000.00\""),
            F.ledgerPayment("1/25/2026", amount: "\"1,000.00\""),
            F.client("Ensemble \u{00C9}lan Fictif"),
            F.ledgerPayment("2/1/2026", amount: "50.00"),
            F.ledgerInvoice("2/2/2026", number: "1002", memo: "Imaginary gala", amount: "50.00"),
        ]))
        #expect(read.fileRefusals.isEmpty)
        #expect(read.totalCheck == .noneExported)
        #expect(read.isAccepted)
        #expect(read.rowsRead == 4)
        #expect(read.structureRows == 2)
        let first = try #require(read.accepted.first)
        #expect(first.kind == .invoice)
        #expect(first.number == 1001)
        #expect(first.client == "Fictive, Quartet")
        #expect(first.groupRow == 6)
        #expect(first.amount == Money(cents: 100_000))
        let payment = try #require(read.accepted.dropFirst(2).first)
        #expect(payment.kind == .payment)
        #expect(payment.number == nil)
        #expect(payment.groupRow == 9)
        #expect(read.accepted.last?.memo == "Imaginary gala")
    }

    @Test("an invoice without a number, a row outside any client and a 2025 row are each refused by name")
    func refusalsAreNamed() {
        let read = QuickBooksExport.invoicesAndPayments(F.invoicesAndPayments([
            F.ledgerInvoice(number: "1000"),
            F.client("Fictive Quartet"),
            F.ledgerInvoice(number: "", amount: "10.00"),
            F.ledgerInvoice("12/30/2025", number: "0998"),
            F.ledgerPayment(amount: "$10.00"),
            F.ledgerPayment(),
        ]))
        #expect(read.refused == [
            QuickBooksRowRefusal(row: 6, reason: .outsideAnyGroup),
            QuickBooksRowRefusal(row: 8, reason: .missing(field: "Transaction number")),
            QuickBooksRowRefusal(row: 9, reason: .beforeScope(field: "Date")),
            QuickBooksRowRefusal(row: 10, reason: .unreadableAmount(field: "Amount")),
        ])
        #expect(read.accepted.map(\.row) == [11])
    }

    @Test("a file that stops before its report timestamp is refused as cut short")
    func noTimestampIsNamed() {
        // With no TOTAL in this report, the timestamp line is the only mark that
        // the file reached its end (ovation#72).
        let read = QuickBooksExport.invoicesAndPayments(F.invoicesAndPayments([
            F.client("Fictive Quartet"), F.ledgerInvoice(),
        ], timestamp: false))
        #expect(read.fileRefusals == [.noTimestampLine])
        #expect(!read.isAccepted)
    }

    @Test("a file cut off on a client heading is not read as ending on its timestamp")
    func aHeadingIsNotATimestamp() {
        // A client heading has the timestamp's shape, one filled first column,
        // so only an empty line before it makes a line the timestamp.
        let cut = F.invoicesAndPayments([F.client("Fictive Quartet"), F.ledgerInvoice()], timestamp: false)
            .trimmingCharacters(in: .newlines) + "\r\n" + F.client("Imaginary Opera") + "\r\n"
        let read = QuickBooksExport.invoicesAndPayments(cut)
        #expect(read.fileRefusals == [.noTimestampLine])
    }

    // MARK: tying payments to invoices

    private static func list(_ rows: [String], total: String) -> [QuickBooksInvoiceRow] {
        QuickBooksExport.invoiceList(F.invoiceList(rows, total: total)).accepted
    }

    private static func ledger(_ rows: [String]) -> [QuickBooksLedgerRow] {
        QuickBooksExport.invoicesAndPayments(F.invoicesAndPayments(rows)).accepted
    }

    @Test("a client holding one invoice ties its payments to it when they add up to what was paid")
    func oneInvoiceTiesItsPayments() throws {
        let result = QuickBooksPaymentReconciliation.reconcile(
            invoices: Self.list([F.invoice(number: "1001", amount: "300.00", open: "50.00")], total: "$300.00"),
            ledger: Self.ledger([
                F.client("Fictive Quartet"), F.ledgerInvoice(number: "1001", amount: "300.00"),
                F.ledgerPayment(amount: "200.00"), F.ledgerPayment("2/1/2026", amount: "50.00"),
            ]))
        #expect(result.refusals.isEmpty)
        let tied = try #require(result.tied.first)
        #expect(tied.invoice.number == 1001)
        #expect(tied.payments.map(\.row) == [8, 9])
    }

    @Test("payments that do not add up to what one invoice was paid are refused carrying the difference")
    func paymentsThatDoNotAddUpAreRefused() {
        let result = QuickBooksPaymentReconciliation.reconcile(
            invoices: Self.list([F.invoice(number: "1001", amount: "300.00")], total: "$300.00"),
            ledger: Self.ledger([
                F.client("Fictive Quartet"), F.ledgerInvoice(number: "1001", amount: "300.00"),
                F.ledgerPayment(amount: "200.00"),
            ]))
        #expect(result.tied.isEmpty)
        #expect(result.refusals == [
            QuickBooksPaymentReconciliation.Refusal(
                groupRow: 6, invoiceListRows: [6], ledgerRows: [7, 8],
                reason: .paymentsDoNotMatchAmountPaid(difference: Money(cents: 10_000))),
        ])
    }

    @Test("a client holding several invoices is named as one this file cannot tie, and says whether its total agrees")
    func severalInvoicesAreNotSplitByGuess() {
        let result = QuickBooksPaymentReconciliation.reconcile(
            invoices: Self.list([F.invoice(number: "1001", amount: "100.00"),
                                 F.invoice(number: "1002", amount: "200.00")], total: "$300.00"),
            ledger: Self.ledger([
                F.client("Fictive Quartet"),
                F.ledgerInvoice(number: "1001", amount: "100.00"), F.ledgerInvoice(number: "1002", amount: "200.00"),
                F.ledgerPayment(amount: "300.00"),
            ]))
        #expect(result.tied.isEmpty)
        #expect(result.refusals == [
            QuickBooksPaymentReconciliation.Refusal(
                groupRow: 6, invoiceListRows: [6, 7], ledgerRows: [7, 8, 9],
                reason: .paymentsNotTiedToOneInvoice(invoices: 2, payments: 1, groupAgrees: true)),
        ])
    }

    @Test("an invoice in one file and not the other, or at another amount, is named by row")
    func invoicesThatDoNotMatchTheListAreNamed() {
        let result = QuickBooksPaymentReconciliation.reconcile(
            invoices: Self.list([F.invoice(number: "1001", amount: "100.00"),
                                 F.invoice(number: "1003", amount: "20.00")], total: "$120.00"),
            ledger: Self.ledger([
                F.client("Fictive Quartet"), F.ledgerInvoice(number: "1001", amount: "90.00"),
                F.client("Imaginary Opera"), F.ledgerInvoice(number: "1004", amount: "5.00"),
                F.ledgerPayment(amount: "5.00"),
            ]))
        #expect(result.tied.isEmpty)
        #expect(result.refusals.map(\.reason) == [
            .amountDiffersFromInvoiceList(difference: Money(cents: 1_000)),
            .invoiceNotInPaymentsReport,
            .onlyInPaymentsReport,
            .groupHoldsAnInvoiceThatDoesNotReconcile,
        ])
        // A client with nothing to tie (no payments) raises nothing about its group.
        #expect(result.refusals.last?.groupRow == 8)
    }

    @Test("one invoice number under two clients is refused by name, and neither client's payments are tied")
    func oneNumberUnderTwoClientsIsAmbiguous() {
        // L521. Two rows carrying one number is not the invoice twice; which
        // client it belongs to is not something the file settles.
        let result = QuickBooksPaymentReconciliation.reconcile(
            invoices: Self.list([F.invoice(number: "1001", amount: "100.00")], total: "$100.00"),
            ledger: Self.ledger([
                F.client("Fictive Quartet"), F.ledgerInvoice(number: "1001", amount: "100.00"),
                F.ledgerPayment(amount: "100.00"),
                F.client("Imaginary Opera"), F.ledgerInvoice(number: "1001", amount: "100.00"),
                F.ledgerPayment(amount: "100.00"),
            ]))
        #expect(result.tied.isEmpty)
        #expect(result.refusals.map(\.reason) == [
            .numberUnderSeveralRows,
            .groupHoldsAnInvoiceThatDoesNotReconcile,
            .groupHoldsAnInvoiceThatDoesNotReconcile,
        ])
        #expect(result.refusals.first?.ledgerRows == [7, 10])
    }

    @Test("a number the invoice list lacks, carried under two clients, is refused as ambiguous and taints both")
    func anUnlistedNumberUnderTwoClientsIsAmbiguous() {
        let result = QuickBooksPaymentReconciliation.reconcile(
            invoices: [],
            ledger: Self.ledger([
                F.client("Fictive Quartet"), F.ledgerInvoice(number: "1009", amount: "100.00"),
                F.ledgerPayment(amount: "100.00"),
                F.client("Imaginary Opera"), F.ledgerInvoice(number: "1009", amount: "100.00"),
                F.ledgerPayment(amount: "100.00"),
            ]))
        #expect(result.refusals.map(\.reason) == [
            .numberUnderSeveralRows,
            .groupHoldsAnInvoiceThatDoesNotReconcile,
            .groupHoldsAnInvoiceThatDoesNotReconcile,
        ])
        #expect(result.refusals.first?.ledgerRows == [7, 10])
    }

    @Test("payments under a client with no invoice in scope are refused, not dropped")
    func paymentsWithNoInvoiceAreRefused() {
        let result = QuickBooksPaymentReconciliation.reconcile(
            invoices: [],
            ledger: Self.ledger([
                F.client("Fictive Quartet"), F.ledgerInvoice("12/30/2025", number: "0998"),
                F.ledgerPayment(amount: "100.00"),
            ]))
        #expect(result.refusals == [
            QuickBooksPaymentReconciliation.Refusal(groupRow: 6, invoiceListRows: [], ledgerRows: [8],
                                                    reason: .paymentsWithNoInvoice),
        ])
    }
}
