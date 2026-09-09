// ovation#61, PRD 23 to 25a. The two CSVs an accountant works from in January.
//
// INCOME IS ACCRUAL. One row per ISSUED invoice, dated by the invoice date,
// whether or not it has been paid (PRD 24, Dan 2026-08-27, reaffirmed after the
// term was explained). That is the opposite of the intuitive cash view, so it is
// stated here and on the surface that produces the file, not only in a test. An
// unpaid invoice IS income for the year it was issued; an invoice issued in
// December and paid in January belongs entirely to the December year; and payment
// dates, still recorded and still exported, decide nothing about the year.
//
// ISSUED MEANS SENT ESTABLISHED, NEVER CREATED (PRD 24b, ovation#45). Sent is
// only ever observed, so the set of invoices on a return is exactly the set whose
// Sent was established. That puts the derived Gmail match on the tax path: an
// invoice Dan sent from Spark that the match misses is MISSING INCOME. So the two
// states that are not "sent" are COUNTED, separately, rather than silently left
// out, and they are counted separately from each other because a draft is a
// decision Dan has not made and an undetermined Sent is a question Ovation could
// not answer (L11).
//
// THE DATES ARE STAMPED DAY KEYS AND NOTHING HERE DOES CALENDAR ARITHMETIC
// (ovation#55). The key was settled when the row was written, in Dan's shooting
// zone, so re-running last January's export produces last January's numbers even
// on a machine in another timezone (L37). A shoot at 23:30 on 31 December is
// already the next year in UTC, and the export must not care.
//
// WHICH DATE DECIDES THE YEAR IS AN OPEN QUESTION FOR THE ACCOUNTANT (PRD 9.3,
// ovation#65): the invoice date, which is the shoot date, or the day it was sent.
// Until it is answered this keys on the INVOICE DATE, and `dateRuleInForce` says
// so in words, so the choice travels with the export rather than being a fact
// about the code (L316).
//
// THE COUNT AND THE ROWS COME FROM ONE PREDICATE. `included(from:in:)` is what
// selects, and both the document and every number answered here are derived from
// its result. A count computed beside the rows is a second definition that drifts,
// and the number is the half a person reads (L16, L107).
//
// PRIVACY. The file necessarily holds real client names, because that is what an
// accountant needs. NOTHING ABOUT PRODUCING IT MAY PRINT ONE: `summary` is what a
// log or a terminal would carry, and it holds counts and totals only (L222,
// docs/PRIVACY-FLOOR.md).
import Foundation

/// A range of business days, both ends included, compared as stamped keys.
struct TaxExportRange: Equatable, Sendable {
    let firstDayKey: String
    let lastDayKey: String

    /// PRD 23: any date range, defaulting to the calendar year.
    static func calendarYear(_ year: Int) -> TaxExportRange {
        TaxExportRange(firstDayKey: String(format: "%04d-01-01", year),
                       lastDayKey: String(format: "%04d-12-31", year))
    }

    /// A key outside the range, or one that is not a day key at all, is OUT.
    ///
    /// `BusinessDate` deliberately loads a row whose stored key is malformed
    /// rather than throwing and taking the store with it, so one can reach here.
    /// String ordering alone would put some malformed values inside a range by
    /// accident, which is a row silently landing in a tax year (L50).
    func contains(dayKey: String) -> Bool {
        guard BusinessCalendar.year(forDayKey: dayKey) != nil else { return false }
        return dayKey >= firstDayKey && dayKey <= lastDayKey
    }
}

/// Why an invoice that might have been income is not a row.
///
/// EVERY ABSENCE CARRIES A MEASURED REASON. A reconciliation that balances by
/// summing named buckets is satisfied by the defect it hunts as long as the
/// missing item lands in a bucket standing for legitimate cases, so membership
/// here is earned by matching a rule rather than by failing to match the good
/// case (L540). An invoice belonging to another year is not in any of these: it
/// is not missing from anything.
enum IncomeOmission: String, CaseIterable, Hashable, Sendable {
    /// Its Sent was never established. It is a draft, and a draft is not income.
    case neverIssued
    /// Ovation looked and could not tell whether it was sent. This is the one
    /// that may be real income missing from the return.
    case sentCouldNotBeDetermined
    /// It has no invoice date, so it cannot be placed in any year.
    case noInvoiceDate
    /// It HAS a stamped day key and that key cannot be read as a day, so it
    /// cannot be placed either.
    ///
    /// SEPARATE FROM `noInvoiceDate` AND FROM SILENCE. `BusinessDate` loads a row
    /// whose stored key is malformed rather than throwing and taking the store
    /// with it, so such a row reaches here; `contains(dayKey:)` correctly answers
    /// false for it, and without this bucket the invoice would then be in no
    /// file, in no count, and reported by nothing. A value parsed from storage
    /// that feeds a comparison lands on the quiet side unless the parse failure
    /// is given somewhere to go (L50).
    case invoiceDateUnreadable
}

/// What one file's worth of export came to. The document, and the numbers that
/// describe it, from the same selection.
struct IncomeExport: Sendable {
    let range: TaxExportRange
    let document: CSVDocument
    let rowsIncluded: Int
    let total: Money
    let salesTax: Money
    /// Counted by reason, never summed into one number, because the remedies
    /// differ and one of the three is alarming.
    let notIncluded: [IncomeOmission: Int]

    /// What may be printed. Counts and totals, never a name (L222).
    var summary: String {
        var out = "income \(range.firstDayKey) to \(range.lastDayKey): "
            + "\(rowsIncluded) row(s), total \(total.exportAmount), "
            + "sales tax \(salesTax.exportAmount)"
        for omission in IncomeOmission.allCases where notIncluded[omission] != nil {
            out += ", \(omission.rawValue) \(notIncluded[omission] ?? 0)"
        }
        return out
    }
}

struct ExpenseExport: Sendable {
    let range: TaxExportRange
    let document: CSVDocument
    let rowsIncluded: Int
    let total: Money
    /// Exported and countable rather than excluded: money that was spent is a
    /// deduction whether or not anybody has said what kind it was (L67).
    let needingACategory: Int
    /// Expenses whose stamped day key cannot be read as a day, so they are in no
    /// range and in no file. Counted for the same reason as
    /// `IncomeOmission.invoiceDateUnreadable`: otherwise the comparison quietly
    /// excludes them and nothing anywhere says so (L50).
    let withAnUnreadableDate: Int

    var summary: String {
        "expenses \(range.firstDayKey) to \(range.lastDayKey): "
            + "\(rowsIncluded) row(s), total \(total.exportAmount), "
            + "needing a category \(needingACategory), "
            + "unreadable date \(withAnUnreadableDate)"
    }
}

enum TaxExport {

    /// The rule in force about which date decides the year, in words, so it can
    /// travel with the export. PRD 9.3 is the question this answers provisionally.
    static let dateRuleInForce =
        "Income is on an accrual basis and each row is dated by the INVOICE DATE, "
        + "which is the shoot date, not by the day it was sent or paid. Whether the "
        + "send date should decide instead is an open question for the accountant "
        + "(PRD 9.3)."

    // MARK: income

    /// THE one selection. Everything else here reads its result.
    static func included(from invoices: [Invoice], in range: TaxExportRange) -> [Invoice] {
        invoices
            .filter { invoice in
                guard invoice.sentStatus.wasSent,
                      let key = invoice.invoiceDate?.dayKey else { return false }
                return range.contains(dayKey: key)
            }
            // A collection carries no order unless the read declares one, and an
            // export whose rows move between runs cannot be compared with the
            // copy the accountant already has (L343, L419). The number breaks the
            // tie, and the id breaks that, so the order is total.
            .sorted { left, right in
                let leftKey = left.invoiceDate?.dayKey ?? ""
                let rightKey = right.invoiceDate?.dayKey ?? ""
                if leftKey != rightKey { return leftKey < rightKey }
                if left.number != right.number {
                    return (left.number ?? .max) < (right.number ?? .max)
                }
                return left.id.uuidString < right.id.uuidString
            }
    }

    /// Why the invoices that are NOT rows are not rows, counted by reason.
    ///
    /// Only invoices that could have belonged to this range are considered. One
    /// from another year is not an omission and is deliberately in none of these.
    static func omissions(from invoices: [Invoice],
                          in range: TaxExportRange) -> [IncomeOmission: Int] {
        var counts: [IncomeOmission: Int] = [:]
        for invoice in invoices {
            guard let key = invoice.invoiceDate?.dayKey else {
                counts[.noInvoiceDate, default: 0] += 1
                continue
            }
            guard BusinessCalendar.year(forDayKey: key) != nil else {
                counts[.invoiceDateUnreadable, default: 0] += 1
                continue
            }
            guard range.contains(dayKey: key) else { continue }
            switch invoice.sentStatus {
            case .sent: continue
            case .notSent: counts[.neverIssued, default: 0] += 1
            case .couldNotDetermine: counts[.sentCouldNotBeDetermined, default: 0] += 1
            }
        }
        return counts
    }

    static let incomeColumns = [
        "Invoice number", "Invoice date", "Client", "Kind", "Status",
        "Subtotal", "Discount", "Sales tax", "Total",
        "Amount paid", "Amount outstanding", "Payment state",
        "Payment dates", "Payment amounts", "Payment methods", "Cleared dates",
        "Refunded", "Refund dates", "Sent on", "Sent route"
    ]

    static func income(from invoices: [Invoice], in range: TaxExportRange) -> IncomeExport {
        let rows = included(from: invoices, in: range)
        let document = CSVDocument(header: incomeColumns, rows: rows.map(incomeRow))
        return IncomeExport(
            range: range,
            document: document,
            rowsIncluded: rows.count,
            total: Money.sum(of: rows.map(\.total)),
            salesTax: Money.sum(of: rows.map(\.tax)),
            notIncluded: omissions(from: invoices, in: range))
    }

    private static func incomeRow(_ invoice: Invoice) -> [CSVDocument.Field] {
        // The allocations that still stand, in a declared order, so the three
        // payment columns line up with each other row by row.
        let allocations = invoice.allocations
            .filter { $0.releasedOn == nil }
            .sorted { left, right in
                let leftKey = left.payment?.receivedOn.dayKey ?? ""
                let rightKey = right.payment?.receivedOn.dayKey ?? ""
                if leftKey != rightKey { return leftKey < rightKey }
                return left.id.uuidString < right.id.uuidString
            }
        let refunds = invoice.refunds.sorted { $0.refundedOn.dayKey < $1.refundedOn.dayKey }

        return [
            // A number is Ovation's own, and a draft has none, which is a state
            // rather than a zero.
            .formatted(invoice.number.map(String.init) ?? ""),
            .formatted(invoice.invoiceDate?.dayKey ?? ""),
            // The one field on this row that came from outside Ovation.
            .text(invoice.client?.name ?? ""),
            .formatted(invoice.kind.exportLabel),
            .formatted(statusLabel(for: invoice)),
            .formatted(invoice.subtotal.exportAmount),
            .formatted(invoice.discountAmount.exportAmount),
            .formatted(invoice.tax.exportAmount),
            .formatted(invoice.total.exportAmount),
            .formatted(invoice.amountPaid.exportAmount),
            .formatted(invoice.amountOutstanding.exportAmount),
            .formatted(invoice.paymentState.exportLabel),
            .formatted(joined(allocations.map { $0.payment?.receivedOn.dayKey ?? "" })),
            .formatted(joined(allocations.map(\.amount.exportAmount))),
            .formatted(joined(allocations.map { $0.payment?.method.exportLabel ?? "" })),
            // Empty for a payment that has not cleared, and for one that never
            // gains a cleared step at all. PRD 5.15 puts cleared on the payment,
            // so this is per payment rather than per invoice.
            .formatted(joined(allocations.map { $0.payment?.clearedOn?.dayKey ?? "" })),
            .formatted(Money.sum(of: refunds.map(\.amount)).exportAmount),
            .formatted(joined(refunds.map(\.refundedOn.dayKey))),
            .formatted(invoice.sentStatus.establishedAt.map(BusinessCalendar.dayKey(for:)) ?? ""),
            .formatted(invoice.sentStatus.route?.rawValue ?? "")
        ]
    }

    /// What happened to the invoice after it was issued. Separate from the
    /// payment state, which is about money alone, because folding them would make
    /// a cancelled unpaid invoice indistinguishable from an open one.
    private static func statusLabel(for invoice: Invoice) -> String {
        switch invoice.closure {
        case .none: return "Issued"
        case .cancelled: return "Cancelled"
        case .dismissed: return "Dismissed"
        }
    }

    /// Several values in one cell, in the row's own order. A semicolon rather
    /// than a comma so the cell does not depend on the quoting to stay one
    /// column when a person copies it out.
    private static func joined(_ values: [String]) -> String {
        values.joined(separator: "; ")
    }

    // MARK: expenses

    static func includedExpenses(from expenses: [Expense],
                                 in range: TaxExportRange) -> [Expense] {
        expenses
            .filter { range.contains(dayKey: $0.incurredOn.dayKey) }
            .sorted { left, right in
                if left.incurredOn.dayKey != right.incurredOn.dayKey {
                    return left.incurredOn.dayKey < right.incurredOn.dayKey
                }
                return left.id.uuidString < right.id.uuidString
            }
    }

    static let expenseColumns = [
        "Date", "Vendor", "Category", "Schedule C line", "Amount", "Receipt", "Note"
    ]

    static func expenses(from expenses: [Expense], in range: TaxExportRange) -> ExpenseExport {
        let rows = includedExpenses(from: expenses, in: range)
        let document = CSVDocument(header: expenseColumns, rows: rows.map(expenseRow))
        return ExpenseExport(
            range: range,
            document: document,
            rowsIncluded: rows.count,
            total: Money.sum(of: rows.map(\.amount)),
            needingACategory: rows.filter(\.needsACategory).count,
            withAnUnreadableDate: expenses.filter {
                BusinessCalendar.year(forDayKey: $0.incurredOn.dayKey) == nil
            }.count)
    }

    private static func expenseRow(_ expense: Expense) -> [CSVDocument.Field] {
        [
            .formatted(expense.incurredOn.dayKey),
            // From outside Ovation: a vendor is whatever the receipt said.
            .text(expense.vendor ?? ""),
            .formatted(expense.category?.exportLabel ?? "Not categorised"),
            // Blank rather than a guess when nobody has said what it is: a
            // Schedule C line asserted for an uncategorised expense would put
            // money on a line of a return on no evidence (L192).
            .formatted(expense.category?.scheduleC.line.exportLabel ?? ""),
            .formatted(expense.amount.exportAmount),
            // The expense's own vocabulary, not a second one here: "no receipt"
            // and "imported without one" are different facts (L118).
            .formatted(expense.hasReceipt ? "Yes" : expense.receiptMissingNote),
            .text(expense.note ?? "")
        ]
    }
}
