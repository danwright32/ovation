// ovation#67. Reading CSV the way QuickBooks writes it, and saying where a read
// stopped rather than returning the part it managed.
//
// NOT THE WRITER'S MIRROR. `CSVDocument` writes, and decides how a value from
// outside Ovation is neutralised for a spreadsheet. Reading has no such
// decision: a leading `=` in a client name is that client's name, so it is read
// as the text it is and kept.
//
// A RECORD IS NUMBERED BY ITS POSITION AMONG RECORDS, which is the row a
// spreadsheet shows when Dan opens the file, and not the physical line: a note
// carrying a newline makes the two differ, and a refusal that names a row Dan
// cannot find is not one he can act on (ovation#67).
//
// A QUOTE THAT NEVER CLOSES ENDS THE READ AT ITS ROW, and the row is reported.
// Everything after it is inside that one runaway field, so the rows after it
// were never reached, and a reader that returned what it had would report a
// short read as a complete one (ovation#72, L211).
import Foundation

struct QuickBooksCSV: Equatable, Sendable {

    struct Record: Equatable, Sendable {
        /// Which record this is, from 1, as a spreadsheet numbers its rows.
        let row: Int
        /// The fields exactly as written, quotes removed and doubled quotes
        /// undoubled. An empty line has no fields at all.
        let fields: [String]
        /// Text followed a closing quote inside a field. The field is not
        /// guessed at: the record is marked, and the caller refuses the row.
        let malformed: Bool
    }

    let records: [Record]

    /// The row whose quoted field never closed, where there was one. Nothing
    /// from that row on was read.
    let unterminatedFromRow: Int?

    static func parse(_ text: String) -> QuickBooksCSV {
        // Unicode scalars rather than Characters, because Swift treats CRLF as
        // ONE Character and a reader looking for CR then LF would never see it.
        var records: [Record] = []
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var afterClosingQuote = false
        var malformed = false
        var lineIsEmpty = true
        var row = 1

        func endField() {
            fields.append(String(field))
            field = String.UnicodeScalarView()
            afterClosingQuote = false
        }
        func endRecord() {
            if lineIsEmpty && fields.isEmpty && field.isEmpty {
                records.append(Record(row: row, fields: [], malformed: false))
            } else {
                endField()
                records.append(Record(row: row, fields: fields, malformed: malformed))
            }
            fields = []
            malformed = false
            lineIsEmpty = true
            row += 1
        }

        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            index += 1
            if inQuotes {
                if scalar == "\"" {
                    if index < scalars.count && scalars[index] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                        afterClosingQuote = true
                    }
                } else {
                    field.append(scalar)
                }
                continue
            }
            switch scalar {
            case ",":
                lineIsEmpty = false
                endField()
            case "\r" where index < scalars.count && scalars[index] == "\n":
                index += 1
                endRecord()
            case "\n", "\r":
                endRecord()
            case "\"" where field.isEmpty && !afterClosingQuote:
                lineIsEmpty = false
                inQuotes = true
            default:
                lineIsEmpty = false
                if afterClosingQuote { malformed = true }
                field.append(scalar)
            }
        }

        if inQuotes {
            return QuickBooksCSV(records: records, unterminatedFromRow: row)
        }
        // A last line with no line ending is still a record.
        if !(lineIsEmpty && fields.isEmpty && field.isEmpty) { endRecord() }
        return QuickBooksCSV(records: records, unterminatedFromRow: nil)
    }
}
