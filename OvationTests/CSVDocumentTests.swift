import Foundation
import Testing

/// ovation#61. The CSV writer, and the traps that all involve real client names.
///
/// EVERY ONE OF THESE IS ORDINARY IN THE DATA THIS EXPORTS. A comma in a business
/// name, an apostrophe that arrives as a quote, a note somebody pasted with a
/// newline in it, an ensemble whose name is not ASCII. Tested against values
/// shaped like the real ones rather than against clean fixtures (L48), which for
/// a public repository means values shaped like them and invented.
///
/// THE TWO KINDS OF FIELD ARE THE WHOLE DESIGN. A value that came from outside
/// Ovation is neutralised if it opens with a character a spreadsheet reads as a
/// formula. A value OVATION formatted is not, because it is safe by construction
/// and because the neutralising would corrupt it: a negative amount opens with a
/// minus sign, and prefixing that would turn money into text (L104).
struct CSVDocumentTests {

    // MARK: quoting

    @Test("a plain value is written as it stands")
    func aPlainValueIsUnquoted() {
        #expect(CSVDocument.render(field: .text("Ashgrove Chamber Players"))
                == "Ashgrove Chamber Players")
    }

    @Test("a comma forces quotes, because otherwise it makes a second column")
    func acommaIsQuoted() {
        #expect(CSVDocument.render(field: .text("Ashgrove, Chamber Players"))
                == "\"Ashgrove, Chamber Players\"")
    }

    @Test("a quote is doubled and the field is quoted")
    func aquoteIsDoubled() {
        // RFC 4180. A single quote left as it stands ends the field early and
        // every column after it on that row shifts, which reads as a corrupt row
        // rather than as an escaping fault.
        #expect(CSVDocument.render(field: .text("The \"Ashgrove\" Players"))
                == "\"The \"\"Ashgrove\"\" Players\"")
    }

    @Test("a newline inside a value is kept, quoted, rather than splitting the row")
    func anewlineIsQuotedAndKept() {
        // A note pasted from an email is the ordinary case. Dropping the newline
        // would silently change what Dan wrote, and leaving it unquoted would
        // make one row into two, which totals differently and looks like data.
        let rendered = CSVDocument.render(field: .text("first line\nsecond line"))
        #expect(rendered == "\"first line\nsecond line\"")
        #expect(rendered.contains("\n"))
    }

    @Test("a carriage return is treated the same way as a newline")
    func acarriageReturnIsQuoted() {
        #expect(CSVDocument.render(field: .text("first\r\nsecond")).hasPrefix("\""))
    }

    @Test("a leading space or trailing space is preserved, quoted")
    func surroundingSpaceIsKept() {
        // Trimming here would be Ovation editing Dan's data on the way out, and
        // the export is evidence rather than a tidy-up.
        #expect(CSVDocument.render(field: .text(" Ashgrove ")) == "\" Ashgrove \"")
    }

    @Test("an empty value is an empty field, not the word empty")
    func anemptyValueIsEmpty() {
        #expect(CSVDocument.render(field: .text("")) == "")
    }

    // MARK: the formula characters

    @Test("a value that OPENS with a formula character is neutralised, every one of them")
    func formulaCharactersAreNeutralised() {
        // A spreadsheet treats a cell opening with any of these as an expression
        // to evaluate rather than as text, and the value came from outside
        // Ovation. Enumerated rather than tested on one example, because a rule
        // written for the character somebody thought of leaves the others (L104).
        for opener in ["=", "+", "-", "@", "\t", "\r"] {
            let rendered = CSVDocument.render(field: .text("\(opener)cmd"))
            #expect(rendered.contains("'\(opener)cmd"),
                    Comment(rawValue: "a value opening with \(opener.debugDescription) was not neutralised"))
        }
    }

    @Test("the neutralising keeps the whole original value, and only prefixes it")
    func nothingIsDeletedByTheNeutralising() {
        // The alternative, dropping the character, would silently change a name.
        // A prefixed apostrophe is visible in the cell and reversible by eye,
        // which is the trade being made and it is worth stating (L192).
        let rendered = CSVDocument.render(field: .text("-Ensemble"))
        #expect(rendered.contains("-Ensemble"))
    }

    @Test("a formula character anywhere but the START is left alone")
    func amidValueEqualsIsNotAFormula() {
        // "Smith + Jones Duo" is a name, and a rule that fired on any occurrence
        // would rewrite ordinary values everywhere (L104).
        #expect(CSVDocument.render(field: .text("Smith + Jones Duo")) == "Smith + Jones Duo")
    }

    @Test("a value OVATION formatted is never neutralised, and a negative amount proves it")
    func formattedValuesAreNotNeutralised() {
        // The reason the two kinds of field exist. A refund line opens with a
        // minus sign, and prefixing it would turn every negative amount into text
        // that no spreadsheet will total. Safe by construction: nothing outside
        // Ovation produced it.
        #expect(CSVDocument.render(field: .formatted("-125.00")) == "-125.00")
        #expect(CSVDocument.render(field: .formatted("=SUM")) == "=SUM",
                "the caller is claiming this value is Ovation's own")
    }

    // MARK: the document

    @Test("a document is the header then the rows, ended the way the format says")
    func adocumentHasAHeaderAndCRLFLineEndings() {
        let document = CSVDocument(header: ["A", "B"],
                                   rows: [[.text("one"), .formatted("2.00")]])
        #expect(document.text == "A,B\r\none,2.00\r\n")
    }

    @Test("the file opens with a byte order mark, so a non ASCII name survives Excel")
    func theDocumentCarriesABOM() {
        // The accountant opens this in a spreadsheet, and Excel reads a UTF-8
        // file with no mark as the system's legacy encoding, which turns an
        // accented name into mojibake in the one column a person reads. The mark
        // is three bytes and every other reader tolerates it.
        let document = CSVDocument(header: ["Client"], rows: [[.text("Ensemble Éclat")]])
        let bytes = [UInt8](document.data)
        #expect(Array(bytes.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(decoding: document.data, as: UTF8.self).contains("Ensemble Éclat"))
    }

    @Test("a document with no rows is still a document, with its header")
    func anemptyDocumentKeepsItsHeader() {
        // An export that found nothing must still produce a file a person can
        // open and see the columns of. A zero byte file is indistinguishable from
        // a failed write (L98); saying "no rows" is ovation#64's job and this is
        // the half that does not lie about it.
        let document = CSVDocument(header: ["A", "B"], rows: [])
        #expect(document.text == "A,B\r\n")
        #expect(document.rowCount == 0)
    }

    @Test("a row with the wrong number of fields is REFUSED rather than written short")
    func araggedRowIsRefused() {
        // A short row shifts every column after it and still parses, so it
        // reaches the accountant as a plausible number in the wrong column. The
        // refusal names the row.
        let document = CSVDocument(header: ["A", "B", "C"],
                                   rows: [[.text("one"), .text("two")]])
        #expect(document.raggedRows == [0])
        #expect(document.isWellFormed == false)
    }

    @Test("a well formed document says so, so the check is not only ever a refusal")
    func awellFormedDocumentSaysSo() {
        let document = CSVDocument(header: ["A", "B"],
                                   rows: [[.text("one"), .text("two")]])
        #expect(document.raggedRows.isEmpty)
        #expect(document.isWellFormed)
    }

    @Test("what it writes can be read back as the values that went in")
    func around_tripSurvivesTheHardValues() throws {
        // The end to end check on all of the above: every trap in one row, parsed
        // back by something that is not the writer. A writer tested only against
        // its own expectations proves it is self consistent (L70).
        let hard = ["Ashgrove, Chamber Players",
                    "The \"Ashgrove\" Players",
                    "first line\nsecond line",
                    "=cmd|' /C calc'!A0",
                    "Ensemble Éclat",
                    " leading and trailing "]
        let document = CSVDocument(header: hard.indices.map { "c\($0)" },
                                   rows: [hard.map { CSVDocument.Field.text($0) }])

        let parsed = try #require(Self.parse(document.text))
        #expect(parsed.count == 2, "a header row and one data row, whatever is inside them")
        let row = parsed[1]
        #expect(row.count == hard.count, "the newline and the commas did not split the row")
        for (index, original) in hard.enumerated() where !original.hasPrefix("=") {
            #expect(row[index] == original,
                    Comment(rawValue: "column \(index) did not survive the round trip"))
        }
        #expect(row[3] == "'=cmd|' /C calc'!A0",
                "the formula opener came back neutralised, which is the one deliberate change")
    }

    // MARK: an independent parser, deliberately not the writer's own logic

    /// A minimal RFC 4180 reader, written to check the writer rather than shared
    /// with it. Two implementations that disagree are what this catches; one
    /// implementation checking itself catches nothing (L52, L70).
    private static func parse(_ text: String) -> [[String]]? {
        // OVER SCALARS, NOT CHARACTERS. Swift groups CRLF into one Character, so
        // a reader written over Characters never matches a bare "\r" and joins
        // every row into one. Measured here rather than reasoned about: the first
        // version of this parser did exactly that.
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var pending: Unicode.Scalar?

        func endField() { row.append(String(field)); field = String.UnicodeScalarView() }
        func endRow() { endField(); rows.append(row); row = [] }

        for scalar in text.unicodeScalars {
            if let previous = pending {
                pending = nil
                if previous == "\"" {
                    if scalar == "\"" {
                        field.append("\"")
                        continue
                    }
                    inQuotes = false
                    // fall through and handle this scalar normally
                }
            }
            if inQuotes {
                if scalar == "\"" { pending = "\"" } else { field.append(scalar) }
                continue
            }
            switch scalar {
            case "\"": inQuotes = true
            case ",": endField()
            case "\r": endRow()
            case "\n": if rows.isEmpty || !(row.isEmpty && field.isEmpty) { endRow() }
            default: field.append(scalar)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
