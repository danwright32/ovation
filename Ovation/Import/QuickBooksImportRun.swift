// ovation#72. One import run over the three QuickBooks files, and its report:
// rows read, accepted and refused per file, a reason for every refusal, and what
// was written.
//
// THE CATEGORIES DO NOT COLLAPSE. Read, accepted and refused are counted per
// file with accepted plus refused equal to read, file level refusals are said
// before the counts they qualify, and the TOTAL comparison says whether "read"
// meant the whole file (ovation#72).
//
// NOTHING IS WRITTEN YET, AND THE REPORT SAYS SO IN WORDS. The store write, its
// idempotency key and the already imported count are ovation#68 to ovation#70. A
// "0 written" here would read exactly like a re-run where everything was already
// imported, so the report states that this build does not write (L98).
//
// THE PRIVACY FLOOR (docs/PRIVACY-FLOOR.md, L222). The report is what reaches a
// terminal or a transcript, so it is built from row numbers, field names, counts
// and reasons, and has no way to print a client name, a description, an invoice
// number or an amount. The typed rows and the differences stay in the run, for
// Dan's own screen.
import Foundation

struct QuickBooksImportRun: Sendable {
    let invoiceList: QuickBooksFileRead<QuickBooksInvoiceRow>
    let payments: QuickBooksFileRead<QuickBooksPaymentRow>
    let salesLines: QuickBooksFileRead<QuickBooksLineRow>
    /// Nil when either file it compares was refused as a whole, because
    /// reconciling against a file that cannot be believed produces findings
    /// about the wrong thing.
    let reconciliation: QuickBooksReconciliation?

    init(invoiceList: QuickBooksFileRead<QuickBooksInvoiceRow>,
         payments: QuickBooksFileRead<QuickBooksPaymentRow>,
         salesLines: QuickBooksFileRead<QuickBooksLineRow>) {
        self.invoiceList = invoiceList
        self.payments = payments
        self.salesLines = salesLines
        self.reconciliation = invoiceList.isAccepted && salesLines.isAccepted
            ? QuickBooksReconciliation.reconcile(invoices: invoiceList.accepted, lines: salesLines.accepted)
            : nil
    }

    /// The report, one line per string, in the privacy floor's vocabulary.
    var report: [String] {
        var out: [String] = []
        out += Self.fileReport(QuickBooksCustodyFile.invoiceList.fileName, invoiceList)
        out += Self.fileReport(QuickBooksCustodyFile.payments.fileName, payments)
        out += Self.fileReport(QuickBooksCustodyFile.salesLines.fileName, salesLines)
        out += reconciliationReport
        if payments.isAccepted {
            let unnumbered = payments.accepted.filter { $0.number == nil }.count
            out.append("payments not matched to invoices: \(unnumbered) of \(payments.accepted.count) "
                       + "carry no invoice number")
        }
        out.append("written: nothing, this build reads and reconciles only; "
                   + "the store write is ovation#68 to ovation#70")
        out.append("already imported: not checked, nothing reads the store yet")
        return out
    }

    private var reconciliationReport: [String] {
        guard let reconciliation else {
            let refused = [invoiceList.isAccepted ? nil : "the invoice list",
                           salesLines.isAccepted ? nil : "the sales lines file"].compactMap { $0 }
            let verb = refused.count == 1 ? "was" : "were"
            return ["reconciliation by invoice number: not run, \(refused.joined(separator: " and ")) \(verb) refused"]
        }
        var out = ["reconciliation by invoice number: \(reconciliation.agreed.count) agree, "
                   + "\(reconciliation.refusals.count) refused"]
        for refusal in reconciliation.refusals {
            var places: [String] = []
            if let row = refusal.invoiceRow { places.append("invoice list row \(row)") }
            if !refusal.lineRows.isEmpty {
                let rows = refusal.lineRows.map(String.init).joined(separator: ", ")
                places.append("sales lines \(refusal.lineRows.count == 1 ? "row" : "rows") \(rows)")
            }
            let why: String
            switch refusal.reason {
            case .onlyInSalesLines: why = "no accepted invoice in the invoice list"
            case .onlyInInvoiceList: why = "no accepted line in the sales lines file"
            case .linesDoNotSumToTotal: why = "the lines do not sum to the invoice total"
            }
            out.append("  \(places.joined(separator: ", ")): \(why)")
        }
        return out
    }

    private static func fileReport<Row>(_ name: String, _ read: QuickBooksFileRead<Row>) -> [String] {
        var out = read.fileRefusals.map { "\(name): REFUSED, \(sentence(for: $0))" }
        out.append("\(name): \(read.rowsRead) read, \(read.accepted.count) accepted, \(read.refused.count) refused")
        switch read.totalCheck {
        case .agrees: out.append("  TOTAL agrees with the rows read")
        case .disagrees: out.append("  REFUSED, the TOTAL disagrees with the rows read, so the read was not the whole file")
        case .notComparable(let rows):
            out.append("  REFUSED, the TOTAL could not be compared, \(rows) rows have no readable amount")
        case .unreadableTotal: out.append("  REFUSED, the TOTAL row's amount cannot be read")
        case .noTotal:
            // Said once: a file refused before its rows were read, or refused
            // for having no TOTAL, already says why there is nothing here (L11).
            if read.fileRefusals.isEmpty {
                out.append("  REFUSED, there is no TOTAL row to compare the rows against")
            }
        }
        for refusal in read.refused {
            out.append("  row \(refusal.row): \(sentence(for: refusal.reason))")
        }
        var counts: [String: Int] = [:]
        for refusal in read.refused { counts[key(for: refusal.reason), default: 0] += 1 }
        for (key, count) in counts.sorted(by: { $0.key < $1.key }) {
            out.append("  refused \(key): \(count)")
        }
        return out
    }

    private static func sentence(for refusal: QuickBooksFileRefusal) -> String {
        switch refusal {
        case .absent: return "the file is not in the custody folder"
        case .unreadable: return "the file is there and could not be read"
        case .hashMismatch: return "the file is not the one docs/CUSTODY.md records, so nothing in it was read"
        case .notUTF8: return "the file is not UTF-8"
        case .headerNotAsMeasured: return "line 5 is not the measured header, so this is another report or other settings"
        case .unterminatedQuote(let row): return "a quote opened on row \(row) never closes, so nothing from row \(row) on was read"
        case .noTotalRow: return "there is no TOTAL row, so the file may have been cut short"
        case .unexpectedAfterTotal(let row): return "row \(row) follows the TOTAL and is not the report timestamp"
        case .noTimestampLine: return "there is no report timestamp after the TOTAL"
        case .groupsDoNotNest(let row): return "the product groups stop nesting at row \(row), so later lines have no known product"
        case .cashBasis: return "the report is on cash basis, so its rows are shares of lines by payment; export it again on accrual basis"
        case .basisNotStated: return "the report does not say it is on accrual basis"
        }
    }

    private static func sentence(for reason: QuickBooksRowRefusal.Reason) -> String {
        switch reason {
        case .fieldCount(let expected, let found): return "expected \(expected) fields, found \(found)"
        case .malformedQuoting: return "text follows a closing quote"
        case .missing(let field): return "\(field) is empty"
        case .unreadableDate(let field): return "\(field) is not an M/D/YYYY date that exists"
        case .beforeScope(let field): return "\(field) is before 2026-01-01, outside Ovation's record"
        case .unreadableAmount(let field): return "\(field) is not a figure with two decimals and no currency symbol"
        case .unreadableInvoiceNumber(let field): return "\(field) is not a whole number"
        case .unexpectedValue(let field): return "\(field) holds a value this export does not carry there"
        case .amountIsNotQuantityTimesPrice: return "Amount is not Quantity times Sales price"
        case .duplicateInvoiceNumber(let rows):
            return "Num is shared by rows \(rows.map(String.init).joined(separator: ", "))"
        }
    }

    /// The class of a refusal, for the per reason count.
    private static func key(for reason: QuickBooksRowRefusal.Reason) -> String {
        switch reason {
        case .fieldCount: return "wrong number of fields"
        case .malformedQuoting: return "text after a closing quote"
        case .missing: return "empty field"
        case .unreadableDate: return "unreadable date"
        case .beforeScope: return "before 2026"
        case .unreadableAmount: return "unreadable amount"
        case .unreadableInvoiceNumber: return "unreadable invoice number"
        case .unexpectedValue: return "unexpected value"
        case .amountIsNotQuantityTimesPrice: return "amount is not quantity times price"
        case .duplicateInvoiceNumber: return "shared invoice number"
        }
    }
}
