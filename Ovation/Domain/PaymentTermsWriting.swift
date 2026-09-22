// ovation#473, PRD 5.7. The terms an invoice is written on, and reading back a
// date somebody typed.
//
// THE DESIGN RECORD SETTLED BOTH, and neither existed in the app.
// `docs/design/invoice.html` draws the due date at the foot as a CONTROL: a
// button showing the date, opening a list of four terms with the day each one
// lands on beside it, and an "Another date..." entry that opens a panel. Until
// this, the due date was a figure the screen printed and nothing could change.
//
// `On receipt` IS A REAL TERM RATHER THAN A ZERO, which the design record says in
// as many words. It is the invoice date itself, and an invoice written on it is a
// different statement from one with no term at all.
//
// READING A DATE IS WHERE THE EDGES ARE, so it is a pure function here rather
// than something the panel does inline, and it is FORGIVING ABOUT WHAT A PERSON
// VARIES AND NOTHING ELSE: the case of the month and the spaces around it. It is
// not forgiving about a day its month does not have, which is the case the design
// record's own note singles out, because date arithmetic rolls 31 September
// forward into 1 October and a date nobody typed would be accepted and then shown
// back as a different day (L50).
import Foundation

/// How long after the invoice date it falls due.
struct PaymentTerm: Equatable, Sendable {
    /// What the control calls it.
    let says: String
    let days: Int

    /// The day this term lands on, counted from the invoice date.
    ///
    /// IN DAYS RATHER THAN SECONDS, through the one day helper, because across a
    /// clock change the two disagree and a due date wrong by a day is a reminder
    /// wrong by a day (L39).
    func from(_ issued: BusinessDate) -> BusinessDate? {
        BusinessCalendar.day(days, after: issued)
    }
}

enum PaymentTerms {

    /// The four the design record draws, in its order.
    static let all: [PaymentTerm] = [
        PaymentTerm(says: "On receipt", days: 0),
        PaymentTerm(says: "7 days", days: 7),
        PaymentTerm(says: "14 days", days: 14),
        PaymentTerm(says: "30 days", days: 30),
    ]

    /// PRD 5.7's default, and what every invoice is created with.
    ///
    /// READ FROM THE LIST rather than written a second time, so the default and
    /// the option a person can pick cannot drift into two different fourteens
    /// (L41).
    static let standard: PaymentTerm = all.first { $0.days == 14 } ?? all[2]

    /// A date a person typed, in the form the screen writes, or nil.
    ///
    /// THE SAME FORM `BusinessCalendar.shortDate` WRITES, and the round trip is
    /// asserted across a whole year rather than on one date, because a writer and
    /// a reader agreeing on one value says nothing about the rest.
    static func read(_ typed: String) -> BusinessDate? {
        let parts = typed
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3,
              let day = Int(parts[0]), (1...31).contains(day),
              let year = Int(parts[2]), (2000...2100).contains(year),
              let month = month(named: String(parts[1]))
        else { return nil }

        // THE DAY IS CHECKED AGAINST ITS OWN MONTH, by building the key and
        // asking the calendar to resolve it, rather than by a table of lengths
        // that would have to know about leap years twice.
        let key = String(format: "%04d-%02d-%02d", year, month, day)
        guard let resolved = BusinessCalendar.day(forKey: key),
              resolved.dayKey == key
        else { return nil }
        return resolved
    }

    /// What the panel says about a value it could not read.
    ///
    /// IT SHOWS THE SHAPE RATHER THAN DESCRIBING IT, in the vocabulary of the
    /// place the person is acting, which is the date already on screen (L399).
    static func refusalSentence(showing day: BusinessDate) -> String {
        let example = BusinessCalendar.shortDate(day) ?? "12 Nov 2026"
        return "Not a date Ovation can read. Write it like \(example)."
    }

    /// Which month a written name is, or nil.
    ///
    /// MATCHED ON THE FIRST THREE LETTERS, so "Nov" and "November" are one
    /// answer: the screen writes the short form and a person may well type the
    /// long one, and refusing the long one would be a rule nothing states (L99).
    private static func month(named written: String) -> Int? {
        let wanted = written.lowercased().prefix(3)
        guard wanted.count == 3 else { return nil }
        let names = ["jan", "feb", "mar", "apr", "may", "jun",
                     "jul", "aug", "sep", "oct", "nov", "dec"]
        // AND THE WHOLE WORD HAS TO BE A MONTH, not merely start like one, or
        // "Novgorod" would be November.
        let full = ["january", "february", "march", "april", "may", "june",
                    "july", "august", "september", "october", "november", "december"]
        let lowered = written.lowercased()
        guard let index = names.firstIndex(of: String(wanted)),
              lowered == names[index] || lowered == full[index]
        else { return nil }
        return index + 1
    }
}
