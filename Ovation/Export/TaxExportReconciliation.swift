// ovation#63, PRD 23 to 25a. The completeness check, and the manifest that
// travels with each run.
//
// THE QUESTION IS NOT WHETHER THE EXPORT WROTE WITHOUT ERROR. It is whether
// everything that should be in it is in it, and those come apart exactly when it
// matters: a fetch that quietly returned fewer rows than the store holds, a row
// whose day key put it in a neighbouring year, an invoice whose client could not
// be resolved. Each leaves a CSV that is well formed, totals cleanly against its
// own parts, and is SHORT. Totalling is not proving: a sum checked against its
// own parts cannot see a row that never entered the export at all (L517).
//
// THE EXPECTATION COMES FROM A DIFFERENT POPULATION THAN THE ROWS, and that is
// the whole design. Comparing the export against the list that produced it is
// arithmetically always zero (L70). So `TaxExport` is handed whatever a fetch
// returned, and this is handed EVERY invoice, expense, payment and refund. The
// RULE they apply is one shared predicate, because a count and the rows it
// promises must come from one place (L16); the POPULATION is what differs, and a
// short fetch is what that difference catches.
//
// EVERY ABSENCE CARRIES A MEASURED REASON. A reconciliation that balances by
// summing named buckets is satisfied by the very defect it hunts, as long as the
// missing item lands in a bucket standing for legitimate cases (L540). So an
// invoice that is not a row is either matched to a rule that excludes it (a
// draft, an undetermined Sent, no date, another year) or it is a FINDING. There
// is no bucket meaning "did not match the good case".
//
// IT READS THE RENDERED ROWS rather than the selection, because a document built
// from the right invoices and rendered wrong is still a wrong file.
//
// PRIVACY. Findings and the manifest name invoices by NUMBER and by DAY KEY, never
// by client. This is the half that gets read out, pasted and logged; the CSV is
// the only thing that may carry a name (L222, docs/PRIVACY-FLOOR.md).
import Foundation

/// What travels beside the two files: what the run produced, and enough to
/// reproduce it in March.
struct TaxExportManifest: Codable, Equatable, Sendable {
    let firstDayKey: String
    let lastDayKey: String
    /// Which date decides the year, in words. PRD 9.3 is unanswered, so the
    /// choice travels with the export rather than being a fact about the code
    /// that produced it (L316).
    let dateRule: String

    let incomeRows: Int
    let incomeTotal: String
    let salesTax: String
    /// Invoices that could have been in this range and are not, by reason.
    /// Keyed by `IncomeOmission`'s raw value so the manifest reads as itself in
    /// a year's time.
    let notIncluded: [String: Int]

    let expenseRows: Int
    let expenseTotal: String
    let expensesNeedingACategory: Int

    /// Payments and refunds that belong to an invoice outside the range. Named
    /// here so that money in the store which is deliberately not on this return
    /// is accounted for rather than merely absent.
    let paymentsAgainstInvoicesOutsideTheRange: Int
    let refundsAgainstInvoicesOutsideTheRange: Int

    /// How many findings the reconciliation raised. A manifest carrying a count
    /// above zero describes a run that must not be handed to an accountant.
    let findings: Int
}

/// What the reconciliation found. Each case is a different piece of work, so
/// they are separate rather than one message with a reason string (L11).
enum TaxExportFinding: Equatable, Hashable, Sendable {
    /// An invoice the rule says belongs in the file, and the file has not got it.
    case missingFromIncome(invoiceNumber: Int64?, dayKey: String)
    /// It is in the file more than once, so the year totals to more income than
    /// exists.
    case duplicateIncomeRow(invoiceNumber: Int64)
    /// Its Sent was established and it has no number, so nothing can match it to
    /// a row. A real defect in the allocator rather than a problem with this
    /// check (ovation#37, ovation#133).
    case issuedWithoutANumber(dayKey: String)
    /// The count of expense rows and the count the store says there should be
    /// disagree. Expenses carry no number, so they are reconciled by count and
    /// by sum rather than by identity, and that is stated rather than implied.
    case expenseRowsDisagree(expected: Int, found: Int)
    case expenseTotalDisagrees(expected: String, found: String)
    /// Money that arrived and belongs to no invoice at all. Either nobody
    /// allocated it or its allocation was released and nobody redid it; both are
    /// money correctly sitting on a client until somebody decides where it goes.
    case paymentAttachedToNothing(dayKey: String)
    /// An allocation that still STANDS and whose invoice is gone (ovation#176).
    ///
    /// A DIFFERENT SITUATION FROM THE ONE ABOVE, and it used to report as it.
    /// `Invoice.allocations` is nullify, so deleting an invoice sets
    /// `PaymentAllocation.invoice` to nil and leaves the allocation active, with
    /// `releasedOn` still nil. Reading a payment's invoices through
    /// `compactMap(\.invoice)` then makes that allocation vanish, and the payment
    /// reported exactly as one nobody had ever allocated. One is money sitting on
    /// a client; this one is an allocation whose invoice was destroyed underneath
    /// it, which is a real corruption and needs a different fix, so the wrong
    /// diagnosis was being given for it (L11).
    ///
    /// IT CARRIES THE AMOUNT, which the case above cannot: how much money is
    /// standing against nothing is the first thing anybody will ask, and the
    /// payment's own total says nothing about which part of it is orphaned.
    case allocationOutlivedItsInvoice(dayKey: String, amount: String)
    case refundAttachedToNothing(dayKey: String)
    /// A source could not be read in full. A short read is a refusal, not a
    /// smaller export.
    case sourceCouldNotBeFullyRead(source: String, rowsNotConsulted: Int)
}

struct TaxExportReconciliation: Sendable {
    let manifest: TaxExportManifest
    let findings: [TaxExportFinding]
    let paymentsAgainstInvoicesOutsideTheRange: Int
    let refundsAgainstInvoicesOutsideTheRange: Int

    /// A run with no findings. Deliberately not called `isValid`: this says the
    /// export holds what the store says it should, and nothing about whether the
    /// numbers in it are right.
    var isComplete: Bool { findings.isEmpty }

    /// What may be printed: counts, never a name (L222).
    var summary: String {
        "\(manifest.firstDayKey) to \(manifest.lastDayKey): "
            + "\(manifest.incomeRows) income row(s), \(manifest.expenseRows) expense row(s), "
            + "\(findings.count) finding(s)"
    }

    /// - Parameters:
    ///   - income: the export as it was actually produced and rendered.
    ///   - everyInvoice: the WHOLE store's invoices, not the ones the export was
    ///     given. If the two are the same array the check degenerates into
    ///     proving the export self consistent, which is the trap this exists to
    ///     avoid (L70), so callers fetch this separately.
    ///   - couldNotBeFullyRead: how many rows each source could not consult. Any
    ///     entry refuses the run.
    static func check(
        income: IncomeExport,
        expenses: ExpenseExport,
        everyInvoice: [Invoice],
        everyExpense: [Expense],
        everyPayment: [Payment],
        everyRefund: [Refund],
        couldNotBeFullyRead: [String: Int] = [:]
    ) -> TaxExportReconciliation {
        var findings: [TaxExportFinding] = []

        // A SHORT READ FIRST, because everything below it is a statement about a
        // population that was not fully consulted. Sorted so the answer does not
        // depend on a dictionary's order.
        for source in couldNotBeFullyRead.keys.sorted() {
            findings.append(.sourceCouldNotBeFullyRead(
                source: source, rowsNotConsulted: couldNotBeFullyRead[source] ?? 0))
        }

        // What the RENDERED file holds, read back out of the document rather than
        // taken from the selection that built it.
        let renderedNumbers = renderedInvoiceNumbers(in: income.document)
        var seen: Set<Int64> = []
        for number in renderedNumbers {
            if seen.contains(number) {
                findings.append(.duplicateIncomeRow(invoiceNumber: number))
            }
            seen.insert(number)
        }

        // What the STORE says should be there, by the same rule and a different
        // population.
        let expected = TaxExport.included(from: everyInvoice, in: income.range)
        for invoice in expected {
            let dayKey = invoice.invoiceDate?.dayKey ?? ""
            guard let number = invoice.number else {
                findings.append(.issuedWithoutANumber(dayKey: dayKey))
                continue
            }
            if !seen.contains(number) {
                findings.append(.missingFromIncome(invoiceNumber: number, dayKey: dayKey))
            }
        }

        // EXPENSES CARRY NO NUMBER, so they are reconciled by count and by sum.
        // That is weaker than the invoice check and it is said out loud rather
        // than left to be assumed: two genuinely identical purchases on one day
        // are legitimate data, so an identity check over rendered values would
        // report a duplicate that is not one (L11).
        let expectedExpenses = TaxExport.includedExpenses(from: everyExpense, in: expenses.range)
        if expectedExpenses.count != expenses.document.rowCount {
            findings.append(.expenseRowsDisagree(expected: expectedExpenses.count,
                                                 found: expenses.document.rowCount))
        }
        let expectedExpenseTotal = Money.sum(of: expectedExpenses.map(\.amount))
        if expectedExpenseTotal != expenses.total {
            findings.append(.expenseTotalDisagrees(expected: expectedExpenseTotal.exportAmount,
                                                   found: expenses.total.exportAmount))
        }

        // EVERY PAYMENT AND REFUND IS ACCOUNTED FOR: attached to an invoice that
        // is a row, attached to one outside the range and counted as that, or a
        // finding. Nothing is allowed to be merely absent.
        var paymentsOutside = 0
        for payment in everyPayment {
            let standing = payment.allocations.filter { $0.releasedOn == nil }

            // AN ALLOCATION THAT OUTLIVED ITS INVOICE IS ITS OWN FINDING
            // (ovation#176). It is reported per allocation rather than per
            // payment, because a payment can carry more than one and each is its
            // own destroyed invoice.
            for orphan in standing where orphan.invoice == nil {
                findings.append(.allocationOutlivedItsInvoice(
                    dayKey: orphan.allocatedOn.dayKey,
                    amount: orphan.amount.exportAmount))
            }

            let invoices = standing.compactMap(\.invoice)
            if invoices.isEmpty {
                // ONLY WHERE THERE IS NOTHING ORPHANED EITHER. Both firing would
                // double the count of things to look at and give two names to one
                // problem, which is the opposite of what separating them is for.
                if standing.isEmpty {
                    findings.append(.paymentAttachedToNothing(dayKey: payment.receivedOn.dayKey))
                }
                continue
            }
            if !invoices.contains(where: { belongs($0, to: income.range) }) {
                paymentsOutside += 1
            }
        }

        var refundsOutside = 0
        for refund in everyRefund {
            guard let invoice = refund.invoice else {
                findings.append(.refundAttachedToNothing(dayKey: refund.refundedOn.dayKey))
                continue
            }
            if !belongs(invoice, to: income.range) { refundsOutside += 1 }
        }

        let manifest = TaxExportManifest(
            firstDayKey: income.range.firstDayKey,
            lastDayKey: income.range.lastDayKey,
            dateRule: TaxExport.dateRuleInForce,
            incomeRows: income.document.rowCount,
            incomeTotal: income.total.exportAmount,
            salesTax: income.salesTax.exportAmount,
            notIncluded: Dictionary(uniqueKeysWithValues:
                income.notIncluded.map { ($0.key.rawValue, $0.value) }),
            expenseRows: expenses.document.rowCount,
            expenseTotal: expenses.total.exportAmount,
            expensesNeedingACategory: expenses.needingACategory,
            paymentsAgainstInvoicesOutsideTheRange: paymentsOutside,
            refundsAgainstInvoicesOutsideTheRange: refundsOutside,
            findings: findings.count)

        return TaxExportReconciliation(
            manifest: manifest,
            findings: findings,
            paymentsAgainstInvoicesOutsideTheRange: paymentsOutside,
            refundsAgainstInvoicesOutsideTheRange: refundsOutside)
    }

    /// Whether this invoice is one the file should hold, by the export's own
    /// rule. One predicate, asked here about one invoice (L16).
    private static func belongs(_ invoice: Invoice, to range: TaxExportRange) -> Bool {
        !TaxExport.included(from: [invoice], in: range).isEmpty
    }

    /// The invoice numbers in the RENDERED rows, by finding the column rather
    /// than by trusting its position: a column inserted above it would otherwise
    /// silently make this read the invoice date.
    private static func renderedInvoiceNumbers(in document: CSVDocument) -> [Int64] {
        guard let column = document.header.firstIndex(of: "Invoice number") else { return [] }
        return document.rows.compactMap { row in
            guard row.indices.contains(column) else { return nil }
            switch row[column] {
            case .text(let value), .formatted(let value):
                return Int64(value)
            }
        }
    }
}
