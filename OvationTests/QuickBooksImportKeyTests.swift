import CryptoKit
import Foundation
import Testing

/// ovation#68. The key an imported row is written under: the file it came from, the
/// row exactly as it stood in that file, and the version of the importer that read
/// it.
///
/// THE VERSION IS THE PART THAT IS EASY TO LEAVE OUT, and the reason the key works
/// at all: a corrected parser is a different key, so it can re-run over the same
/// file instead of being blocked by its own earlier mistake (L121).
///
/// THE ROW IS THE RAW ROW, before any unquoting or reading. Hashing the parsed
/// result would make two files that parse alike collide, and would move every key
/// whenever the parser changed while its version did not.
struct QuickBooksImportKeyTests {

    private typealias F = QuickBooksFixture
    private typealias Source = QuickBooksImportKey.Source

    @Test("the same file, row and version make the same key, so a re-run finds what it wrote")
    func theSameInputsMakeTheSameKey() {
        let sources = [Source(fileSHA256: "a1", row: 6, rawRowSHA256: "b2")]
        #expect(QuickBooksImportKey(version: 1, sources: sources) == QuickBooksImportKey(version: 1, sources: sources))
    }

    @Test("a corrected importer makes a different key over the same file and row")
    func anotherVersionIsAnotherKey() {
        let sources = [Source(fileSHA256: "a1", row: 6, rawRowSHA256: "b2")]
        #expect(QuickBooksImportKey(version: 1, sources: sources) != QuickBooksImportKey(version: 2, sources: sources))
        #expect(QuickBooksImportKey(sources: sources).value.hasPrefix("quickbooks-v\(QuickBooksImportKey.importerVersion):"))
    }

    @Test("another file or another row is another key")
    func anotherFileOrRowIsAnotherKey() {
        let base = QuickBooksImportKey(version: 1, sources: [Source(fileSHA256: "a1", row: 6, rawRowSHA256: "b2")])
        #expect(base != QuickBooksImportKey(version: 1, sources: [Source(fileSHA256: "a9", row: 6, rawRowSHA256: "b2")]))
        #expect(base != QuickBooksImportKey(version: 1, sources: [Source(fileSHA256: "a1", row: 6, rawRowSHA256: "b9")]))
        // EVERY CONTRIBUTING ROW COUNTS: an invoice whose lines changed in the
        // sales lines file is a different invoice to import, even though its row in
        // the invoice list did not move.
        #expect(base != QuickBooksImportKey(version: 1, sources: [Source(fileSHA256: "a1", row: 6, rawRowSHA256: "b2"),
                                                                   Source(fileSHA256: "c3", row: 7, rawRowSHA256: "d4")]))
    }

    @Test("the same text on another row of the same file is another row")
    func theRowNumberIsPartOfTheKey() {
        // REVIEW OF 1e824ef (L186). Two payments with the same date and amount read
        // as the same text, under different clients or under one; without where each
        // sits, the second one's key is the first one's, and it is refused as
        // already imported though it was never written.
        let first = QuickBooksImportKey(version: 1, sources: [Source(fileSHA256: "a1", row: 8, rawRowSHA256: "b2")])
        let second = QuickBooksImportKey(version: 1, sources: [Source(fileSHA256: "a1", row: 11, rawRowSHA256: "b2")])
        #expect(first != second)
    }

    @Test("a record keeps its raw text, quotes and all, without its line ending")
    func aRecordKeepsItsRawText() {
        let csv = QuickBooksCSV.parse("a,\"Fictive, \"\"Quartet\"\"\",c\r\n\"two\r\nlines\",x\r\n\r\nlast")
        #expect(csv.records.map(\.raw) == ["a,\"Fictive, \"\"Quartet\"\"\",c", "\"two\r\nlines\",x", "", "last"])
    }

    @Test("two rows that read alike but were written differently hash differently")
    func theHashIsOfTheRawRow() throws {
        // `100.00` and `"100.00"` read as the same amount. They are not the same row.
        let plain = QuickBooksExport.invoiceList(F.invoiceList([F.invoice(amount: "100.00")], total: "$100.00"))
        let quoted = QuickBooksExport.invoiceList(F.invoiceList([F.invoice(amount: "\"100.00\"")], total: "$100.00"))
        let first = try #require(plain.accepted.first)
        let second = try #require(quoted.accepted.first)
        #expect(first.amount == second.amount)
        #expect(first.rawRowSHA256 != second.rawRowSHA256)
        #expect(first.rawRowSHA256 == Self.sha256(F.invoice(amount: "100.00")))
    }

    @Test("the file is identified by its contents, never by where it sits")
    func theFileIsItsContents() throws {
        let text = F.invoiceList([F.invoice()], total: "$100.00")
        let read = QuickBooksExport.invoiceList(text)
        #expect(read.fileSHA256 == QuickBooksCustodyFile.sha256(of: Data(text.utf8)))
        let url = try F.write(text, named: "list.csv")
        let file = QuickBooksCustodyFile(report: .invoiceList, fileName: "list.csv",
                                         sha256: QuickBooksCustodyFile.sha256(of: Data(text.utf8)))
        #expect(QuickBooksExport.invoiceList(file, in: url.deletingLastPathComponent()).fileSHA256 == read.fileSHA256)
    }

    @Test("every typed row carries its raw row's hash")
    func everyRowCarriesItsHash() throws {
        let line = F.line(quantity: "2.00", price: "50.00", amount: "100.00")
        let lines = QuickBooksExport.salesLines(F.salesLines([line, F.groupTotal("--", amount: "$100.00")],
                                                            total: "$100.00"))
        #expect(try #require(lines.accepted.first).rawRowSHA256 == Self.sha256(line))
        let ledger = QuickBooksExport.invoicesAndPayments(F.invoicesAndPayments([
            F.client("Fictive Quartet"), F.ledgerInvoice(), F.ledgerPayment(),
        ]))
        #expect(ledger.accepted.map(\.rawRowSHA256) == [Self.sha256(F.ledgerInvoice()), Self.sha256(F.ledgerPayment())])
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
