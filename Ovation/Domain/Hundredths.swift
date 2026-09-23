// ovation#457. Reading a figure a person typed, as hundredths of what they typed.
//
// ONE PARSER FOR EVERY TYPED FIGURE. Cents are hundredths of a dollar and basis
// points are hundredths of a percent, so `Money.read` and the discount's
// percentage field are the same parse with a different sigil and a different
// wrapper around the answer. They were going to be two, and two parsers is how
// one field comes to accept what the other refuses (L370, L613).
//
// NO FLOATING POINT AND NO `Decimal`, which `check-forbidden-constructs.sh`
// refuses in money code and which the first version of this was caught by. The
// digits either side of the point are read as integers and combined, so there is
// no conversion to round through: `Money` is Int64 minor units for the same
// reason (plan 1.4, ovation#127).
//
// AN OPTIONAL RATHER THAN A DEFAULT. A zero is a figure and an empty field is
// not one, and PRD 5.1b turns on the difference: a zero total is a legitimate
// comped invoice, so a figure the screen was never given must never become one
// (L544, L706). What a caller does with nothing is the caller's question.
import Foundation

enum Hundredths {

    /// Reads `typed` as hundredths, or answers that it is not a figure.
    ///
    /// THE SIGIL IS THE CALLER'S AND ONLY ONE IS READ THROUGH. A dollar sign
    /// typed into a percentage field is a mistake rather than a unit, and
    /// reading both would let each field accept the other's values (L118).
    /// Commas are read through everywhere: they are what the figure beside the
    /// field already looks like.
    static func read(_ typed: String, stripping sigil: String = "") -> Int64? {
        var cleaned = ""
        for character in typed where !character.isWhitespace {
            if character == "," { continue }
            if sigil.contains(character) { continue }
            cleaned.append(character)
        }
        var negative = false
        if cleaned.hasPrefix("-") { negative = true; cleaned.removeFirst() }
        guard !cleaned.isEmpty else { return nil }

        // EVERY CHARACTER MUST BE PART OF A FIGURE, because a reader that takes
        // a leading number and stops would read "12 dollars" as 12 and "1.2.3"
        // as 1.2 rather than refusing either (L108).
        var whole = "", fraction = "", seenPoint = false
        for character in cleaned {
            if character.isNumber {
                if seenPoint { fraction.append(character) } else { whole.append(character) }
                continue
            }
            guard character == ".", !seenPoint else { return nil }
            seenPoint = true
        }
        guard !whole.isEmpty || !fraction.isEmpty else { return nil }

        guard let units = whole.isEmpty ? 0 : Int64(whole) else { return nil }
        let (scaled, overflowed) = units.multipliedReportingOverflow(by: 100)
        guard !overflowed else { return nil }

        // THE FIRST TWO DIGITS ARE THE HUNDREDTHS AND THE THIRD DECIDES THE
        // ROUNDING, half away from zero, which is the rule every other figure in
        // this app is rounded by rather than a second one written here (L370).
        let digits = Array(fraction)
        func digit(_ index: Int) -> Int64 {
            index < digits.count ? Int64(String(digits[index])) ?? 0 : 0
        }
        var total = scaled + digit(0) * 10 + digit(1)
        if digit(2) >= 5 { total += 1 }
        return negative ? -total : total
    }

    /// Writes hundredths back the way a person would type them.
    ///
    /// THE ROUND TRIP IS THE POINT. What this writes into a field must read back
    /// as the same value, or editing a discount would change it by looking at it
    /// (L317). Trailing zeros are dropped because 10% is typed "10" and not
    /// "10.00", which is what the design record's own field shows.
    static func text(_ value: Int64) -> String {
        let whole = value / 100
        let fraction = abs(value % 100)
        guard fraction != 0 else { return "\(whole)" }
        var digits = String(format: "%02d", fraction)
        while digits.hasSuffix("0") { digits.removeLast() }
        let sign = value < 0 && whole == 0 ? "-" : ""
        return "\(sign)\(whole).\(digits)"
    }
}
