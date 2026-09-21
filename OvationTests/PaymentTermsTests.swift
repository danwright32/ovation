import Foundation
import Testing

/// ovation#461, PRD 3 and PRD 5.7. The two numbers a draft is created with, and
/// the day arithmetic behind one of them.
///
/// BOTH WERE MISSING UNTIL A DRAFT HAD TO BE MADE. Measured 2026-09-21: nothing
/// in production decided an hourly rate (`hourlyRate` appeared only in the schema
/// shapes, `Money.charge` and the Debug sample world), and nothing anywhere
/// derived a due date at all, though `Invoice.dueDate`'s own doc comment has
/// cited PRD 5.7 since it was written.
struct PaymentTermsTests {

    /// PRD 3, corrected 2026-09-08. The rate is one published number rather than
    /// a literal at each call site, because a second copy is how two invoices
    /// come to be priced differently for no reason anybody chose.
    @Test("the standard rate is the one the requirement states")
    func thestandardRateIsWhatPRDThreeSays() {
        #expect(Pricing.standardHourlyRate == Money(dollars: 250))
    }

    /// PRD 5.7. Fourteen days after the invoice date.
    @Test("a due date is fourteen days after the day it is measured from")
    func theduedateIsFourteenDaysOn() throws {
        let invoiceDay = try #require(BusinessCalendar.day(forKey: "2026-09-06"))

        let due = try #require(BusinessCalendar.day(14, after: invoiceDay))

        #expect(due.dayKey == "2026-09-20")
    }

    /// IT IS DAYS, NOT SECONDS, and the difference only ever shows across a clock
    /// change. Adding 14 times 86,400 seconds to 2026-10-25 in New York lands on
    /// 2026-11-07 rather than the 8th, because 1 November takes an hour back: the
    /// arithmetic is one hour short of fourteen days and truncates to thirteen.
    /// A due date wrong by a day is a reminder wrong by a day (L39).
    @Test("fourteen days across the autumn clock change is still fourteen days")
    func acrossTheClockChangeItIsStillFourteenDays() throws {
        let invoiceDay = try #require(BusinessCalendar.day(forKey: "2026-10-25"))

        let due = try #require(BusinessCalendar.day(14, after: invoiceDay))

        #expect(due.dayKey == "2026-11-08")
        // The control: the seconds arithmetic this replaces, which lands a day
        // early on exactly this pair and agrees everywhere else.
        let bySeconds = BusinessDate.stamping(invoiceDay.instant.addingTimeInterval(14 * 86_400))
        #expect(bySeconds.dayKey == "2026-11-07",
                "the seconds arithmetic agreed, so this case no longer proves anything")
    }

    /// A DAY KEY THAT IS NOT A DAY IS REFUSED rather than turned into something
    /// plausible, which is the same rule `BusinessCalendar.shortDate` follows
    /// (L50).
    @Test("a key that is not a calendar day yields no date at all", arguments: [
        "2026-13-01", "not-a-day", "", "2026-09-31",
    ])
    func amalformedKeyIsRefused(key: String) {
        #expect(BusinessCalendar.day(forKey: key) == nil)
    }

    /// AND THE DAY IT RETURNS AGREES WITH ITS OWN INSTANT, which is the invariant
    /// `BusinessDate.agreesWithItsInstant` exists to state: a date whose stored
    /// day and stored instant disagree is a record no reader can trust.
    @Test("both days agree with the instants they carry")
    func thedaysAgreeWithTheirInstants() throws {
        let day = try #require(BusinessCalendar.day(forKey: "2026-10-25"))
        let due = try #require(BusinessCalendar.day(14, after: day))

        #expect(day.agreesWithItsInstant)
        #expect(due.agreesWithItsInstant)
    }
}
