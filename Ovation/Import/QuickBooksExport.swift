// ovation#67, PRD 5.27. The three QuickBooks exports, read into typed rows, with
// every row that cannot be read refused by its row number and a reason.
//
// MEASURED, NOT IMAGINED (ovation#66). The format below is what the three custody
// files actually contain, recorded on #66 and in a shape only pass over them on
// 2026-09-29 that read pattern classes and never a value: three preamble lines,
// an empty fourth, the header on line 5, data rows, a TOTAL row, three empty
// lines and a report timestamp line. The sales lines report groups its rows
// under product headings that nest and close with "Total for" rows.
//
// REFUSE, NEVER COERCE (L340). A value that is not in the measured shape is not
// turned into a plausible one: an amount carrying a currency symbol, a third
// decimal, a date in another format, a day that does not exist. Each is refused
// by row and field name, because the fixes differ and "17 refused" is nothing
// anybody can act on (ovation#67).
//
// ACCEPT ONLY WHAT THE READER CAN HOLD (L150). Ovation computes a line's amount
// from its hours and rate and never stores it (LineItem), so a line whose amount
// is not its quantity times its price, rounded as Ovation rounds, is refused
// here rather than imported and silently repriced later.
//
// 2026 ONLY (Dan, 2026-09-26, ovation#118). A row dated before 2026-01-01 is
// refused by name and counted, never dropped: dropping it would make a file with
// 2025 rows in it look exactly like one without.
//
// NOTHING HERE PRINTS. The typed rows carry client names because the import
// needs them; what reaches a terminal is `QuickBooksImportRun.report`, which
// carries row numbers, field names and counts only (docs/PRIVACY-FLOOR.md).
import CryptoKit
import Foundation

/// Which of the three QuickBooks reports a file is.
enum QuickBooksReport: String, CaseIterable, Sendable {
    case invoiceList
    case payments
    case salesLines
    case invoicesAndPayments

    /// The header on line 5, exactly as measured. Anything else is a different
    /// report or a different export setting, and is refused as a whole.
    var header: [String] {
        switch self {
        case .invoiceList:
            return ["Date", "Transaction type", "Num", "Name", "Memo", "Due date", "Amount", "Open balance"]
        case .payments:
            return ["Date", "Transaction type", "Num", "Posting (Y/N)", "Name", "Memo", "Account name",
                    "Split", "Amount"]
        case .salesLines:
            return ["", "Transaction date", "Transaction type", "Num", "Client full name", "Description",
                    "Quantity", "Sales price", "Amount", "Balance"]
        case .invoicesAndPayments:
            return ["", "Date", "Transaction type", "Memo/Description", "Transaction number", "Amount"]
        }
    }

    /// Whether the report exports a TOTAL row. MEASURED: the Invoices and
    /// Received Payments report has none, and no "Total for" rows either, so its
    /// body runs straight into the empty lines and the timestamp.
    var hasTotalRow: Bool { self != .invoicesAndPayments }

    /// The column the TOTAL row sums, which is the one the short read check
    /// compares against the rows.
    var amountColumn: Int { header.firstIndex(of: "Amount") ?? 0 }

    /// The row the header sits on, measured on all three files.
    static let headerRow = 5
}

/// One custody file and the hash it was recorded with in docs/CUSTODY.md.
struct QuickBooksCustodyFile: Equatable, Sendable {
    let report: QuickBooksReport
    let fileName: String
    let sha256: String

    /// The three files Dan exported on 2026-09-29 (ovation#66). The hashes are
    /// docs/CUSTODY.md's, and `QuickBooksExportTests` holds the two copies equal,
    /// because the app cannot read the note at runtime (L41).
    static let invoiceList = QuickBooksCustodyFile(
        report: .invoiceList, fileName: "quickbooks-invoice-list-2026-09-29.csv",
        sha256: "811848e1452c8fa8546e4c4b64ecc2d7ea0d8dc87411f8c08fc29947595870aa")
    static let payments = QuickBooksCustodyFile(
        report: .payments, fileName: "quickbooks-payments-2026-09-29.csv",
        sha256: "d798e8d99a45cc3ba271323bcc8bceb7d81d5464010b4fda92195311771a3c09")
    /// The ACCRUAL basis re-export of 2026-09-30, which replaces the cash basis
    /// file of 2026-09-29. That one stays in docs/CUSTODY.md, marked superseded,
    /// and this parser refuses it by name.
    static let salesLines = QuickBooksCustodyFile(
        report: .salesLines, fileName: "quickbooks-sales-lines-accrual-2026-09-30.csv",
        sha256: "d866fde4bc2adca23d492984e1bf5477e096f133ff8cd6ec356b9d94dfad292b")
    /// The Invoices and Received Payments report of 2026-09-30, the only export
    /// that places a payment under the client and invoices it belongs to.
    static let invoicesAndPayments = QuickBooksCustodyFile(
        report: .invoicesAndPayments, fileName: "quickbooks-invoices-and-payments-2026-09-30.csv",
        sha256: "e1a8283fa097bf6acce4af61317c2db4fa712462c2306a9c1d0ea8263a22cbb8")

    static let recorded = [invoiceList, payments, salesLines, invoicesAndPayments]

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Why a whole file was refused. Each is its own outcome, because each needs a
/// different action and collapsing any two would let a file nobody checked read
/// like one that passed (L11).
enum QuickBooksFileRefusal: Equatable, Sendable {
    /// The custody file is not where the record says.
    case absent
    /// It is there and could not be read.
    case unreadable
    /// It reads, and it is not the file that was recorded. Nothing in it is read.
    case hashMismatch
    case notUTF8
    /// Line 5 is not the measured header: a different report, or different
    /// export settings.
    case headerNotAsMeasured
    /// A quoted field opened on this row and never closed, so nothing from it
    /// on was reached.
    case unterminatedQuote(fromRow: Int)
    /// No TOTAL row, so the file may have been cut short.
    case noTotalRow
    /// Something other than empty lines and the timestamp follows the TOTAL.
    case unexpectedAfterTotal(row: Int)
    /// No report timestamp line after the TOTAL.
    case noTimestampLine
    /// A "Total for" row that does not close the group open at that row, or a
    /// group still open at the TOTAL, so no line after it has a known product.
    case groupsDoNotNest(row: Int)
    /// The sales lines report was run on cash basis. MEASURED on the real file:
    /// a cash basis report splits each line across the payments that covered it
    /// and drops what is unpaid, so its rows are shares of lines, not lines.
    case cashBasis
    /// The sales lines report does not say which basis it was run on.
    case basisNotStated
}

/// Whether the file's own TOTAL agrees with the rows read from it: the check
/// that a read was complete (ovation#72).
enum QuickBooksTotalCheck: Equatable, Sendable {
    case agrees
    /// TOTAL minus the sum of the rows.
    case disagrees(difference: Money)
    /// Some rows' amounts could not be read, so there is nothing to compare.
    case notComparable(rowsWithoutAmount: Int)
    /// The TOTAL row is there and its amount cannot be read.
    case unreadableTotal
    case noTotal
    /// The report exports no TOTAL at all, measured, so completeness rests on
    /// its timestamp line and on the reconciliation against the other files.
    case noneExported
}

/// One row refused, by its row number, with the reason.
struct QuickBooksRowRefusal: Equatable, Sendable {
    let row: Int
    let reason: Reason

    enum Reason: Equatable, Sendable {
        case fieldCount(expected: Int, found: Int)
        /// Text follows a closing quote inside a field.
        case malformedQuoting
        case missing(field: String)
        case unreadableDate(field: String)
        /// Dated before 2026-01-01, outside Ovation's record (ovation#118).
        case beforeScope(field: String)
        case unreadableAmount(field: String)
        case unreadableInvoiceNumber(field: String)
        /// A value outside the small set this export carries in that column.
        case unexpectedValue(field: String)
        case amountIsNotQuantityTimesPrice
        /// Every row carrying one invoice number, when more than one does.
        case duplicateInvoiceNumber(rows: [Int])
        /// A data row above the first group heading, so it belongs to nobody.
        case outsideAnyGroup
    }
}

/// A file read: its own refusals, and every data row either accepted or refused.
struct QuickBooksFileRead<Row: Sendable>: Sendable {
    let fileRefusals: [QuickBooksFileRefusal]
    /// Data rows reached, which is accepted plus refused. Headings, group totals
    /// and empty lines are structure, counted apart.
    let rowsRead: Int
    let accepted: [Row]
    let refused: [QuickBooksRowRefusal]
    let structureRows: Int
    let totalCheck: QuickBooksTotalCheck

    /// Whether the file as a whole can be believed. A refused file still lists
    /// its rows, so the report can say everything that is wrong at once.
    ///
    /// ONLY AN AGREEING TOTAL IS A COMPLETE READ. A TOTAL that is missing,
    /// unreadable or left uncompared is a read nobody has shown was whole, and
    /// believing it is how a short read becomes a filed return (L211, ovation#72).
    var isAccepted: Bool {
        fileRefusals.isEmpty && (totalCheck == .agrees || totalCheck == .noneExported)
    }

    static func refused(_ refusal: QuickBooksFileRefusal) -> QuickBooksFileRead {
        QuickBooksFileRead(fileRefusals: [refusal], rowsRead: 0, accepted: [], refused: [],
                           structureRows: 0, totalCheck: .noTotal)
    }
}

struct QuickBooksInvoiceRow: Equatable, Sendable {
    let row: Int
    let date: BusinessDate
    let number: Int64
    let name: String
    let memo: String
    let dueDate: BusinessDate
    let amount: Money
    let openBalance: Money
}

struct QuickBooksPaymentRow: Equatable, Sendable {
    let row: Int
    let date: BusinessDate
    /// Empty on every measured payment, so nothing ties a payment to an invoice.
    let number: String?
    let posting: Bool
    let name: String
    let memo: String
    let account: String
    let split: String
    let amount: Money
}

/// One row of the Invoices and Received Payments report.
struct QuickBooksLedgerRow: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case invoice, payment }

    let row: Int
    /// The client heading this row sits under, which is the only thing tying a
    /// payment to anything: payments carry no transaction number.
    let groupRow: Int
    let client: String
    let date: BusinessDate
    let kind: Kind
    /// The invoice number on an invoice row. Nil on every measured payment.
    let number: Int64?
    let memo: String
    let amount: Money
}

struct QuickBooksLineRow: Equatable, Sendable {
    let row: Int
    let date: BusinessDate
    let number: Int64
    let clientName: String
    /// The innermost product group the line sits in, or nil for a line in no
    /// group, which QuickBooks closes as "Total for --".
    let product: String?
    let description: String
    /// Hundredths, as `Hours` holds them. Nil with the price on a flat line.
    let quantityHundredths: Int64?
    let salesPrice: Money?
    let amount: Money
}

enum QuickBooksExport {

    /// The first day of Ovation's record (Dan, 2026-09-26, ovation#118).
    static let firstDayKey = "2026-01-01"

    // MARK: entry points

    static func invoiceList(_ file: QuickBooksCustodyFile, in folder: URL) -> QuickBooksFileRead<QuickBooksInvoiceRow> {
        switch verifiedData(file, in: folder) {
        case .success(let data): return invoiceList(data)
        case .failure(let refusal): return .refused(refusal.refusal)
        }
    }

    static func payments(_ file: QuickBooksCustodyFile, in folder: URL) -> QuickBooksFileRead<QuickBooksPaymentRow> {
        switch verifiedData(file, in: folder) {
        case .success(let data): return payments(data)
        case .failure(let refusal): return .refused(refusal.refusal)
        }
    }

    static func salesLines(_ file: QuickBooksCustodyFile, in folder: URL) -> QuickBooksFileRead<QuickBooksLineRow> {
        switch verifiedData(file, in: folder) {
        case .success(let data): return salesLines(data)
        case .failure(let refusal): return .refused(refusal.refusal)
        }
    }

    static func invoiceList(_ data: Data) -> QuickBooksFileRead<QuickBooksInvoiceRow> {
        guard let text = String(data: data, encoding: .utf8) else { return .refused(.notUTF8) }
        return invoiceList(text)
    }

    static func payments(_ data: Data) -> QuickBooksFileRead<QuickBooksPaymentRow> {
        guard let text = String(data: data, encoding: .utf8) else { return .refused(.notUTF8) }
        return payments(text)
    }

    static func salesLines(_ data: Data) -> QuickBooksFileRead<QuickBooksLineRow> {
        guard let text = String(data: data, encoding: .utf8) else { return .refused(.notUTF8) }
        return salesLines(text)
    }

    static func invoiceList(_ text: String) -> QuickBooksFileRead<QuickBooksInvoiceRow> {
        refusingDuplicateNumbers(flatRead(text, report: .invoiceList, row: invoice(from:)))
    }

    static func payments(_ text: String) -> QuickBooksFileRead<QuickBooksPaymentRow> {
        flatRead(text, report: .payments, row: payment(from:))
    }

    // MARK: reading the file as it was recorded

    private struct Refused: Error { let refusal: QuickBooksFileRefusal }

    /// The file's bytes, only where they hash to what docs/CUSTODY.md records.
    ///
    /// VERIFIED AT READ TIME, not only when the hash was written, as the note
    /// requires of every custody file. Absent, unreadable and changed are three
    /// outcomes, never one, and a changed file is not parsed at all: figures
    /// derived from a file that changed under its record are worse than none.
    private static func verifiedData(_ file: QuickBooksCustodyFile, in folder: URL) -> Result<Data, Refused> {
        let url = folder.appending(path: file.fileName)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return .failure(Refused(refusal: .absent))
        }
        guard let data = try? Data(contentsOf: url) else { return .failure(Refused(refusal: .unreadable)) }
        guard QuickBooksCustodyFile.sha256(of: data) == file.sha256 else {
            return .failure(Refused(refusal: .hashMismatch))
        }
        return .success(data)
    }

    // MARK: the frame every report shares

    /// Preamble, header, body, TOTAL and what follows it, split apart, with the
    /// file level refusals that splitting found.
    private struct Frame {
        var refusals: [QuickBooksFileRefusal] = []
        var body: [QuickBooksCSV.Record] = []
        var total: QuickBooksCSV.Record?
        /// The first column of the report timestamp line, which carries the basis.
        var timestamp: String?
        var headerAsMeasured = false
    }

    private static func frame(_ text: String, report: QuickBooksReport) -> Frame {
        var frame = Frame()
        var trimmed = text
        if trimmed.hasPrefix("\u{FEFF}") { trimmed.removeFirst() }
        let csv = QuickBooksCSV.parse(trimmed)
        if let row = csv.unterminatedFromRow { frame.refusals.append(.unterminatedQuote(fromRow: row)) }

        let records = csv.records
        guard records.count >= QuickBooksReport.headerRow,
              records[QuickBooksReport.headerRow - 1].fields == report.header else {
            frame.refusals = [.headerNotAsMeasured]
            return frame
        }
        frame.headerAsMeasured = true

        let rest = records.dropFirst(QuickBooksReport.headerRow)
        guard report.hasTotalRow else { return untotalledFrame(frame, rest: rest) }
        guard let totalIndex = rest.firstIndex(where: { $0.fields.first == "TOTAL" }) else {
            frame.body = Array(rest)
            frame.refusals.append(.noTotalRow)
            return frame
        }
        frame.body = Array(rest[rest.startIndex..<totalIndex])
        frame.total = rest[totalIndex]

        let after = rest[rest.index(after: totalIndex)...].filter { !isBlank($0) }
        if let timestamp = after.last, timestamp.fields.dropFirst().allSatisfy(\.isEmpty),
           !(timestamp.fields.first ?? "").isEmpty {
            frame.timestamp = timestamp.fields.first
            if let stray = after.dropLast().first {
                frame.refusals.append(.unexpectedAfterTotal(row: stray.row))
            }
        } else if let stray = after.first {
            frame.refusals.append(.unexpectedAfterTotal(row: stray.row))
        } else {
            frame.refusals.append(.noTimestampLine)
        }
        return frame
    }

    /// A report with no TOTAL: the body ends at the run of empty lines before the
    /// timestamp. A group heading has the same shape as the timestamp line, so
    /// the timestamp is only the last record AFTER an empty one; a file cut off
    /// mid body has no such line and is refused as having none.
    private static func untotalledFrame(_ start: Frame, rest: ArraySlice<QuickBooksCSV.Record>) -> Frame {
        var frame = start
        let records = Array(rest)
        guard let last = records.lastIndex(where: { !isBlank($0) }),
              last > 0, isBlank(records[last - 1]),
              !(records[last].fields.first ?? "").isEmpty,
              records[last].fields.dropFirst().allSatisfy(\.isEmpty) else {
            frame.body = records
            frame.refusals.append(.noTimestampLine)
            return frame
        }
        frame.timestamp = records[last].fields.first
        var end = last
        while end > 0 && isBlank(records[end - 1]) { end -= 1 }
        frame.body = Array(records[..<end])
        return frame
    }

    private static func isBlank(_ record: QuickBooksCSV.Record) -> Bool {
        record.fields.allSatisfy(\.isEmpty)
    }

    /// The TOTAL row against the rows read, over every data row whose amount
    /// could be read, refused rows included: the TOTAL describes the file, not
    /// what Ovation accepted from it.
    private static func totalCheck(_ frame: Frame, report: QuickBooksReport,
                                   amounts: [Money?]) -> QuickBooksTotalCheck {
        guard report.hasTotalRow else { return .noneExported }
        guard let total = frame.total else { return .noTotal }
        let column = report.amountColumn
        guard column < total.fields.count,
              let stated = amount(total.fields[column], allowingCurrencySymbol: true) else {
            return .unreadableTotal
        }
        let missing = amounts.filter { $0 == nil }.count
        guard missing == 0 else { return .notComparable(rowsWithoutAmount: missing) }
        let difference = stated - Money.sum(of: amounts.compactMap { $0 })
        return difference == .zero ? .agrees : .disagrees(difference: difference)
    }

    // MARK: the invoice list and payments, one row per record

    /// A row refused, thrown from inside a row reader so that each reader states
    /// its checks in order and stops at the first that fails.
    private struct RowRefused: Error { let reason: QuickBooksRowRefusal.Reason }

    private static func flatRead<Row>(_ text: String, report: QuickBooksReport,
                                      row read: (QuickBooksCSV.Record) throws -> Row)
        -> QuickBooksFileRead<Row> {
        let frame = frame(text, report: report)
        guard frame.headerAsMeasured else { return .refused(.headerNotAsMeasured) }

        var accepted: [Row] = []
        var refused: [QuickBooksRowRefusal] = []
        var amounts: [Money?] = []
        var structure = 0
        for record in frame.body {
            if isBlank(record) { structure += 1; continue }
            amounts.append(rawAmount(of: record, report: report))
            do {
                try checkShape(record, report: report)
                accepted.append(try read(record))
            } catch let refusal as RowRefused {
                refused.append(QuickBooksRowRefusal(row: record.row, reason: refusal.reason))
            } catch {
                refused.append(QuickBooksRowRefusal(row: record.row, reason: .malformedQuoting))
            }
        }
        var refusals = frame.refusals
        refusals += basisRefusals(frame, report: report)
        return QuickBooksFileRead(fileRefusals: refusals, rowsRead: accepted.count + refused.count,
                                  accepted: accepted, refused: refused, structureRows: structure,
                                  totalCheck: totalCheck(frame, report: report, amounts: amounts))
    }

    /// A row's amount for the TOTAL comparison, read whatever else is wrong with it.
    private static func rawAmount(of record: QuickBooksCSV.Record, report: QuickBooksReport) -> Money? {
        let column = report.amountColumn
        guard record.fields.count == report.header.count else { return nil }
        return amount(record.fields[column])
    }

    private static func checkShape(_ record: QuickBooksCSV.Record, report: QuickBooksReport) throws {
        guard record.fields.count == report.header.count else {
            throw RowRefused(reason: .fieldCount(expected: report.header.count, found: record.fields.count))
        }
        guard !record.malformed else { throw RowRefused(reason: .malformedQuoting) }
    }

    private static func invoice(from record: QuickBooksCSV.Record) throws -> QuickBooksInvoiceRow {
        let f = record.fields
        let date = try scopedDate(f[0], field: "Date")
        guard f[1] == "Invoice" else { throw RowRefused(reason: .unexpectedValue(field: "Transaction type")) }
        let number = try invoiceNumber(f[2], field: "Num")
        let name = try required(f[3], field: "Name")
        let due = try readDate(f[5], field: "Due date")
        let total = try readAmount(f[6], field: "Amount")
        let open = try readAmount(f[7], field: "Open balance")
        return QuickBooksInvoiceRow(row: record.row, date: date, number: number, name: name, memo: f[4],
                                    dueDate: due, amount: total, openBalance: open)
    }

    private static func payment(from record: QuickBooksCSV.Record) throws -> QuickBooksPaymentRow {
        let f = record.fields
        let date = try scopedDate(f[0], field: "Date")
        guard f[1] == "Payment" else { throw RowRefused(reason: .unexpectedValue(field: "Transaction type")) }
        let posting: Bool
        switch f[3] {
        case "Yes": posting = true
        case "No": posting = false
        default: throw RowRefused(reason: .unexpectedValue(field: "Posting (Y/N)"))
        }
        let name = try required(f[4], field: "Name")
        let account = try required(f[6], field: "Account name")
        let split = try required(f[7], field: "Split")
        let total = try readAmount(f[8], field: "Amount")
        return QuickBooksPaymentRow(row: record.row, date: date, number: f[2].isEmpty ? nil : f[2],
                                    posting: posting, name: name, memo: f[5], account: account,
                                    split: split, amount: total)
    }

    /// Every row sharing an invoice number is refused, each naming them all.
    ///
    /// BOTH, NOT THE SECOND. Which of two rows is the real invoice is not
    /// something the file says, and reconciling by number with either one
    /// kept would pair lines with an invoice chosen by row order.
    private static func refusingDuplicateNumbers(
        _ read: QuickBooksFileRead<QuickBooksInvoiceRow>) -> QuickBooksFileRead<QuickBooksInvoiceRow> {
        let rowsByNumber = Dictionary(grouping: read.accepted, by: \.number)
        let shared = rowsByNumber.filter { $0.value.count > 1 }
        guard !shared.isEmpty else { return read }
        var refused = read.refused
        for (_, rows) in shared {
            let numbers = rows.map(\.row)
            refused += numbers.map { QuickBooksRowRefusal(row: $0, reason: .duplicateInvoiceNumber(rows: numbers)) }
        }
        return QuickBooksFileRead(
            fileRefusals: read.fileRefusals, rowsRead: read.rowsRead,
            accepted: read.accepted.filter { shared[$0.number] == nil },
            refused: refused.sorted { $0.row < $1.row }, structureRows: read.structureRows,
            totalCheck: read.totalCheck)
    }

    // MARK: the sales lines, grouped by product

    static func salesLines(_ text: String) -> QuickBooksFileRead<QuickBooksLineRow> {
        let report = QuickBooksReport.salesLines
        let frame = frame(text, report: report)
        guard frame.headerAsMeasured else { return .refused(.headerNotAsMeasured) }

        var refusals = frame.refusals
        var accepted: [QuickBooksLineRow] = []
        var refused: [QuickBooksRowRefusal] = []
        var amounts: [Money?] = []
        var structure = 0
        var groups: [String] = []
        var nestingBroken = false

        func breakNesting(at row: Int) {
            guard !nestingBroken else { return }
            nestingBroken = true
            refusals.append(.groupsDoNotNest(row: row))
        }

        for record in frame.body {
            let f = record.fields
            if isBlank(record) { structure += 1; continue }
            let label = f.first ?? ""
            let restEmpty = f.dropFirst().allSatisfy(\.isEmpty)

            if label.hasPrefix("Total for ") {
                structure += 1
                let closing = String(label.dropFirst("Total for ".count))
                if let open = groups.last, closing == open || closing == open + " with sub-items" {
                    groups.removeLast()
                } else if !(groups.isEmpty && closing == "--") {
                    breakNesting(at: record.row)
                }
                continue
            }
            if !label.isEmpty && restEmpty && f.count == report.header.count {
                structure += 1
                groups.append(label)
                continue
            }

            amounts.append(rawAmount(of: record, report: report))
            do {
                try checkShape(record, report: report)
                guard label.isEmpty else { throw RowRefused(reason: .unexpectedValue(field: "the first column")) }
                accepted.append(try line(from: record, product: nestingBroken ? nil : groups.last))
            } catch let refusal as RowRefused {
                refused.append(QuickBooksRowRefusal(row: record.row, reason: refusal.reason))
            } catch {
                refused.append(QuickBooksRowRefusal(row: record.row, reason: .malformedQuoting))
            }
        }
        if let total = frame.total, !groups.isEmpty { breakNesting(at: total.row) }
        refusals += basisRefusals(frame, report: report)

        return QuickBooksFileRead(fileRefusals: refusals, rowsRead: accepted.count + refused.count,
                                  accepted: accepted, refused: refused, structureRows: structure,
                                  totalCheck: totalCheck(frame, report: report, amounts: amounts))
    }

    private static func line(from record: QuickBooksCSV.Record, product: String?) throws -> QuickBooksLineRow {
        let f = record.fields
        let date = try scopedDate(f[1], field: "Transaction date")
        guard f[2] == "Invoice" else { throw RowRefused(reason: .unexpectedValue(field: "Transaction type")) }
        let number = try invoiceNumber(f[3], field: "Num")
        let client = try required(f[4], field: "Client full name")
        let total = try readAmount(f[8], field: "Amount")

        var quantity: Int64?
        var price: Money?
        switch (f[6].isEmpty, f[7].isEmpty) {
        case (true, true):
            break
        case (false, true):
            throw RowRefused(reason: .missing(field: "Sales price"))
        case (true, false):
            throw RowRefused(reason: .missing(field: "Quantity"))
        case (false, false):
            guard let hundredths = figure(f[6]) else { throw RowRefused(reason: .unreadableAmount(field: "Quantity")) }
            let rate = try readAmount(f[7], field: "Sales price")
            // What Ovation itself would charge for these inputs, through the one
            // rounding rule, rather than a second multiplication written here.
            guard Money.charge(for: Hours(hundredths: hundredths), at: rate) == total else {
                throw RowRefused(reason: .amountIsNotQuantityTimesPrice)
            }
            quantity = hundredths
            price = rate
        }
        return QuickBooksLineRow(row: record.row, date: date, number: number, clientName: client, product: product,
                                 description: f[5], quantityHundredths: quantity, salesPrice: price, amount: total)
    }

    // MARK: invoices and received payments, grouped by client

    static func invoicesAndPayments(_ file: QuickBooksCustodyFile, in folder: URL)
        -> QuickBooksFileRead<QuickBooksLedgerRow> {
        switch verifiedData(file, in: folder) {
        case .success(let data): return invoicesAndPayments(data)
        case .failure(let refusal): return .refused(refusal.refusal)
        }
    }

    static func invoicesAndPayments(_ data: Data) -> QuickBooksFileRead<QuickBooksLedgerRow> {
        guard let text = String(data: data, encoding: .utf8) else { return .refused(.notUTF8) }
        return invoicesAndPayments(text)
    }

    static func invoicesAndPayments(_ text: String) -> QuickBooksFileRead<QuickBooksLedgerRow> {
        let report = QuickBooksReport.invoicesAndPayments
        let frame = frame(text, report: report)
        guard frame.headerAsMeasured else { return .refused(.headerNotAsMeasured) }

        var accepted: [QuickBooksLedgerRow] = []
        var refused: [QuickBooksRowRefusal] = []
        var structure = 0
        var group: (row: Int, client: String)?
        for record in frame.body {
            let f = record.fields
            if isBlank(record) { structure += 1; continue }
            let label = f.first ?? ""
            if !label.isEmpty && f.dropFirst().allSatisfy(\.isEmpty) && f.count == report.header.count {
                structure += 1
                group = (record.row, label)
                continue
            }
            do {
                try checkShape(record, report: report)
                guard label.isEmpty else { throw RowRefused(reason: .unexpectedValue(field: "the first column")) }
                guard let group else { throw RowRefused(reason: .outsideAnyGroup) }
                accepted.append(try ledgerRow(from: record, group: group))
            } catch let refusal as RowRefused {
                refused.append(QuickBooksRowRefusal(row: record.row, reason: refusal.reason))
            } catch {
                refused.append(QuickBooksRowRefusal(row: record.row, reason: .malformedQuoting))
            }
        }
        return QuickBooksFileRead(fileRefusals: frame.refusals, rowsRead: accepted.count + refused.count,
                                  accepted: accepted, refused: refused, structureRows: structure,
                                  totalCheck: totalCheck(frame, report: report, amounts: []))
    }

    private static func ledgerRow(from record: QuickBooksCSV.Record,
                                  group: (row: Int, client: String)) throws -> QuickBooksLedgerRow {
        let f = record.fields
        let date = try scopedDate(f[1], field: "Date")
        let kind: QuickBooksLedgerRow.Kind
        switch f[2] {
        case "Invoice": kind = .invoice
        case "Payment": kind = .payment
        default: throw RowRefused(reason: .unexpectedValue(field: "Transaction type"))
        }
        // An invoice must carry its number, since that is what ties it to the
        // invoice list. A payment carries none on every measured row; one that
        // does is read, and refused if it is not a number.
        var number: Int64?
        if kind == .invoice || !f[4].isEmpty {
            number = try invoiceNumber(f[4], field: "Transaction number")
        }
        let amount = try readAmount(f[5], field: "Amount")
        return QuickBooksLedgerRow(row: record.row, groupRow: group.row, client: group.client, date: date,
                                   kind: kind, number: number, memo: f[3], amount: amount)
    }

    // MARK: the basis

    /// The sales lines report must say it was run on accrual basis, the basis
    /// Ovation's figures are kept on (PRD 5.24). The other two reports list
    /// transactions whole and state no basis, measured.
    private static func basisRefusals(_ frame: Frame, report: QuickBooksReport) -> [QuickBooksFileRefusal] {
        guard report == .salesLines, let timestamp = frame.timestamp else { return [] }
        if timestamp.hasPrefix("Accrual Basis") { return [] }
        if timestamp.hasPrefix("Cash Basis") { return [.cashBasis] }
        return [.basisNotStated]
    }

    // MARK: values

    private static func required(_ value: String, field: String) throws -> String {
        guard !value.isEmpty else { throw RowRefused(reason: .missing(field: field)) }
        return value
    }

    private static func invoiceNumber(_ value: String, field: String) throws -> Int64 {
        guard !value.isEmpty else { throw RowRefused(reason: .missing(field: field)) }
        guard value.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int64(value) else {
            throw RowRefused(reason: .unreadableInvoiceNumber(field: field))
        }
        return number
    }

    private static func scopedDate(_ value: String, field: String) throws -> BusinessDate {
        let date = try readDate(value, field: field)
        guard date.dayKey >= firstDayKey else { throw RowRefused(reason: .beforeScope(field: field)) }
        return date
    }

    /// M/D/YYYY, the only date shape measured in any of the three files, into a
    /// business day. A day that does not exist is refused by the calendar rather
    /// than rolled into the next month.
    private static func readDate(_ value: String, field: String) throws -> BusinessDate {
        guard !value.isEmpty else { throw RowRefused(reason: .missing(field: field)) }
        guard let match = value.wholeMatch(of: /(\d{1,2})\/(\d{1,2})\/(\d{4})/),
              let month = Int(match.1), let day = Int(match.2), let year = Int(match.3),
              let date = BusinessCalendar.day(forKey: String(format: "%04d-%02d-%02d", year, month, day)) else {
            throw RowRefused(reason: .unreadableDate(field: field))
        }
        return date
    }

    private static func readAmount(_ value: String, field: String) throws -> Money {
        guard !value.isEmpty else { throw RowRefused(reason: .missing(field: field)) }
        guard let money = amount(value) else { throw RowRefused(reason: .unreadableAmount(field: field)) }
        return money
    }

    /// Two decimals exactly, an optional minus, and thousands commas only where
    /// thousands fall. A currency symbol is accepted only on a TOTAL, which is
    /// the one place the export writes one.
    private static func amount(_ value: String, allowingCurrencySymbol: Bool = false) -> Money? {
        var text = value
        if allowingCurrencySymbol {
            if text.hasPrefix("-$") { text = "-" + text.dropFirst(2) } else if text.hasPrefix("$") { text.removeFirst() }
        }
        return figure(text).map(Money.init(cents:))
    }

    /// A figure in the measured shape, as hundredths, through the app's one
    /// figure reader once the shape has been checked (L370). The shape check is
    /// what refuses: `Hundredths.read` rounds a third decimal, which here would
    /// be coercion.
    private static func figure(_ value: String) -> Int64? {
        guard value.wholeMatch(of: /-?(\d{1,3}(,\d{3})+|\d+)\.\d{2}/) != nil else { return nil }
        return Hundredths.read(value)
    }
}
