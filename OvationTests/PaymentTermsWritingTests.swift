import Foundation
import Testing

/// ovation#473, PRD 5.7. The terms an invoice is written on, and reading back a
/// date somebody typed.
///
/// THE DESIGN RECORD SETTLED BOTH. `docs/design/invoice.html` draws the due date
/// as a control carrying four terms, with the date each one lands on beside it,
/// and an "Another date..." entry opening a panel that reads a typed date or
/// refuses it by name. Nothing in the app had either, so the due date was a
/// figure at the foot that could not be changed.
///
/// READING A DATE IS WHERE THE EDGES ARE, which is why it is a pure function with
/// its own cases rather than something the panel does inline.
struct PaymentTermsWritingTests {

    private static func day(_ key: String) throws -> BusinessDate {
        try #require(BusinessCalendar.day(forKey: key))
    }

    // MARK: the terms

    /// FOUR TERMS, AND `On receipt` IS A REAL ONE RATHER THAN A ZERO, which the
    /// design record says in as many words. Fourteen days is PRD 5.7's default
    /// and is the one an invoice is created with.
    @Test("the terms are the four the design record draws, in its order")
    func thetermsAreTheFour() {
        #expect(PaymentTerms.all.map(\.says) == ["On receipt", "7 days", "14 days", "30 days"])
        #expect(PaymentTerms.all.map(\.days) == [0, 7, 14, 30])
        #expect(PaymentTerms.standard.days == 14, "PRD 5.7's default moved and nothing said so")
    }

    @Test("each term lands on the day it says, counted from the invoice date")
    func eachtermLandsWhereItSays() throws {
        let issued = try Self.day("2026-08-29")

        let landing = PaymentTerms.all.map { BusinessCalendar.shortDate($0.from(issued) ?? issued) }

        #expect(landing == ["29 Aug 2026", "5 Sep 2026", "12 Sep 2026", "28 Sep 2026"])
    }

    // MARK: reading a date somebody typed

    @Test("a date written the way the screen writes it is read back", arguments: [
        ("12 Nov 2026", "2026-11-12"),
        ("1 Jan 2027", "2027-01-01"),
        ("29 Feb 2028", "2028-02-29"),
        ("31 Dec 2026", "2026-12-31"),
    ])
    func adateIsReadBack(typed: String, key: String) {
        #expect(PaymentTerms.read(typed)?.dayKey == key, "\(typed) read as \(PaymentTerms.read(typed)?.dayKey ?? "nothing")")
    }

    /// TYPED BY A PERSON, so it is forgiving about the things a person varies and
    /// about nothing else: the case of the month and the spaces around it.
    @Test("it forgives case and spacing, because a person is typing", arguments: [
        "12 nov 2026", "12 NOV 2026", "  12 Nov 2026  ", "12  Nov  2026", "12 November 2026",
    ])
    func itforgivesWhatAPersonVaries(typed: String) {
        #expect(PaymentTerms.read(typed)?.dayKey == "2026-11-12", "\(typed) was refused")
    }

    /// A DAY THE MONTH DOES NOT HAVE IS REFUSED, never rolled forward. This is
    /// the case the design record's own note singles out: date arithmetic rolls
    /// 31 September into 1 October, so a date nobody typed would be accepted and
    /// then shown back as a different day (L50).
    @Test("a day its month does not have is refused rather than rolled forward", arguments: [
        "31 Sep 2026", "30 Feb 2026", "29 Feb 2027", "32 Jan 2026", "0 Jan 2026",
    ])
    func animpossibleDayIsRefused(typed: String) {
        #expect(PaymentTerms.read(typed) == nil,
                "\(typed) was read as \(PaymentTerms.read(typed)?.dayKey ?? "nothing")")
    }

    @Test("anything else is refused by returning nothing", arguments: [
        "", "   ", "tomorrow", "12/11/2026", "2026-11-12", "12 Nov", "Nov 2026",
        "12 Xxx 2026", "12 Nov 1999", "12 Nov 2101", "twelve Nov 2026",
    ])
    func anythingElseIsRefused(typed: String) {
        #expect(PaymentTerms.read(typed) == nil,
                "\(typed) was read as \(PaymentTerms.read(typed)?.dayKey ?? "nothing")")
    }

    /// A ROUND TRIP, which is the property that actually matters: whatever the
    /// screen writes, the screen can read. Asserted across a year rather than on
    /// one date, because a formatter and a parser agreeing on one value says
    /// nothing about the rest (L26, L504).
    @Test("every day of a year survives being written and read back")
    func everydayOfAYearSurvives() throws {
        var checked = 0
        var day = try Self.day("2026-01-01")
        while day.dayKey < "2027-01-01" {
            let written = try #require(BusinessCalendar.shortDate(day))
            #expect(PaymentTerms.read(written)?.dayKey == day.dayKey,
                    "\(written) did not read back as \(day.dayKey)")
            checked += 1
            day = try #require(BusinessCalendar.day(1, after: day))
        }
        #expect(checked == 365, "the walk covered \(checked) days, not the year")
    }

    /// AND THE REFUSAL NAMES WHAT GOOD LOOKS LIKE, in the shape the reader is
    /// already looking at, rather than describing a format (L399).
    @Test("the refusal shows the shape rather than describing it")
    func therefusalShowsTheShape() throws {
        let said = PaymentTerms.refusalSentence(showing: try Self.day("2026-11-12"))

        #expect(said == "Not a date Ovation can read. Write it like 12 Nov 2026.")
    }
}
