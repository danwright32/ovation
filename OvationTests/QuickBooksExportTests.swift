import Foundation
import Testing

/// ovation#67, PRD 5.27. Every row of the three QuickBooks exports is either read
/// into a typed row or refused by its row number with a reason, and nothing is
/// coerced into a plausible value on the way (L340).
///
/// THE FIXTURES ARE SYNTHETIC AND SHAPED LIKE THE MEASURED FILES (L48), from
/// `QuickBooksFixture`. The malformed row sits in the MIDDLE of a file wherever a
/// test is about one, because a fault planted at the end lets the run finish its
/// real work first and the case under test never occurs (L165).
struct QuickBooksExportTests {

    private typealias F = QuickBooksFixture

    // MARK: the invoice list

    @Test("a well formed invoice list reads every row into a typed invoice")
    func aWellFormedInvoiceListReads() throws {
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            F.invoice("1/19/2026", number: "1001", name: "\"Fictive, Quartet\"", amount: "\"1,134.56\"",
                      open: "0.00"),
            F.invoice("9/13/2026", number: "1002", name: "Ensemble \u{00C9}lan Fictif", memo: "Imaginary gala",
                      due: "10/13/2026", amount: "100.00", open: "100.00"),
        ], total: "\"$1,234.56\"", openBalance: "$100.00"))

        #expect(read.fileRefusals.isEmpty)
        #expect(read.totalCheck == .agrees)
        #expect(read.rowsRead == 2)
        #expect(read.refused.isEmpty)
        let first = try #require(read.accepted.first)
        #expect(first.row == 6)
        #expect(first.date.dayKey == "2026-01-19")
        #expect(first.number == 1001)
        #expect(first.name == "Fictive, Quartet")
        #expect(first.amount == Money(cents: 113_456))
        let second = try #require(read.accepted.last)
        #expect(second.name == "Ensemble \u{00C9}lan Fictif")
        #expect(second.memo == "Imaginary gala")
        #expect(second.dueDate.dayKey == "2026-10-13")
        #expect(second.openBalance == Money(cents: 10_000))
    }

    @Test("a malformed row in the middle is refused by row and field, and the rows after it still read")
    func aMalformedRowInTheMiddleIsRefusedByName() {
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            F.invoice(number: "1001", amount: "100.00"),
            F.invoice(number: "1002", amount: "\"$1,000.00\""),
            F.invoice(number: "1003", amount: "1134.56"),
        ], total: "\"$2,234.56\""))

        #expect(read.refused == [QuickBooksRowRefusal(row: 7, reason: .unreadableAmount(field: "Amount"))])
        #expect(read.accepted.map(\.number) == [1001, 1003])
        #expect(read.accepted.map(\.row) == [6, 8])
    }

    @Test("an amount with more than two decimals is refused, never rounded")
    func threeDecimalsAreRefused() {
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            F.invoice(number: "1001", amount: "100.005"),
            F.invoice(number: "1002", amount: "1234.56"),
        ], total: "\"$1,234.56\""))
        #expect(read.refused == [QuickBooksRowRefusal(row: 6, reason: .unreadableAmount(field: "Amount"))])
    }

    @Test("a date in another format, and a day that does not exist, are each refused by field")
    func unreadableDatesAreRefused() {
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            F.invoice("2026-01-19", number: "1001", amount: "0.00"),
            F.invoice("2/30/2026", number: "1002", amount: "0.00"),
            F.invoice(number: "1003", due: "13/1/2026", amount: "1234.56"),
        ], total: "\"$1,234.56\""))
        #expect(read.refused == [
            QuickBooksRowRefusal(row: 6, reason: .unreadableDate(field: "Date")),
            QuickBooksRowRefusal(row: 7, reason: .unreadableDate(field: "Date")),
            QuickBooksRowRefusal(row: 8, reason: .unreadableDate(field: "Due date")),
        ])
    }

    @Test("a row dated before 2026 is refused by name and counted, never dropped")
    func aRowBefore2026IsRefusedNotDropped() {
        // Dan, 2026-09-26 (ovation#118): Ovation's record starts with 2026.
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            F.invoice("1/19/2026", number: "1001", amount: "1000.00"),
            F.invoice("12/31/2025", number: "0999", amount: "134.56"),
            F.invoice("1/1/2026", number: "1002", amount: "100.00"),
        ], total: "\"$1,234.56\""))
        #expect(read.refused == [QuickBooksRowRefusal(row: 7, reason: .beforeScope(field: "Date"))])
        #expect(read.accepted.map(\.number) == [1001, 1002])
        #expect(read.rowsRead == 3)
    }

    @Test("a row with the wrong number of fields is refused rather than read shifted")
    func aShortRowIsRefused() {
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            F.invoice(number: "1001", amount: "1234.56"),
            "1/20/2026,Invoice,1002,Fictive Quartet,,2/19/2026,0.00",
        ], total: "\"$1,234.56\""))
        #expect(read.refused == [QuickBooksRowRefusal(row: 7, reason: .fieldCount(expected: 8, found: 7))])
    }

    @Test("a transaction that is not an invoice, and a number that is not a number, are refused")
    func unexpectedTypeAndNumberAreRefused() {
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            "1/19/2026,Credit Memo,1001,Fictive Quartet,,2/18/2026,0.00,0.00",
            F.invoice(number: "INV-7", amount: "0.00"),
            F.invoice(number: "", amount: "0.00"),
            F.invoice(number: "1002", name: "", amount: "0.00"),
            F.invoice(number: "1003", amount: "1234.56"),
        ], total: "\"$1,234.56\""))
        #expect(read.refused == [
            QuickBooksRowRefusal(row: 6, reason: .unexpectedValue(field: "Transaction type")),
            QuickBooksRowRefusal(row: 7, reason: .unreadableInvoiceNumber(field: "Num")),
            QuickBooksRowRefusal(row: 8, reason: .missing(field: "Num")),
            QuickBooksRowRefusal(row: 9, reason: .missing(field: "Name")),
        ])
    }

    @Test("two rows carrying one invoice number are both refused, each naming every row")
    func aDuplicateNumberRefusesBoth() {
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            F.invoice(number: "1001", amount: "1000.00"),
            F.invoice(number: "1002", amount: "134.56"),
            F.invoice(number: "1001", amount: "100.00"),
        ], total: "\"$1,234.56\""))
        #expect(read.accepted.map(\.number) == [1002])
        #expect(read.refused == [
            QuickBooksRowRefusal(row: 6, reason: .duplicateInvoiceNumber(rows: [6, 8])),
            QuickBooksRowRefusal(row: 8, reason: .duplicateInvoiceNumber(rows: [6, 8])),
        ])
    }

    @Test("a leading formula character in a name is kept, and a credit keeps its minus sign")
    func formulaCharactersAndCreditsReadAsTheyStand() {
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            F.invoice(number: "1001", name: "=Imaginary Opera", amount: "1334.56"),
            F.invoice(number: "1002", name: "@At Ensemble", amount: "-100.00", open: "-100.00"),
        ], total: "\"$1,234.56\"", openBalance: "-$100.00"))
        #expect(read.refused.isEmpty)
        #expect(read.accepted.map(\.name) == ["=Imaginary Opera", "@At Ensemble"])
        #expect(read.accepted.last?.amount == Money(cents: -10_000))
    }

    @Test("every data row lands in exactly one of accepted and refused")
    func everyRowLandsInOneBucket() {
        // L517. A row counted twice or in neither makes the report's arithmetic
        // disagree with the file, and nobody would notice from either number alone.
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            F.invoice(number: "1001", amount: "1000.00"),
            F.invoice("12/31/2025", number: "0999", amount: "0.00"),
            F.invoice(number: "1002", amount: "$1.00"),
            F.invoice(number: "1001", amount: "134.56"),
            F.invoice(number: "1003", amount: "100.00"),
            "short,row",
        ], total: "\"$1,234.56\""))
        let rows = read.accepted.map(\.row) + read.refused.map(\.row)
        #expect(read.rowsRead == 6)
        #expect(rows.sorted() == Array(6...11))
    }

    // MARK: the file as a whole

    @Test("a header that is not the measured one refuses the file and reads no rows")
    func anUnmeasuredHeaderRefusesTheFile() {
        let text = F.invoiceList([F.invoice(amount: "1234.56")])
            .replacingOccurrences(of: "Open balance", with: "Balance")
        let read = QuickBooksExport.invoiceList(text)
        #expect(read.fileRefusals == [.headerNotAsMeasured])
        #expect(read.rowsRead == 0)
        #expect(read.accepted.isEmpty)
    }

    @Test("a file with no TOTAL row is refused as possibly cut short")
    func noTotalRowIsNamed() {
        let text = F.invoiceList([F.invoice(amount: "1234.56")])
            .replacingOccurrences(of: "TOTAL,", with: "Summary,")
        let read = QuickBooksExport.invoiceList(text)
        #expect(read.fileRefusals.contains(.noTotalRow))
        #expect(read.totalCheck == .noTotal)
    }

    @Test("a TOTAL that disagrees with the rows read is named with the difference")
    func aTotalThatDisagreesIsNamed() {
        // THE SHORT READ CHECK. A file whose rows do not add up to its own TOTAL
        // was not fully read, or was edited by hand, and either way the rows are
        // not the report QuickBooks produced (ovation#72).
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            F.invoice(number: "1001", amount: "1000.00"),
            F.invoice(number: "1002", amount: "134.56"),
        ], total: "\"$1,234.56\""))
        #expect(read.totalCheck == .disagrees(difference: Money(cents: 10_000)))
        #expect(!read.isAccepted)
    }

    @Test("a TOTAL cannot be checked while a row's amount is unreadable, and says how many")
    func aTotalNotComparableSaysWhy() {
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            F.invoice(number: "1001", amount: "1234.56"),
            F.invoice(number: "1002", amount: "twelve"),
        ], total: "\"$1,234.56\""))
        #expect(read.totalCheck == .notComparable(rowsWithoutAmount: 1))
    }

    @Test("a stray quote in the middle swallows the rows after it, and the read says it lost the TOTAL")
    func aStrayQuoteInTheMiddleIsNotAShortReadThatPasses() {
        // MEASURED ON THE FIXTURE, NOT ASSUMED: the TOTAL and the timestamp line
        // are both quoted, so a quote opened by mistake mid file is CLOSED by the
        // TOTAL's own quote and everything between becomes one field. What gives
        // it away is that the TOTAL row is never found (ovation#72).
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            F.invoice(number: "1001", amount: "1234.56"),
            F.invoice(number: "1002", name: "\"Fictive Quartet", amount: "0.00"),
            F.invoice(number: "1003", amount: "0.00"),
        ], total: "\"$1,234.56\""))
        #expect(read.fileRefusals.contains(.noTotalRow))
        #expect(!read.accepted.contains { $0.number == 1003 })
        #expect(!read.isAccepted)
    }

    @Test("a file whose rows cannot all be totalled is not believed, and says why")
    func aTotalNotComparableRefusesTheFile() {
        // L211. A row whose amount could not be read leaves the TOTAL unchecked,
        // and an unchecked TOTAL is a read nobody has shown was complete.
        let read = QuickBooksExport.invoiceList(F.invoiceList([
            F.invoice(number: "1001", amount: "1234.56"),
            F.invoice(number: "1002", amount: "twelve"),
        ], total: "\"$1,234.56\""))
        #expect(!read.isAccepted)
    }

    @Test("a TOTAL row whose amount cannot be read is its own outcome, and refuses the file")
    func anUnreadableTotalRefusesTheFile() {
        let text = F.invoiceList([F.invoice(amount: "1234.56")], total: "about twelve hundred")
        let read = QuickBooksExport.invoiceList(text)
        #expect(read.totalCheck == .unreadableTotal)
        #expect(!read.isAccepted)
    }

    @Test("a file with no TOTAL row is not believed")
    func noTotalRefusesTheFile() {
        let text = F.invoiceList([F.invoice(amount: "1234.56")])
            .replacingOccurrences(of: "TOTAL,", with: "Summary,")
        #expect(!QuickBooksExport.invoiceList(text).isAccepted)
    }

    @Test("a quote still open at the end of the file names the row the read stopped at")
    func anUnterminatedQuoteNamesWhereTheReadStopped() {
        let text = F.invoiceList([F.invoice(number: "1001", amount: "1234.56")], total: "\"$1,234.56\"")
            + "\"never closed,,,,,,,\r\n"
        let read = QuickBooksExport.invoiceList(text)
        #expect(read.fileRefusals == [.unterminatedQuote(fromRow: 12)])
        #expect(read.accepted.count == 1)
    }

    @Test("anything but empty lines and the timestamp after TOTAL is refused by row")
    func contentAfterTheTotalIsNamed() {
        let text = F.invoiceList([F.invoice(amount: "1234.56")])
            .replacingOccurrences(of: "$0.00\r\n\r\n", with: "$0.00\r\n\(F.invoice(number: "1009"))\r\n")
        let read = QuickBooksExport.invoiceList(text)
        #expect(read.fileRefusals == [.unexpectedAfterTotal(row: 8)])
    }

    @Test("a file that is not UTF-8 is refused by name")
    func notUTF8IsNamed() {
        var data = Data(F.invoiceList([F.invoice(amount: "1234.56")]).utf8)
        data.append(contentsOf: [0xFF, 0xFE])
        #expect(QuickBooksExport.invoiceList(data).fileRefusals == [.notUTF8])
    }

    // MARK: payments

    @Test("a well formed payments export reads every row into a typed payment")
    func paymentsRead() throws {
        let read = QuickBooksExport.payments(F.payments([
            F.payment("1/10/2026", name: "\"Fictive, Quartet\"", amount: "\"1,000.00\""),
            F.payment("9/18/2026", name: "Ensemble \u{00C9}lan Fictif", account: "Imaginary Savings",
                      amount: "234.56"),
        ], total: "\"$1,234.56\""))
        #expect(read.fileRefusals.isEmpty)
        #expect(read.totalCheck == .agrees)
        let first = try #require(read.accepted.first)
        #expect(first.date.dayKey == "2026-01-10")
        #expect(first.name == "Fictive, Quartet")
        #expect(first.posting)
        #expect(first.split == "Accounts Receivable (A/R)")
        #expect(first.amount == Money(cents: 100_000))
        #expect(read.accepted.last?.account == "Imaginary Savings")
    }

    @Test("a posting value that is neither Yes nor No is refused rather than guessed")
    func anUnknownPostingIsRefused() {
        let read = QuickBooksExport.payments(F.payments([
            F.payment(amount: "1000.00"),
            F.payment(posting: "Maybe", amount: "234.56"),
        ], total: "\"$1,234.56\""))
        #expect(read.refused == [QuickBooksRowRefusal(row: 7, reason: .unexpectedValue(field: "Posting (Y/N)"))])
    }

    // MARK: sales lines

    private static let groupedBody = [
        F.heading("Add-Ons"),
        F.heading("Rush Delivery (1 Week)"),
        F.line(number: "1001", quantity: "1.00", price: "150.00", amount: "150.00"),
        F.groupTotal("Rush Delivery (1 Week)", amount: "$150.00"),
        F.groupTotal("Add-Ons with sub-items", amount: "$150.00"),
        F.heading("Photography"),
        F.line(number: "1001", description: "\"Imaginary gala, second act\"", quantity: "2.50",
               price: "150.00", amount: "375.00"),
        F.line(number: "1002", client: "Ensemble \u{00C9}lan Fictif", quantity: "3.00", price: "400.00",
               amount: "\"1,200.00\""),
        F.groupTotal("Photography", amount: "\"$1,575.00\""),
        ",,,,,,,,,",
        F.line(number: "1002", description: "Imaginary discount", amount: "-90.44"),
        F.groupTotal("--", amount: "-$90.44"),
    ]

    @Test("a line takes its product from the innermost open group, and a line in no group has none")
    func linesCarryTheirProduct() throws {
        let read = QuickBooksExport.salesLines(F.salesLines(Self.groupedBody, total: "\"$1,634.56\""))
        #expect(read.fileRefusals.isEmpty)
        #expect(read.totalCheck == .agrees)
        #expect(read.refused.isEmpty)
        #expect(read.rowsRead == 4)
        #expect(read.accepted.map(\.product) == ["Rush Delivery (1 Week)", "Photography", "Photography", nil])
        let hourly = try #require(read.accepted.dropFirst().first)
        #expect(hourly.description == "Imaginary gala, second act")
        #expect(hourly.quantityHundredths == 250)
        #expect(hourly.salesPrice == Money(cents: 15_000))
        #expect(hourly.amount == Money(cents: 37_500))
        let flat = try #require(read.accepted.last)
        #expect(flat.quantityHundredths == nil)
        #expect(flat.salesPrice == nil)
        #expect(flat.amount == Money(cents: -9_044))
        #expect(read.structureRows == 8)
    }

    @Test("a line whose amount is not its quantity times its price is refused")
    func quantityTimesPriceMustBeTheAmount() {
        // VALIDATED AGAINST THE READER (L150). Ovation computes a line's amount
        // from its hours and rate and never stores it, so a line whose amount is
        // anything else cannot be held without changing the money. Measured on
        // the real file: a cash basis report splits one line across the payments
        // that covered it, and each share fails exactly this.
        let read = QuickBooksExport.salesLines(F.salesLines([
            F.heading("Photography"),
            F.line(number: "1001", quantity: "2.50", price: "150.00", amount: "187.50"),
            F.line(number: "1002", quantity: "1.00", price: "1447.06", amount: "1447.06"),
            F.groupTotal("Photography", amount: "\"$1,634.56\""),
        ], total: "\"$1,634.56\""))
        #expect(read.refused == [QuickBooksRowRefusal(row: 7, reason: .amountIsNotQuantityTimesPrice)])
    }

    @Test("a quantity without a price is refused as missing the price")
    func aQuantityWithoutAPriceIsRefused() {
        let read = QuickBooksExport.salesLines(F.salesLines([
            F.line(number: "1001", quantity: "2.00", amount: "300.00"),
            F.groupTotal("--", amount: "$300.00"),
        ], total: "$300.00"))
        #expect(read.refused == [QuickBooksRowRefusal(row: 6, reason: .missing(field: "Sales price"))])
    }

    @Test("a group total that does not close the open group refuses the file at that row")
    func groupsThatDoNotNestAreNamed() {
        let read = QuickBooksExport.salesLines(F.salesLines([
            F.heading("Photography"),
            F.line(number: "1001", amount: "100.00"),
            F.groupTotal("Prints", amount: "$100.00"),
        ], total: "$100.00"))
        #expect(read.fileRefusals == [.groupsDoNotNest(row: 8)])
    }

    @Test("a sales lines report on cash basis is refused, because its rows are shares of lines")
    func aCashBasisReportIsRefused() {
        let read = QuickBooksExport.salesLines(F.salesLines(Self.groupedBody, total: "\"$1,634.56\"",
                                                            basis: "Cash Basis"))
        #expect(read.fileRefusals == [.cashBasis])
        #expect(!read.isAccepted)
    }

    @Test("a sales lines report that states no basis is refused, and an invoice list needs none")
    func aSalesLinesReportMustStateItsBasis() {
        let lines = QuickBooksExport.salesLines(F.salesLines(Self.groupedBody, total: "\"$1,634.56\"", basis: ""))
        #expect(lines.fileRefusals == [.basisNotStated])
        let list = QuickBooksExport.invoiceList(F.invoiceList([F.invoice(amount: "1234.56")]))
        #expect(list.fileRefusals.isEmpty)
    }

    // MARK: reading from custody

    @Test("a file whose hash matches the record is read")
    func aVerifiedFileIsRead() throws {
        let text = F.invoiceList([F.invoice(amount: "1234.56")])
        let url = try F.write(text, named: "list.csv")
        let file = QuickBooksCustodyFile(report: .invoiceList, fileName: "list.csv",
                                         sha256: QuickBooksCustodyFile.sha256(of: Data(text.utf8)))
        let read = QuickBooksExport.invoiceList(file, in: url.deletingLastPathComponent())
        #expect(read.fileRefusals.isEmpty)
        #expect(read.accepted.count == 1)
    }

    @Test("a changed file is refused by hash and nothing in it is read")
    func aMismatchedHashRefusesTheFile() throws {
        let url = try F.write(F.invoiceList([F.invoice(amount: "1234.56")]), named: "list.csv")
        let file = QuickBooksCustodyFile(report: .invoiceList, fileName: "list.csv", sha256: String(repeating: "0", count: 64))
        let read = QuickBooksExport.invoiceList(file, in: url.deletingLastPathComponent())
        #expect(read.fileRefusals == [.hashMismatch])
        #expect(read.rowsRead == 0)
        #expect(read.accepted.isEmpty)
    }

    @Test("an absent file is its own outcome, distinct from a changed one")
    func anAbsentFileIsNamed() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "quickbooks-absent-\(UUID().uuidString)")
        let file = QuickBooksCustodyFile(report: .payments, fileName: "missing.csv", sha256: String(repeating: "0", count: 64))
        #expect(QuickBooksExport.payments(file, in: folder).fileRefusals == [.absent])
    }

    @Test("the recorded files and hashes are the ones docs/CUSTODY.md records")
    func theRecordAgreesWithTheCustodyNote() throws {
        // TWO COPIES OF ONE FACT, and the app cannot read the note at runtime, so
        // this is what keeps them one (L41). The note is what
        // scripts/check-custody-files.sh verifies the files against.
        let note = try Self.custodyNote()
        #expect(QuickBooksCustodyFile.recorded.map(\.report) == [.invoiceList, .payments, .salesLines, .invoicesAndPayments])
        for file in QuickBooksCustodyFile.recorded {
            let heading = try #require(note.range(of: "## \(file.fileName)\n"))
            let rest = note[heading.upperBound...]
            let end = rest.range(of: "\n## ")?.lowerBound ?? rest.endIndex
            #expect(rest[..<end].contains("| SHA-256 | `\(file.sha256)` |"))
        }
    }

    private static func custodyNote(_ file: StaticString = #filePath) throws -> String {
        let repository = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repository.appending(path: "docs/CUSTODY.md"), encoding: .utf8)
    }
}
