import Foundation
import Testing
@testable import Ovation

/// ovation#60, PRD 5.3 and 5.3b. When a shoot happened, and the number Dan bills
/// that comes out of it.
///
/// Every instant here is pinned. Nothing in this file reads the clock, so the
/// arithmetic is measured rather than the day it ran.
struct ShootWhenTests {

    /// 2026-11-12 20:00 America/New_York.
    private static let eightPM = Date(timeIntervalSince1970: 1_794_531_600)

    private static func hours(_ seconds: TimeInterval) throws -> Hours {
        let when = try #require(ShootWhen(startsAt: eightPM, endsAt: eightPM + seconds))
        return try #require(when.billableHours)
    }

    // MARK: the number that becomes money

    @Test("a whole number of hours is exactly that many")
    func wholeHoursAreExact() throws {
        #expect(try Self.hours(3_600) == Hours(whole: 1))
        #expect(try Self.hours(4 * 3_600) == Hours(whole: 4))
    }

    @Test("two and a half hours is twenty five tenths, which is what the rate multiplies")
    func halfHoursAreTenths() throws {
        #expect(try Self.hours(9_000) == Hours(tenths: 25))
    }

    @Test("PRD 5.3 says exact to one decimal, so a shoot is billed in tenths and rounded there")
    func minutesRoundToTenths() throws {
        // 2h35m is 25.83 tenths of an hour.
        #expect(try Self.hours(9_300) == Hours(tenths: 26))
        // 2h32m30s is 25.42, which rounds the other way.
        #expect(try Self.hours(9_150) == Hours(tenths: 25))
    }

    @Test("a tenth exactly on the half rounds away from zero, the way every other amount does")
    func aHalfTenthRoundsAwayFromZero() throws {
        // 2h33m is 25.5 tenths exactly.
        #expect(try Self.hours(9_180) == Hours(tenths: 26))
    }

    @Test("a shoot shorter than a tenth of an hour still records the time it took")
    func aVeryShortShootIsNotZeroedOut() throws {
        // Three minutes. The ONE HOUR MINIMUM is a pricing rule and is applied by
        // the line item (ovation#43), not here: a surface reporting how long Dan
        // was actually there must not be handed a number rounded up for billing.
        #expect(try Self.hours(180) == Hours(tenths: 1))
    }

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

    @Test("a shoot recorded as a day has a day and no billable hours")
    func aDayOnlyShootPricesNothing() {
        let day = ShootWhen(dayOf: Self.eightPM)
        #expect(day.billableHours == nil, "there is nothing to price from, which is not zero hours")
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
