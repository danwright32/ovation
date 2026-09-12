import Foundation
import Testing

/// Plan 1.5, ovation#54. One calendar, pinned to America/New_York, and it is the
/// only one anything uses.
///
/// SERIALIZED, and it is not a preference. Two of these cases change the
/// PROCESS's timezone in order to prove the pinned calendar ignores it, and a
/// process wide setting mutated while other tests run is a shared object a
/// neighbour can observe mid change (L205). Serialized here, restored in a defer,
/// and each such case asserts that the host zone really did change before
/// asserting anything else: a test whose setup silently failed would pass while
/// measuring nothing (L322).
@Suite(.serialized)
struct BusinessCalendarTests {

    // MARK: what is pinned

    @Test("the business timezone is America/New_York")
    func theZoneIsPinned() {
        #expect(BusinessCalendar.timeZone.identifier == "America/New_York")
    }

    // MARK: the case that decides a tax year

    @Test("an invoice at half past eleven on New Year's Eve keys to the year that is ending")
    func theAccrualBoundary() {
        // 2026-12-31 23:30 America/New_York is 2027-01-01 04:30 UTC. Under the
        // accrual basis (PRD 24) the invoice is income for 2026, and a calendar
        // that read UTC, or the host's zone, would file it in a return that has
        // nothing to do with it.
        let instant = utc(2027, 1, 1, 4, 30)

        #expect(BusinessCalendar.dayKey(for: instant) == "2026-12-31")
        #expect(BusinessCalendar.year(for: instant) == 2026)
    }

    @Test("the same instant as a payment date answers the same way")
    func thePaymentBoundary() {
        // Payment dates no longer decide the tax year under PRD 24, but they are
        // still exported and they still set the sales tax period (PRD 25), so
        // they go through the same calendar rather than a second one.
        let instant = utc(2027, 1, 1, 4, 30)
        #expect(BusinessCalendar.dayKey(for: instant) == "2026-12-31")
    }

    @Test("one minute later is the new year")
    func theOtherSideOfTheBoundary() {
        // The positive control. Without it, everything above is satisfied by a
        // calendar that answers 2026-12-31 to everything (L159).
        let instant = utc(2027, 1, 1, 5, 0)
        #expect(BusinessCalendar.dayKey(for: instant) == "2027-01-01")
        #expect(BusinessCalendar.year(for: instant) == 2027)
    }

    // MARK: the other boundaries

    @Test("a month boundary keys to the month that is ending")
    func theMonthBoundary() {
        #expect(BusinessCalendar.dayKey(for: utc(2026, 2, 1, 4, 30)) == "2026-01-31")
        #expect(BusinessCalendar.dayKey(for: utc(2026, 2, 1, 5, 0)) == "2026-02-01")
    }

    @Test("midnight belongs to the day that is starting")
    func midnightBelongsForward() {
        // 2026-07-01 00:00 New York is 04:00 UTC in summer.
        #expect(BusinessCalendar.dayKey(for: utc(2026, 7, 1, 4, 0)) == "2026-07-01")
        #expect(BusinessCalendar.dayKey(for: utc(2026, 7, 1, 3, 59)) == "2026-06-30")
    }

    @Test("the offset is read per date, so a summer evening and a winter evening key differently")
    func daylightSavingIsApplied() {
        // A fixed five hour offset would put both of these on the same side of
        // midnight. New York is four hours behind UTC in July and five in January.
        #expect(BusinessCalendar.dayKey(for: utc(2026, 7, 4, 0, 30)) == "2026-07-03")
        #expect(BusinessCalendar.dayKey(for: utc(2026, 1, 4, 0, 30)) == "2026-01-03")
    }

    @Test("an instant inside the hour that daylight saving repeats still has one day")
    func theRepeatedHourHasOneAnswer() {
        // 2026-11-01 01:30 happens twice in New York. Both instants are the same
        // day, which is the only thing a day key has to be right about.
        #expect(BusinessCalendar.dayKey(for: utc(2026, 11, 1, 5, 30)) == "2026-11-01")
        #expect(BusinessCalendar.dayKey(for: utc(2026, 11, 1, 6, 30)) == "2026-11-01")
    }

    // MARK: the host's zone is not consulted

    @Test("the answers do not change when the host is on the other side of the world")
    func theHostZoneIsIgnored() {
        // On this Mac the host zone already IS America/New_York, so every
        // assertion above would pass against an implementation that read
        // Calendar.current. The test sets the environment itself rather than
        // inheriting it (L504).
        withHostTimeZone("Pacific/Auckland") {
            #expect(BusinessCalendar.dayKey(for: utc(2027, 1, 1, 4, 30)) == "2026-12-31")
            #expect(BusinessCalendar.year(for: utc(2027, 1, 1, 4, 30)) == 2026)
            #expect(BusinessCalendar.dayKey(for: utc(2026, 7, 1, 3, 59)) == "2026-06-30")
        }
    }

    @Test("a day key round trips through the start of its own day, in either host zone")
    func dayKeysRoundTrip() {
        for zone in ["Pacific/Auckland", "UTC"] {
            withHostTimeZone(zone) {
                let start = BusinessCalendar.startOfDay(forDayKey: "2026-12-31")
                #expect(start != nil)
                #expect(BusinessCalendar.dayKey(for: start!) == "2026-12-31")
            }
        }
    }

    // MARK: a key that came from storage is not trusted

    @Test("a malformed day key is refused rather than coerced into a date")
    func malformedKeysAreRefused() {
        // A value read back from the store must never feed a comparison
        // unchecked (L50). Each of these is a different way a key can be wrong.
        #expect(BusinessCalendar.startOfDay(forDayKey: "") == nil)
        #expect(BusinessCalendar.startOfDay(forDayKey: "2026-13-01") == nil)
        #expect(BusinessCalendar.startOfDay(forDayKey: "2026-12-32") == nil)
        #expect(BusinessCalendar.startOfDay(forDayKey: "31/12/2026") == nil)
        #expect(BusinessCalendar.startOfDay(forDayKey: "2026-12-31T00:00:00Z") == nil)
        #expect(BusinessCalendar.startOfDay(forDayKey: "not a date") == nil)
    }

    @Test("a well formed key is accepted, in the same fixture as the refusals")
    func wellFormedKeysAreAccepted() {
        #expect(BusinessCalendar.startOfDay(forDayKey: "2026-12-31") != nil)
        #expect(BusinessCalendar.startOfDay(forDayKey: "2026-02-29") == nil)
        #expect(BusinessCalendar.startOfDay(forDayKey: "2024-02-29") != nil)
    }

    @Test("the year of a day key is read from the key, and a bad key has no year")
    func yearsComeFromKeys() {
        #expect(BusinessCalendar.year(forDayKey: "2026-12-31") == 2026)
        #expect(BusinessCalendar.year(forDayKey: "2026-13-01") == nil)
    }

    // MARK: fixtures

    /// An instant, named in UTC so the test says exactly which moment it means
    /// and never depends on where the machine is.
    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    /// Runs the body with the PROCESS's timezone set to something else, and
    /// asserts that it really changed before the body runs.
    private func withHostTimeZone(_ identifier: String, _ body: () -> Void) {
        let previous = getenv("TZ").map { String(cString: $0) }
        setenv("TZ", identifier, 1)
        NSTimeZone.resetSystemTimeZone()
        defer {
            if let previous {
                setenv("TZ", previous, 1)
            } else {
                unsetenv("TZ")
            }
            NSTimeZone.resetSystemTimeZone()
        }

        // If this fails, the case below proves nothing at all, so it fails here
        // rather than passing quietly (L322).
        //
        // Compared by OFFSET, not by identifier: Foundation reports "UTC" back as
        // its alias "GMT", so an identifier comparison fails on a host zone that
        // was set correctly. What the case actually needs is that the host is no
        // longer where the pinned calendar is, and both halves of that are
        // asserted.
        let requested = TimeZone(identifier: identifier)
        #expect(requested != nil)
        #expect(TimeZone.current.secondsFromGMT() == requested?.secondsFromGMT())
        #expect(TimeZone.current.secondsFromGMT() != BusinessCalendar.timeZone.secondsFromGMT())
        body()
    }

    // MARK: which day, as a number (ovation#248)

    /// A ROTATION NEEDS AN ORDERED DAY, and until now the one place that wanted
    /// it divided seconds by 86,400 in UTC
    /// (`BackupService.reverifyOneArchive`). That works and is deterministic, and
    /// it is a SECOND notion of "day" in a product that has one on purpose (L39).
    /// The boundary it used was not the boundary the backup trigger, the
    /// staleness rule and the archive names all use.
    @Test("two instants on the same business day are the same day number")
    func sameDaySameNumber() {
        let morning = BusinessCalendarTests.instant(2026, 4, 4, hour: 7)
        let evening = BusinessCalendarTests.instant(2026, 4, 4, hour: 22)

        #expect(BusinessCalendar.dayNumber(for: morning)
                == BusinessCalendar.dayNumber(for: evening))
    }

    @Test("consecutive business days are consecutive numbers")
    func consecutiveDays() {
        let first = BusinessCalendarTests.instant(2026, 4, 4, hour: 12)
        let second = BusinessCalendarTests.instant(2026, 4, 5, hour: 12)

        #expect(BusinessCalendar.dayNumber(for: second)
                - BusinessCalendar.dayNumber(for: first) == 1)
    }

    /// THE CASE THE RAW DIVISION GETS WRONG. Late evening in New York is already
    /// the next day in UTC, so counting UTC days puts this instant on a different
    /// day from the one every other part of the product calls it.
    @Test("late evening belongs to the business day it is, not the UTC one")
    func lateEveningStaysOnItsBusinessDay() {
        let evening = BusinessCalendarTests.instant(2026, 4, 4, hour: 21)
        let noon = BusinessCalendarTests.instant(2026, 4, 4, hour: 12)

        #expect(BusinessCalendar.dayNumber(for: evening)
                == BusinessCalendar.dayNumber(for: noon))
        // And the raw arithmetic disagrees, which is the whole reason for this.
        let rawNoon = Int(noon.timeIntervalSinceReferenceDate / 86_400)
        let rawEvening = Int(evening.timeIntervalSinceReferenceDate / 86_400)
        #expect(rawNoon != rawEvening,
                "the fixture no longer straddles a UTC boundary, so it proves nothing")
    }

    /// It agrees with the day key, which is the same fact spelled two ways.
    @Test("the day number and the day key change together")
    func theNumberAndTheKeyAgree() {
        let first = BusinessCalendarTests.instant(2026, 4, 4, hour: 12)
        let second = BusinessCalendarTests.instant(2026, 4, 5, hour: 12)

        #expect((BusinessCalendar.dayKey(for: first) == BusinessCalendar.dayKey(for: second))
                == (BusinessCalendar.dayNumber(for: first)
                    == BusinessCalendar.dayNumber(for: second)))
    }

    /// An instant in Dan's own timezone, so a case reads as the moment it is
    /// about rather than as an offset from a reference date.
    static func instant(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BusinessCalendar.timeZone
        return calendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }
}
