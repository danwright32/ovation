// Plan 1.5, ovation#54. ONE calendar, pinned to America/New_York, and it is the
// only one anything in Ovation uses for a business date.
//
// NOT A PORT, though Downbeat reasons the same way: its handoff record is built
// with the EXPORT's calendar rather than the host's, precisely so the two apps
// agree about which day a late evening shoot fell on.
//
// WHY PINNED RATHER THAN THE HOST'S. The host timezone is a setting. A tax year
// boundary decided by it moves when Dan travels or when a machine is configured
// differently, and under the accrual basis (PRD 24) an invoice dated
// 2026-12-31 23:30 New York is income for 2026 while the same instant is
// 2027-01-01 in UTC. That is a filed return being wrong, in a way nothing in the
// app would ever report.
//
// `scripts/check-forbidden-constructs.sh` refuses `Calendar.current`,
// `TimeZone.current` and `Locale.current` anywhere in the app's sources, because
// the second calendar does not arrive as a decision. It arrives inside a
// convenience somebody adds later (L39, L27).
//
// EVERYTHING HERE IS PURE. It takes an instant and answers; it never asks what
// time it is now. A clock is a separate seam and belongs to whatever needs one.
import Foundation

enum BusinessCalendar {
    /// Where Dan's business is, and the only zone any business date is expressed
    /// in. Force unwrapped deliberately: a build whose Foundation does not know
    /// this identifier cannot compute a correct tax year, and failing at launch
    /// is better than answering in UTC (L42).
    static let timeZone: TimeZone = {
        guard let zone = TimeZone(identifier: "America/New_York") else {
            preconditionFailure("America/New_York is not available on this system")
        }
        return zone
    }()

    /// The day key format, and the only place it is written down. ISO ordered so
    /// that a string comparison and a date comparison agree, which is what lets
    /// the export group and sort on the stamped key (plan 1.6).
    static let dayKeyFormat = "yyyy-MM-dd"

    /// `en_US_POSIX` because a fixed format read under the host's locale is not
    /// fixed: a locale with its own calendar or numbering system renders and
    /// parses different text for the same instant.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = dayKeyFormat
        // Not lenient, so "2026-13-01" is refused rather than rolled forward
        // into January of the following year.
        //
        // MEASURED, NOT ASSUMED, and the measurement is not what was expected.
        // This and the re-render in `startOfDay(forDayKey:)` below are each
        // INDEPENDENTLY SUFFICIENT on this Foundation version: switching either
        // one off on 2026-09-06 left every malformed key still refused and the
        // whole suite green, and only removing BOTH made the refusals fail.
        //
        // Both are kept anyway. Leniency is a hint rather than a contract, and a
        // fixed format parser accepting a PREFIX of a longer string is documented
        // historical behaviour, so which of the two is load bearing can change
        // under a Foundation upgrade with nothing saying so. What the tests
        // assert is the OUTCOME, that a malformed key is refused, never the
        // mechanism, so either may be removed without going red. That is exactly
        // why this note exists rather than a comment claiming one of them is the
        // protection (L346).
        formatter.isLenient = false
        return formatter
    }()

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// Which business day an instant fell on, as `yyyy-MM-dd`.
    static func dayKey(for instant: Date) -> String {
        formatter.string(from: instant)
    }

    /// Which business year an instant fell in.
    static func year(for instant: Date) -> Int {
        calendar.component(.year, from: instant)
    }

    /// The first instant of a day key, or nil when the key is not one.
    ///
    /// A key read back from the store is input, not a fact, so it is parsed and
    /// refused rather than being fed to a comparison (L50). Round tripped through
    /// the formatter, so a key that parses as a PREFIX of something longer
    /// ("2026-12-31T00:00:00Z") cannot come back as the 31st.
    ///
    /// See the note beside `isLenient` above: this refusal and that one are each
    /// independently sufficient today, and neither is proven necessary.
    static func startOfDay(forDayKey key: String) -> Date? {
        guard let parsed = formatter.date(from: key), formatter.string(from: parsed) == key else {
            return nil
        }
        return calendar.startOfDay(for: parsed)
    }

    /// Whole business days between two instants, counted by calendar day rather
    /// than by dividing an interval, so a day that is 23 or 25 hours long across
    /// a clock change still counts as one (ovation#64). Never negative: a caller
    /// asking how long ago something was gets 0 for the future rather than a
    /// number that reads as a very stale value.
    ///
    /// One date helper decides what a day is, here, rather than each caller
    /// dividing by 86,400 slightly differently (L39).
    static func wholeDays(from: Date, to: Date) -> Int {
        guard to > from else { return 0 }
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// The year a day key belongs to, or nil when the key is not one. Derived
    /// through `startOfDay` rather than by taking the first four characters, so
    /// there is one definition of what a valid key is (L41).
    static func year(forDayKey key: String) -> Int? {
        guard let start = startOfDay(forDayKey: key) else { return nil }
        return year(for: start)
    }
}
