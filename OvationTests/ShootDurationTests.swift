import Foundation
import Testing

/// ovation#43, PRD 3, 3b and 3c. The hours an invoice bills, from the two clock
/// times Dan enters after the shoot.
///
/// THE CASES ARE THE DESIGN RECORD'S OWN, read from
/// `docs/design/rules/duration.cases.js`, the file `scripts/test-design-rules.sh`
/// runs the settled rule against. Two implementations of one pricing rule, each
/// tested against cases of its own, agree on the day they are written and then
/// drift, and an invoice on its way to a client is where that would show (L26).
///
/// THE CASES ARE READ FROM THE JAVASCRIPT RATHER THAN COPIED INTO JSON, which is
/// what `PDFTextTests` does with its own. `duration.cases.js` is INLINED into
/// `docs/design/invoice.html`, which runs its suite on the page, and
/// `scripts/check-design-rules-inline.sh` requires every rule file to appear
/// verbatim in a design file. Moving these to JSON would take them off that page
/// and leave the design record running cases nothing compares. So the file stays
/// where it is and this parses it.
///
/// THE PARSE REFUSES RATHER THAN SKIPS. A line inside the table that this cannot
/// read is a failure, not a case quietly dropped: a reader that returns fewer
/// cases when the format moves is indistinguishable from one that read them all
/// (L215, L98).
struct ShootDurationTests {

    /// One row of `DURATION_CASES`: the two times, the minutes they span, the
    /// hours billed (nil where nothing is priced), whether the billed figure is
    /// above the time actually spent, and why the case is there.
    private struct Case {
        let start: String
        let end: String
        let minutes: Int?
        let billedHundredths: Int64?
        let roundedUp: Bool
        let why: String
    }

    /// Located from this file, never from the working directory, which is
    /// wherever the runner happened to start (L372).
    private static func cases(_ file: StaticString = #filePath) throws -> [Case] {
        let repository = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repository.appending(path: "docs/design/rules/duration.cases.js")
        let text = try String(contentsOf: url, encoding: .utf8)

        guard let open = text.range(of: "var DURATION_CASES = ["),
              let close = text.range(of: "];", range: open.upperBound..<text.endIndex) else {
            throw CasesUnreadable.tableNotFound
        }

        let row = /\[\s*"([^"]*)",\s*"([^"]*)",\s*(\d+|null),\s*([0-9.]+|null),\s*(true|false),\s*"([^"]*)"\s*\],?/
        var found: [Case] = []
        for line in text[open.upperBound..<close.lowerBound].split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let match = try row.wholeMatch(in: trimmed) else {
                throw CasesUnreadable.rowNotRead(String(trimmed.prefix(24)))
            }
            found.append(Case(
                start: String(match.1),
                end: String(match.2),
                minutes: match.3 == "null" ? nil : Int(match.3),
                billedHundredths: match.4 == "null" ? nil : Self.hundredths(String(match.4)),
                roundedUp: match.5 == "true",
                why: String(match.6)
            ))
        }
        return found
    }

    private enum CasesUnreadable: Error {
        case tableNotFound
        case rowNotRead(String)
    }

    /// The design writes hours as a decimal, and the app holds hundredths. Parsed
    /// through the decimal STRING rather than a Double, so a value the design can
    /// write exactly cannot be turned into 174 hundredths on the way in.
    private static func hundredths(_ decimal: String) -> Int64? {
        let parts = decimal.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let whole = Int64(parts[0]) else { return nil }
        guard parts.count == 2 else { return whole * 100 }
        let fraction = parts[1].padding(toLength: 2, withPad: "0", startingAt: 0)
        guard fraction.count == 2, let hundredths = Int64(fraction) else { return nil }
        return whole * 100 + hundredths
    }

    @Test("the shared cases are read and hold something, so no test below runs over nothing")
    func theSharedCasesAreThere() throws {
        let cases = try Self.cases()
        #expect(cases.count >= 16)
        #expect(cases.contains { $0.minutes == nil }, "a time that cannot be read is a case, or it is never exercised")
        #expect(cases.contains { $0.minutes != nil && $0.billedHundredths == nil },
                "a span too long to be a shoot is a case, or the cap is never exercised")
    }

    @Test("every case in the design's own table prices the way the design prices it")
    func theDesignsCasesAllHold() throws {
        for item in try Self.cases() {
            guard let start = ClockTime(item.start), let end = ClockTime(item.end) else {
                #expect(item.minutes == nil, "\(item.why): the design reads these times and the app does not")
                continue
            }
            #expect(item.minutes != nil, "\(item.why): the app reads these times and the design does not")

            let duration = ShootDuration.between(start, and: end)
            guard let billed = item.billedHundredths else {
                #expect(duration == .longerThanAShoot(minutes: item.minutes ?? -1), "\(item.why)")
                continue
            }
            guard case .priced(let priced) = duration else {
                Issue.record("\(item.why): expected \(billed) hundredths, nothing was priced")
                continue
            }
            #expect(priced.elapsedMinutes == item.minutes, "\(item.why)")
            #expect(priced.billed == Hours(hundredths: billed), "\(item.why)")
            #expect(priced.roundedUp == item.roundedUp, "\(item.why)")
        }
    }

    /// The invariant the cases cannot see, because it is about the CONSTANTS
    /// rather than any input. It is asserted in the design's own suite too, and it
    /// is here because the constants are now in two places (duration.js).
    @Test("the one hour minimum is a whole number of quarter hour steps, or rounding and the minimum stop commuting")
    func theMinimumSitsOnAStep() {
        #expect(ShootDuration.minimum.hundredths % ShootDuration.step.hundredths == 0)
    }

    @Test("the constants are the numbers Dan settled, so moving one is a decision rather than a line")
    func theConstantsAreTheSettledOnes() {
        #expect(ShootDuration.minimum == Hours(whole: 1))
        #expect(ShootDuration.cap == Hours(whole: 12))
        #expect(ShootDuration.step == Hours(quarters: 1))
    }

    @Test("a shoot ending after midnight is not a negative one")
    func crossingMidnightIsNotNegative() throws {
        let duration = ShootDuration.between(try #require(ClockTime("21:00")), and: try #require(ClockTime("00:30")))
        #expect(duration == .priced(.init(elapsedMinutes: 210, billed: Hours(hundredths: 350),
                                          roundedUp: false, atMinimum: false)))
    }

    /// PRD 3: forty minutes bills one hour. `atMinimum` is what lets a surface say
    /// WHY the figure is above the time spent, rather than showing a number that
    /// disagrees with the times printed beside it.
    @Test("a short shoot bills the minimum and says that is what happened")
    func theMinimumSaysSoForItself() throws {
        let duration = ShootDuration.between(try #require(ClockTime("19:00")), and: try #require(ClockTime("19:40")))
        guard case .priced(let priced) = duration else {
            Issue.record("forty minutes priced nothing")
            return
        }
        #expect(priced.billed == Hours(whole: 1))
        #expect(priced.atMinimum)
        #expect(priced.roundedUp)
    }

    /// An exact hour is AT the minimum and was not raised to it, and the pair is
    /// the difference between "this is what you shot" and "this is the floor".
    @Test("an exact hour is not reported as having been raised to the minimum")
    func anExactHourIsNotAtTheMinimum() throws {
        let duration = ShootDuration.between(try #require(ClockTime("19:00")), and: try #require(ClockTime("20:00")))
        guard case .priced(let priced) = duration else {
            Issue.record("an hour priced nothing")
            return
        }
        #expect(priced.billed == Hours(whole: 1))
        #expect(!priced.atMinimum)
        #expect(!priced.roundedUp)
    }

    @Test("a time is parsed and only then compared, so a nonsense one can never reach arithmetic")
    func aNonsenseTimeNeverReachesArithmetic() {
        #expect(ClockTime("19:67") == nil)
        #expect(ClockTime("25:00") == nil)
        #expect(ClockTime("1930") == nil)
        #expect(ClockTime("") == nil)
        #expect(ClockTime("+9:30") == nil, "a sign is not a digit, and Int reads one")
        #expect(ClockTime("\u{FF11}\u{FF19}:30") == nil, "nor are full width digits, which Int also reads")
        #expect(ClockTime("7:30")?.minutesSinceMidnight == 450)
        #expect(ClockTime("19:30")?.minutesSinceMidnight == 1_170)
    }
}
