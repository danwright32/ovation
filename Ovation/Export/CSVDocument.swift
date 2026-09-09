// ovation#61, PRD 23 to 25a. The CSV writer the year end export produces its two
// files with.
//
// CSV IS A FORMAT WITH TRAPS AND THEY ALL INVOLVE REAL CLIENT NAMES: a comma in a
// business name, an apostrophe that arrives as a quote, a note pasted with a
// newline in it, an ensemble whose name is not ASCII. Each of those is ordinary
// in the data this exports, so the rule is decided once, here, rather than at
// each call site where the next writer would decide it again slightly
// differently (L613).
//
// THERE ARE TWO KINDS OF FIELD AND THAT IS THE WHOLE DESIGN. A value that came
// from OUTSIDE Ovation (a client name, a vendor, a note) is neutralised when it
// opens with a character a spreadsheet evaluates as a formula. A value OVATION
// FORMATTED (an amount, a date key, a state label) is not, because it is safe by
// construction and because neutralising it would corrupt it: a negative amount
// opens with a minus sign, and prefixing that turns money into text no
// spreadsheet will total (L104).
//
// The caller therefore has to say which kind each field is, at every call site,
// and cannot get the safe behaviour by accident. That is deliberate: a single
// `String` parameter with the escaping decided inside would make the wrong
// answer the quiet one.
import Foundation

struct CSVDocument: Equatable, Sendable {

    /// One cell, and where its value came from.
    enum Field: Equatable, Sendable {
        /// It came from outside Ovation. Neutralised if it opens with a formula
        /// character.
        case text(String)
        /// Ovation produced this string itself: an amount, a day key, a label
        /// from a vocabulary. Written exactly as given.
        case formatted(String)
    }

    /// Ovation's own column names, so they are `formatted` by definition.
    let header: [String]
    let rows: [[Field]]

    var rowCount: Int { rows.count }

    /// Rows whose field count does not match the header, by index.
    ///
    /// A SHORT ROW STILL PARSES, which is what makes it dangerous: every column
    /// after the gap shifts, and the accountant reads a plausible number in the
    /// wrong column. Reported rather than padded, because padding would produce
    /// exactly that file and call it fixed.
    var raggedRows: [Int] {
        rows.indices.filter { rows[$0].count != header.count }
    }

    var isWellFormed: Bool { raggedRows.isEmpty }

    /// The document as text, with no byte order mark. `data` is what gets
    /// written to disk.
    var text: String {
        var out = header.map { Self.render(field: .formatted($0)) }.joined(separator: ",")
        out += Self.lineEnding
        for row in rows {
            out += row.map { Self.render(field: $0) }.joined(separator: ",")
            out += Self.lineEnding
        }
        return out
    }

    /// What is written to disk: the text, opened with a UTF-8 byte order mark.
    ///
    /// THE MARK IS FOR EXCEL. It reads a UTF-8 file without one as the system's
    /// legacy encoding, which turns an accented name into mojibake in the one
    /// column a person actually reads. Three bytes, and every other reader
    /// tolerates them.
    var data: Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    /// RFC 4180 says CRLF, and a spreadsheet is the reader here rather than a
    /// unix pipe.
    static let lineEnding = "\r\n"

    /// A cell opening with one of these is read as an expression to evaluate
    /// rather than as text. Tab and carriage return are on the list because a
    /// spreadsheet strips them and then reads whatever is behind them.
    ///
    /// SCALARS, NOT CHARACTERS, AND THAT IS MEASURED RATHER THAN STYLE. Swift
    /// groups a carriage return and the newline after it into ONE Character, so
    /// `"a\r\nb".contains("\r")` is FALSE and a value carrying a CRLF went out
    /// unquoted, splitting the row. The round trip test caught it, which is what
    /// an independent reader is for (L52, L70).
    static let formulaOpeners: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]

    static func render(field: Field) -> String {
        switch field {
        case .formatted(let value):
            return quoteIfNeeded(value)
        case .text(let value):
            return quoteIfNeeded(neutralised(value))
        }
    }

    /// Prefixes an apostrophe when the value OPENS with a formula character.
    ///
    /// ONLY AT THE START, because a formula is only a formula there. A rule that
    /// fired on any occurrence would rewrite "Smith + Jones Duo", which is a name
    /// (L104).
    ///
    /// NOTHING IS DELETED. Dropping the character would silently change a name;
    /// the prefix is visible in the cell and reversible by eye. That is the trade,
    /// and it is made in favour of never editing Dan's data on the way out.
    private static func neutralised(_ value: String) -> String {
        guard let first = value.unicodeScalars.first,
              formulaOpeners.contains(first) else { return value }
        return "'" + value
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        let scalars = value.unicodeScalars
        let needsQuotes = scalars.contains(",")
            || scalars.contains("\"")
            || scalars.contains("\n")
            || scalars.contains("\r")
            || scalars.first == " "
            || scalars.last == " "
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
