import Foundation
import Testing

/// ovation#60, PRD 5.3 and 5.3b. When a shoot happened: what can be constructed
/// at all, and which business day the result belongs to.
///
/// THE SIX ARITHMETIC TESTS THAT WERE HERE WENT WITH ovation#432, which deleted
/// the derived length this type used to offer. They priced a derivation no app
/// code read; what is charged is `ShootDuration`, tested against the design
/// record's own cases, and the units and rounding they also covered are
/// `MoneyTests`.
///
/// Every instant here is pinned. Nothing in this file reads the clock, so what is
/// asserted is the value rather than the day it ran.
struct ShootWhenTests {

    /// 2026-11-12 20:00 America/New_York.
    private static let eightPM = Date(timeIntervalSince1970: 1_794_531_600)

    // MARK: what cannot be constructed at all

    @Test("a shoot that ends when it started cannot be made, so it can never be priced")
    func aZeroDurationIsRefused() {
        #expect(ShootWhen(startsAt: Self.eightPM, endsAt: Self.eightPM) == nil)
    }

    @Test("a shoot that ends before it started cannot be made either")
    func aNegativeDurationIsRefused() {
        #expect(ShootWhen(startsAt: Self.eightPM, endsAt: Self.eightPM - 1) == nil)
        #expect(ShootWhen(startsAt: Self.eightPM, endsAt: Self.eightPM - 86_400) == nil)
    }

    @Test("one second is enough to be a real shoot, because the refusal is about nonsense not size")
    func oneSecondIsStillAShoot() {
        #expect(ShootWhen(startsAt: Self.eightPM, endsAt: Self.eightPM + 1) != nil)
    }

    // MARK: a day with no times

    @Test("a shoot recorded as a day carries its day and no instants at all")
    func aDayOnlyShootHasNoTimes() {
        let day = ShootWhen(dayOf: Self.eightPM)
        #expect(day == .dayOnly(.stamping(Self.eightPM)),
                "there is nothing to price from, which is not a span of zero")
        #expect(day.day.dayKey == BusinessCalendar.dayKey(for: Self.eightPM))
    }

    @Test("both forms answer which business day they were on, settled at write")
    func bothFormsCarryTheirDay() throws {
        let timed = try #require(ShootWhen(startsAt: Self.eightPM, endsAt: Self.eightPM + 9_000))
        let dayOnly = ShootWhen(dayOf: Self.eightPM)
        #expect(timed.day.dayKey == dayOnly.day.dayKey)
        #expect(timed.day.agreesWithItsInstant)
    }

    @Test("a shoot that runs past midnight belongs to the day it STARTED")
    func anEveningShootBelongsToItsOwnDay() throws {
        // 2026-11-14 23:30 to 00:30 the next morning, America/New_York. The day
        // key is settled from the start, which is the instant the booking is about.
        let lateStart = Date(timeIntervalSince1970: 1_794_717_000)
        let when = try #require(ShootWhen(startsAt: lateStart, endsAt: lateStart + 3_600))
        #expect(when.day.dayKey == BusinessCalendar.dayKey(for: lateStart))
        #expect(when.day.dayKey != BusinessCalendar.dayKey(for: lateStart + 3_600),
                "the two really are different days, so this asserts something")
    }
}
