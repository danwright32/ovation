import Foundation
import SwiftData
import Testing

/// ovation#43, PRD 3a, 3b, 51a and 51c. The real times Dan types after a shoot,
/// and the money they decide.
///
/// WHY THE TIMES ARE STORED AT ALL, which is the whole of PRD 3a: Downbeat's
/// booking carries a start and an end DERIVED FROM IT, and nothing ever goes back
/// to correct that end, so 16 of 19 committed bookings say exactly one hour while
/// only 16% of Dan's issued invoices over 2019 to 2024 were one hour. Pricing from
/// the booking would have billed one hour for every shoot he has ever done, on an
/// invoice totalling correctly against its own parts (L161).
@MainActor
struct ShootTimesTests {

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    private static func invoice(_ context: ModelContext,
                                taxStatus: TaxStatus = .notExempt) -> Invoice {
        let client = Client(name: "A company", taxStatus: taxStatus)
        client.email = "booker@example.com"
        context.insert(client)
        let invoice = Invoice(client: client, kind: .fromABooking,
                              invoiceDate: .stamping(Date(timeIntervalSince1970: 1_794_531_600)),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        // DUE 14 DAYS LATER, which PRD 7 says every invoice is. It was missing
        // until ovation#446, and two cases here passed BECAUSE of that: they assert
        // `ReviewGate` refuses nothing, and the gate could not see a missing due
        // date at all, so an invoice no page could be drawn from was being used to
        // prove that a comped one is allowed through. A fixture has to be what real
        // data is, not whatever makes the rule under test fire (L48).
        invoice.dueDate = .stamping(Date(timeIntervalSince1970: 1_794_531_600 + 14 * 86_400))
        context.insert(invoice)
        return invoice
    }

    @discardableResult
    private static func shoot(on invoice: Invoice, from: String?, until: String?) throws -> Shoot {
        let shoot = Shoot(name: "Autumn Evensong", when: nil, venue: "St Anne's")
        if let from { shoot.shotFrom = try #require(ClockTime(from)) }
        if let until { shoot.shotUntil = try #require(ClockTime(until)) }
        invoice.add(shoot)
        return shoot
    }

    // MARK: what the shoot itself answers

    @Test("a shoot with both times answers what it bills")
    func bothTimesPriceTheShoot() throws {
        let context = try Self.store()
        let shoot = try Self.shoot(on: Self.invoice(context), from: "19:32", until: "21:10")

        #expect(shoot.billedHours == Hours(hundredths: 175), "1h38m rounds up to the quarter")
    }

    /// PRD 3c and 51b: a start with no end is the ORDINARY state of a draft. It is
    /// not an error and it is not a duration of nothing, so it answers nothing at
    /// all rather than zero (L11).
    @Test("a shoot missing either time bills nothing, and nothing is not zero")
    func amissingTimeBillsNothing() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)

        let noEnd = try Self.shoot(on: invoice, from: "19:00", until: nil)
        #expect(noEnd.duration == nil)
        #expect(noEnd.billedHours == nil)
        #expect(try Self.shoot(on: invoice, from: nil, until: "21:00").billedHours == nil)
        #expect(try Self.shoot(on: invoice, from: nil, until: nil).billedHours == nil)
    }

    /// PRD 3a said as a test: the booking's own instants are a placeholder and
    /// price nothing, so a shoot carrying them and no typed times bills nothing.
    @Test("the booking's own times price nothing, however complete they are")
    func thebookingsTimesPriceNothing() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        let start = Date(timeIntervalSince1970: 1_794_531_600)
        let shoot = Shoot(name: "Autumn Evensong",
                          when: ShootWhen(startsAt: start, endsAt: start.addingTimeInterval(3_600)),
                          venue: nil)
        invoice.add(shoot)

        // THE POSITIVE CONTROL, asserted on the instants themselves since
        // ovation#432 deleted the booking's own length calculation. The booking
        // carries a complete, hour long span, so "bills nothing" below is a
        // decision about the placeholder rather than a fixture that had nothing
        // to price (L159).
        #expect(shoot.when == ShootWhen(startsAt: start, endsAt: start + 3_600),
                "the booking carries both instants, an hour apart")
        #expect(shoot.billedHours == nil, "and the invoice bills nothing from it")
    }

    // MARK: a flat charge belongs to the invoice, never to a shoot (ovation#431)

    /// PRD 4, and Dan's own decision on 2026-09-19 put to him as a choice: rush
    /// turnaround and preview images belong to the invoice, so a flat charge never
    /// names a shoot. That was written in two docstrings and enforced by nothing
    /// (L407).
    ///
    /// THE GUARD IS THE CONSTRUCTOR, so most of this rule is held by the compiler:
    /// `flat` takes no shoot and `shoot` is `private(set)`, so the bad line cannot
    /// be written. What is asserted here is that the escape hatch really is shut
    /// and that the money is right on the line that is allowed.
    @Test("a flat charge has no shoot to be priced by, and is its own amount")
    func aflatChargeIsItsOwnAmount() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        let shoot = try Self.shoot(on: invoice, from: "19:00", until: "22:00")

        let rush = LineItem.flat(Money(dollars: 150), describedAs: "Rush turnaround")
        invoice.add(rush)

        // THE POSITIVE CONTROL. The shoot really does price, so "the flat charge
        // was not multiplied" is a decision about the KIND of line rather than a
        // fixture with no rate to multiply by (L159).
        #expect(shoot.billedHours == Hours(whole: 3))
        #expect(rush.shoot == nil, "and there is no way to give it one")
        #expect(rush.billedHours == nil)
        #expect(rush.amount == Money(dollars: 150),
                "and not the $450 three hours at its own amount would have come to")
    }

    @Test("an hourly line is the only one that can name a shoot, and it prices from it")
    func onlyAnHourlyLineNamesAShoot() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        let shoot = try Self.shoot(on: invoice, from: "19:00", until: "22:00")
        let line = LineItem.hourly(hours: Hours(whole: 9), at: invoice.hourlyRate,
                                   describedAs: "Photography", for: shoot)
        invoice.add(line)

        #expect(line.shoot?.id == shoot.id)
        #expect(line.billedHours == Hours(whole: 3), "the shoot's typed times, not the stored 9")
        #expect(invoice.refusals.isEmpty)
    }

    // MARK: clearing a time takes the hours beside it (ovation#431)

    /// Dan's decision, 2026-09-19, put to him as a choice against keeping the last
    /// price: clearing a time puts the invoice back to waiting on the times, as a
    /// fresh draft is. So the hours stored beside them go in the same write, or the
    /// invoice goes on pricing from a figure that appears on no screen (L46, L544).
    @Test("clearing one of a shoot's times un-prices every line for it")
    func clearingATimeUnpricesTheLinesForIt() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        let shoot = try Self.shoot(on: invoice, from: "19:00", until: "22:00")
        let line = LineItem.hourly(hours: Hours(whole: 3), at: invoice.hourlyRate,
                                   describedAs: "Photography", for: shoot)
        invoice.add(line)

        // Another shoot on the same invoice, to prove the clearing is addressed to
        // the shoot it was asked about rather than to the invoice (L166).
        let other = Shoot(name: "Spring recital", when: nil, venue: "The Chapel")
        other.shotFrom = try #require(ClockTime("14:00"))
        other.shotUntil = try #require(ClockTime("15:30"))
        invoice.add(other)
        let otherLine = LineItem.hourly(hours: Hours(hundredths: 150), at: invoice.hourlyRate,
                                        describedAs: "Photography", for: other)
        invoice.add(otherLine)

        #expect(invoice.refusals.isEmpty)
        invoice.clearTimes(of: shoot)

        #expect(shoot.shotFrom == nil)
        #expect(shoot.shotUntil == nil)
        #expect(line.hours == nil, "the stored figure went with the times that produced it")
        #expect(line.billedHours == nil)
        #expect(invoice.refusals == [.shootTimesNotGiven],
                "the invoice is waiting on the times again, exactly as a fresh draft is")

        #expect(otherLine.hours == Hours(hundredths: 150), "the other shoot is untouched")
        #expect(other.shotFrom != nil)
    }

    /// The case the fallback arm exists for, asserted so the change above cannot
    /// quietly take it: an imported row carries hours and was NEVER timed, and it
    /// prices from them (L159, ovation#68).
    @Test("a line whose shoot was never timed still prices from its own stored hours")
    func anuntimedShootStillPricesFromStoredHours() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        let shoot = try Self.shoot(on: invoice, from: nil, until: nil)
        let line = LineItem.hourly(hours: Hours(whole: 2), at: invoice.hourlyRate,
                                   describedAs: "Photography", for: shoot)
        invoice.add(line)

        #expect(line.billedHours == Hours(whole: 2))
        #expect(line.amount == Money(dollars: 500))
    }

    // MARK: the number is written once (PRD 51a)

    @Test("the line charges the hours the times produce, whatever hours were stored on it")
    func thelineTakesItsHoursFromTheShoot() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        let shoot = try Self.shoot(on: invoice, from: "19:30", until: "21:00")

        // Stored hours DELIBERATELY WRONG. PRD 51a: the hours are derived from the
        // times and are never typed, so a second copy on the line must not be able
        // to decide the money (L544, L384).
        let line = LineItem.hourly(hours: Hours(whole: 9), at: invoice.hourlyRate,
                                   describedAs: "Photography", for: shoot)
        invoice.add(line)

        #expect(line.billedHours == Hours(hundredths: 150))
        #expect(line.amount == Money(dollars: 375))
    }

    /// The positive control: a line belonging to no shoot is unaffected, so the
    /// case above cannot be satisfied by a rule that ignores stored hours
    /// everywhere (L159).
    @Test("a line belonging to no shoot still charges its own hours")
    func alineWithNoShootKeepsItsHours() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        invoice.add(LineItem.hourly(hours: Hours(whole: 2), at: invoice.hourlyRate,
                                    describedAs: "Photography"))

        #expect(invoice.subtotal == Money(dollars: 500))
    }

    /// The other arm, stated so it is a decision rather than something nobody
    /// looked at: an imported QuickBooks row and the design record's own PDF
    /// fixtures both carry hours with no typed times, and they still price.
    @Test("a line whose shoot has no typed times still charges the hours it carries")
    func anuntimedShootLeavesTheLinesOwnHoursStanding() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        let shoot = try Self.shoot(on: invoice, from: nil, until: nil)
        let line = LineItem.hourly(hours: Hours(whole: 2), at: invoice.hourlyRate,
                                   describedAs: "Photography", for: shoot)
        invoice.add(line)

        #expect(line.billedHours == Hours(whole: 2))
        #expect(line.amount == Money(dollars: 500))
    }

    // MARK: the refusal PRD 3b requires

    @Test("a span too long to be a shoot refuses the invoice by name")
    func alongSpanRefusesByName() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        // 09:00 to 08:00 is 23 hours, which is a typo rather than a shoot.
        try Self.shoot(on: invoice, from: "09:00", until: "08:00")

        #expect(invoice.refusals.contains(.durationLongerThanAShoot))
        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) ==
                "That is more than 12 hours, so it prices nothing. Check the times.")
    }

    /// PRD 5.1a puts more than one shoot on an invoice, so a rule reading only the
    /// first would pass an invoice whose SECOND shoot is the mistyped one.
    @Test("a second shoot's mistyped times refuse the invoice just as the first's would")
    func asecondShootIsAskedToo() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        try Self.shoot(on: invoice, from: "19:30", until: "21:00")
        try Self.shoot(on: invoice, from: "09:00", until: "08:00")

        #expect(invoice.refusals.contains(.durationLongerThanAShoot))
    }

    /// The positive control: a long evening inside the cap is priced, so the
    /// refusal is not simply always on (L159).
    @Test("a long evening inside the cap is priced like any other")
    func alongEveningInsideTheCapIsPriced() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        let shoot = try Self.shoot(on: invoice, from: "19:00", until: "01:30")
        // A LINE, because the last assertion is that the gate refuses NOTHING, and
        // an invoice with no lines now carries its own refusal (ovation#458). The
        // case is about the duration cap, so the fixture has to be an invoice that
        // is otherwise sendable rather than one that passes because a refusal did
        // not exist yet (L48).
        invoice.add(LineItem.hourly(hours: Hours(hundredths: 650), at: Money(dollars: 250),
                                    describedAs: "Photography", for: shoot))

        #expect(shoot.billedHours == Hours(hundredths: 650))
        #expect(invoice.refusals.contains(.durationLongerThanAShoot) == false)
        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) == nil)
    }

    @Test("an invoice with no shoot at all cannot carry the duration refusal")
    func noshootMeansNoDurationRefusal() throws {
        let context = try Self.store()

        #expect(Self.invoice(context).refusals.contains(.durationLongerThanAShoot) == false)
    }

    /// The sentence quotes the constant rather than a second copy of the number,
    /// so moving the cap moves what the refusal says (L370).
    @Test("the sentence names the cap the rule actually uses")
    func thesentenceNamesTheRealCap() {
        #expect(ReviewGate.sentence(for: .durationLongerThanAShoot)
            .contains("more than \(ShootDuration.cap.hundredths / 100) hours"))
    }

    // MARK: the times survive a save and a reopen

    @Test("the times are stored, because an input that is not stored is not an input")
    func thetimesSurviveASave() throws {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let invoice = Self.invoice(context)
        try Self.shoot(on: invoice, from: "19:30", until: "21:00")
        try context.save()

        let reader = ModelContext(container)
        let shoot = try #require(try reader.fetch(FetchDescriptor<Shoot>()).first)
        #expect(shoot.shotFrom == ClockTime("19:30"))
        #expect(shoot.shotUntil == ClockTime("21:00"))
        #expect(shoot.billedHours == Hours(hundredths: 150))
    }
}
