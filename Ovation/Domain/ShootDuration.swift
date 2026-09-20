// ovation#43, PRD 3, 3b and 3c. What a shoot's two clock times come to, and what
// an invoice bills for them.
//
// PORTED FROM THE DESIGN RECORD, `docs/design/rules/duration.js`, which is where
// the three decisions in it were settled with Dan and where the reasoning for
// each is written in full. The cases that file is tested against are the cases
// this is tested against, read from `docs/design/rules/duration.cases.js` by
// `OvationTests/ShootDurationTests.swift`, because two implementations of one
// pricing rule each tested against cases of its own agree on the day they are
// written and then drift (L26).
//
// THE THREE DECISIONS, in one line each, with the reasoning in duration.js:
//
//   THE ONE HOUR MINIMUM (PRD 3). Forty minutes bills one hour.
//   CROSSING MIDNIGHT. An end at or before the start is the next day, because an
//   evening concert running to 00:30 is not a negative shoot.
//   THE CAP. Above twelve hours nothing is priced, which is Dan's number,
//   settled 2026-09-08 against 8, 7 and no cap at all.
//
// THE ELAPSED SPAN AND THE BILLED FIGURE ARE DIFFERENT QUESTIONS, and `Priced`
// carries both. `elapsedMinutes` is how long Dan was actually there and no
// billing rule has touched it, so a surface reporting the shoot's length is never
// handed a number that was rounded up to charge; `billed` is what is charged.
// Folding them would give one number two meanings, and the rounded one is the one
// that would win. `ShootWhen` used to answer the first question and ovation#432
// deleted that, because after this type shipped nothing read it.
//
// WHY IT TAKES CLOCK TIMES RATHER THAN TWO INSTANTS. These are the REAL times
// Dan types after the shoot (PRD 3a), on a screen whose field is a segmented
// clock. A pair of instants would carry a day each and make crossing midnight a
// property of the data rather than a rule, and the rule is what was settled.
import Foundation

/// A time of day, as minutes since midnight.
///
/// PARSED AND ONLY THEN COMPARED (L50, L23). The failable initializer is the only
/// way to make one from text, so a value that is not a time cannot reach the
/// arithmetic below: a nonsense figure that reaches it becomes a confident
/// invoice, well formed and totalling correctly against its own parts.
struct ClockTime: Equatable, Hashable, Comparable, Codable, Sendable {

    /// 0 through 1,439.
    let minutesSinceMidnight: Int

    /// `h:mm` or `hh:mm`, and nothing else. A missing colon, an hour past 23 or a
    /// minute past 59 is not a time, and each is refused rather than clamped.
    init?(_ text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        // DIGITS ONLY, asked before the numbers are read rather than after.
        // `Int("+9")` is 9 and `Int("１９")` is 19, so a parse that only checks the
        // RESULT accepts text nobody would call a time (L50).
        let digits: (Substring) -> Bool = { $0.allSatisfy { $0.isASCII && $0.isNumber } }
        guard parts.count == 2,
              (1...2).contains(parts[0].count), parts[1].count == 2,
              digits(parts[0]), digits(parts[1]),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        self.minutesSinceMidnight = hour * 60 + minute
    }

    init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.minutesSinceMidnight = hour * 60 + minute
    }

    static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// What a shoot's start and end come to, priced or refused by name.
///
/// TWO OUTCOMES RATHER THAN AN OPTIONAL. PRD 3b requires a duration too long to
/// be a shoot to be refused BY NAME rather than priced, and an optional returning
/// nil makes that refusal indistinguishable from a time nobody has typed yet,
/// which is the ordinary state of every draft (docs/design/rules/waiting.js).
/// Those two need opposite sentences: one asks for the end time, the other says
/// the times already given cannot be right (L11).
enum ShootDuration: Equatable, Sendable {

    /// What is charged, and everything a surface needs to explain it.
    struct Priced: Equatable, Sendable {
        /// The real length of the shoot, which is what the times on screen say.
        let elapsedMinutes: Int
        /// What the invoice charges for, on a quarter hour and never below the
        /// minimum.
        let billed: Hours
        /// The billed figure is above the time actually spent, by rounding or by
        /// the minimum. A surface showing both numbers without this has to make
        /// the reader work out why they disagree.
        let roundedUp: Bool
        /// The minimum is what produced the figure, rather than the rounding.
        let atMinimum: Bool
    }

    case priced(Priced)

    /// PRD 3b's refusal, carrying the span it read so a message can quote it.
    case longerThanAShoot(minutes: Int)

    // MARK: the three constants, each one Dan's decision

    /// PRD 3. Forty minutes bills one hour.
    static let minimum = Hours(whole: 1)

    /// Round 4 of ovation#111, Dan's choice, put to him with the measurement that
    /// 94% of his billed lines over 2019 to 2024 already land on a quarter.
    static let step = Hours(quarters: 1)

    /// Dan's number, settled 2026-09-08 against 8, 7 and no cap at all, with his
    /// longest ever billed shoot (6.25 hours) in front of him. Nearly double it,
    /// so it refuses no real shoot; the cost he accepted is that a mistyped
    /// meridiem on an evening job comes to 10 hours and is priced.
    static let cap = Hours(whole: 12)

    /// The minutes between two clock times, reading an end at or before the start
    /// as the next day.
    ///
    /// PUBLIC AND SEPARATE, because a surface shows the elapsed span beside the
    /// billed figure even when the span is refused, and recomputing it there would
    /// be the same rule written twice (L370).
    static func minutes(from start: ClockTime, to end: ClockTime) -> Int {
        let span = end.minutesSinceMidnight - start.minutesSinceMidnight
        return span > 0 ? span : span + 24 * 60
    }

    static func between(_ start: ClockTime, and end: ClockTime) -> ShootDuration {
        let elapsed = minutes(from: start, to: end)

        // ASKED IN MINUTES, never in hours as a fraction. The cap is a whole
        // number of hours and the span is a whole number of minutes, so the
        // comparison is exact and no rounding decides whether an invoice may be
        // priced at all.
        guard elapsed <= Int(cap.hundredths) * 60 / 100 else {
            return .longerThanAShoot(minutes: elapsed)
        }

        // THE STEP IS A WHOLE NUMBER OF MINUTES and the rounding is done in them,
        // so nothing here goes through a binary fraction. `ShootDurationTests`
        // holds the minimum to a whole number of steps, because where it is not,
        // applying it before or after the rounding gives different money.
        let stepMinutes = Int(step.hundredths) * 60 / 100
        let steps = Rounding.halfAwayFromZero(Int64(elapsed), over: Int64(stepMinutes))
        let rounded = Hours(hundredths: steps * step.hundredths)
        let billed = max(rounded, minimum)

        return .priced(Priced(
            elapsedMinutes: elapsed,
            billed: billed,
            roundedUp: Int(billed.hundredths) * 60 / 100 > elapsed,
            atMinimum: billed == minimum && rounded < minimum
        ))
    }
}
