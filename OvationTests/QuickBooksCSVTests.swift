import Foundation
import Testing

/// ovation#67. Reading CSV the way QuickBooks writes it.
///
/// Every trap here is ordinary in the real export: a comma inside a quoted
/// field, a doubled quote, a newline inside a note, CRLF line endings, an empty
/// line between the preamble and the header. The row a record is numbered by is
/// the RECORD's position, which is the row a spreadsheet shows Dan, not the
/// physical line a text editor would.
struct QuickBooksCSVTests {

    @Test("a comma inside quotes stays in its field")
    func aQuotedCommaIsOneField() {
        let csv = QuickBooksCSV.parse("a,\"Fictive, Quartet\",c\r\n")
        #expect(csv.records.map(\.fields) == [["a", "Fictive, Quartet", "c"]])
    }

    @Test("a doubled quote is one quote, and a newline inside quotes is kept")
    func quotesAndNewlinesInsideAField() {
        let csv = QuickBooksCSV.parse("\"The \"\"Imaginary\"\" Players\",\"two\r\nlines\"\r\nnext,row\r\n")
        #expect(csv.records.map(\.fields) == [["The \"Imaginary\" Players", "two\r\nlines"], ["next", "row"]])
        // The second record is the spreadsheet's row 2 even though it starts on
        // the third physical line.
        #expect(csv.records.map(\.row) == [1, 2])
    }

    @Test("an empty line is an empty record rather than being skipped, so rows keep their numbers")
    func anEmptyLineKeepsItsRow() {
        let csv = QuickBooksCSV.parse("a,b\r\n\r\nc,d\n")
        #expect(csv.records.map(\.fields) == [["a", "b"], [], ["c", "d"]])
        #expect(csv.records.map(\.row) == [1, 2, 3])
    }

    @Test("a quote that never closes stops the read at its row and says so")
    func anUnterminatedQuoteIsNamed() {
        let csv = QuickBooksCSV.parse("a,b\r\nc,\"never closed\r\nd,e\r\n")
        #expect(csv.records.map(\.fields) == [["a", "b"]])
        #expect(csv.unterminatedFromRow == 2)
    }

    @Test("text after a closing quote marks the record malformed rather than being glued on")
    func textAfterAClosingQuoteIsMalformed() {
        let csv = QuickBooksCSV.parse("\"abc\"x,d\r\nok,row\r\n")
        #expect(csv.records.map(\.malformed) == [true, false])
    }

    @Test("a leading formula character is read as the text it is")
    func aLeadingFormulaCharacterIsText() {
        let csv = QuickBooksCSV.parse("=Imaginary Opera,+Plus Trio,-Minus Duo,@At Ensemble\r\n")
        #expect(csv.records.first?.fields == ["=Imaginary Opera", "+Plus Trio", "-Minus Duo", "@At Ensemble"])
    }
}
