// ovation#167, PRD 50c. How money, hours and dates are WRITTEN on the invoice PDF,
// the one document a client ever sees.
//
// THE RULE IS THE DESIGN RECORD'S, and so are its cases. The settled page writes a
// figure through docs/design/rules/pdf-text.js, and docs/design/rules/pdf-text.cases.json
// is read both by scripts/test-design-rules.sh against that rule and by
// OvationTests/PDFTextTests.swift against this file. Two implementations of one
// rule, each tested against cases of its own, agree on the day they are written
// and then drift, and the page a client receives is where it would show (L26).
//
// THE INVOICE SCREEN WRITES FIGURES DIFFERENTLY, on purpose: no dollar sign and a
// fixed two decimals. That is a formatter for Dan's own screen, and this one
// belongs to the PDF alone, so neither is reused for the other.
//
// NOTHING HERE ASKS THE HOST FOR A LOCALE. A figure or a month name rendered under
// the Mac's own settings changes with those settings, and the page is what ships
// (L504). Every digit, separator and month name is written out here instead.
import Foundation

enum PDFText {

    /// "$1,234.56", and "-$250.00" below zero, with the minus before the dollar sign.
    static func money(_ value: Money) -> String {
        (value.cents < 0 ? "-$" : "$") + amount(value)
    }

    /// "1,234.56": the figure alone, with no currency sign and no minus.
    ///
    /// THE INVOICE LIST SHOWS THE FIGURE WITHOUT A SIGN (`docs/design/invoice-list.html`),
    /// and it groups its thousands exactly as the page does. This exists so there
    /// is ONE implementation of that grouping rather than two that agree on the day
    /// they are written: sharing the rule while copying the code is not sharing it
    /// (L370). `money` is now this plus a sign.
    static func amount(_ value: Money) -> String {
        let magnitude = value.cents.magnitude
        let cents = magnitude % 100
        return grouped(String(magnitude / 100)) + "."
            + (cents < 10 ? "0\(cents)" : "\(cents)")
    }

    /// "1.0 hr", "1.5 hrs", "1.25 hrs": one decimal unless the value needs two.
    ///
    /// A quarter hour written to one decimal printed 1.3, so the hours times the
    /// rate stopped adding up to the amount beside them, and PRD 50c exists so a
    /// client can reconstruct every figure.
    static func hours(_ duration: Hours) -> String {
        let unit = duration.hundredths == 100 ? " hr" : " hrs"
        return hoursFigure(duration) + unit
    }

    /// The same number WITHOUT its unit, for a sentence that supplies its own.
    ///
    /// ONE DEFINITION, TWO RENDERINGS (ovation#457). The invoice screen writes
    /// "billed as 1.50 hours" in running text, so it needs the figure and not the
    /// abbreviation; deriving it a second time there would be two formatters for
    /// one number, and the quarter hour is exactly where they would disagree
    /// (L370). The design record's own `writtenHours` is this rule.
    static func hoursFigure(_ duration: Hours) -> String {
        let magnitude = duration.hundredths.magnitude
        let whole = magnitude / 100
        let part = magnitude % 100
        let decimals: String
        if part % 10 == 0 {
            decimals = "\(part / 10)"
        } else {
            decimals = part < 10 ? "0\(part)" : "\(part)"
        }
        return (duration.hundredths < 0 ? "-" : "") + "\(whole).\(decimals)"
    }

    /// "October 25, 2026", from the business day the date was STAMPED with.
    ///
    /// The day key is read rather than the instant, because the key is the day
    /// the business recorded, in New York (L39). Returns nil for a key that is not
    /// a calendar day, so a malformed date is refused by whoever lays out the page
    /// rather than printed as something plausible (L50).
    static func date(_ day: BusinessDate) -> String? {
        let parts = day.dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(dayOfMonth)
        else { return nil }
        return "\(monthNames[month - 1]) \(dayOfMonth), \(year)"
    }

    /// "Payment due within 30 days of the invoice date.", counted from the invoice's
    /// own dates (Dan, 2026-09-14), so a due date moved per client or per invoice
    /// (PRD 7) is never contradicted by the footer. Nil for a due date before the
    /// invoice date, which is refused rather than written as a term.
    static func terms(days: Int) -> String? {
        guard days >= 0 else { return nil }
        guard days > 0 else { return "Payment due on the invoice date." }
        return "Payment due within \(days) \(days == 1 ? "day" : "days") of the invoice date."
    }

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    /// "1234567" to "1,234,567".
    private static func grouped(_ digits: String) -> String {
        var out: [Character] = []
        for (index, digit) in digits.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return String(out.reversed())
    }
}
