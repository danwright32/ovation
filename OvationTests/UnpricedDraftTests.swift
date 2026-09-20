import Foundation
import SwiftData
import Testing

/// ovation#117, PRD 3c and 51b. A drafted invoice carries NO duration and cannot
/// be sent until Dan supplies one, so an unpriced draft is a state of its own.
///
/// WHY IT IS NOT A ZERO INVOICE, which is the whole reason this is an issue. PRD
/// 1b makes a zero total ordinary, occasionally wanted for a comped shoot, and
/// says no guard may refuse one. An unpriced draft rendered as an amount would be
/// indistinguishable from that on every screen while needing the opposite action
/// (L11). The list draws `no price` for one and `comped` for the other, settled
/// with Dan on 2026-09-09, and both say what they are rather than either being
/// inferred from a figure.
///
/// THE VOCABULARY IS THE DESIGN'S, `docs/design/rules/waiting.js`, which names the
/// thing that is missing rather than its class: a draft carrying a start time and
/// no end time is the ORDINARY state of every draft and asks for the END, by name.
@MainActor
struct UnpricedDraftTests {

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
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
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

    // MARK: what the shoot says it is waiting on

    @Test("a shoot with neither time asks for both, and it is the only state that may")
    func neitherTimeAsksForBoth() throws {
        let context = try Self.store()
        let shoot = try Self.shoot(on: Self.invoice(context), from: nil, until: nil)

        #expect(shoot.timesMissing == .both)
    }

    /// The everyday draft, and the case the design's rule was written for.
    @Test("a start time and no end time asks for the END, by name")
    func astartWithNoEndAsksForTheEnd() throws {
        let context = try Self.store()
        let shoot = try Self.shoot(on: Self.invoice(context), from: "19:30", until: nil)

        #expect(shoot.timesMissing == .end)
    }

    @Test("and the other way round, which a booking with only a finish would give")
    func anendWithNoStartAsksForTheStart() throws {
        let context = try Self.store()
        let shoot = try Self.shoot(on: Self.invoice(context), from: nil, until: "21:00")

        #expect(shoot.timesMissing == .start)
    }

    @Test("a shoot with both times is waiting on nothing")
    func bothtimesWaitOnNothing() throws {
        let context = try Self.store()
        let shoot = try Self.shoot(on: Self.invoice(context), from: "19:30", until: "21:00")

        #expect(shoot.timesMissing == nil)
    }

    // MARK: the refusal, and the sentence it carries

    @Test("an unpriced draft refuses the send and names the time that is missing")
    func anunpricedDraftRefusesByName() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        try Self.shoot(on: invoice, from: "19:30", until: nil)

        #expect(invoice.refusals.contains(.shootEndTimeNotGiven))
        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) ==
                "Waiting on the time the shoot ended.")
    }

    @Test("a draft with neither time is asked for both rather than for one of them")
    func aneitherDraftIsAskedForBoth() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        try Self.shoot(on: invoice, from: nil, until: nil)

        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) ==
                "Waiting on the shoot's start and end times.")
    }

    @Test("a draft with only an end time is asked for the start")
    func anendOnlyDraftIsAskedForTheStart() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        try Self.shoot(on: invoice, from: nil, until: "21:00")

        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) ==
                "Waiting on the time the shoot started.")
    }

    /// PRD 51b's fixed order, which is the design's: the times, then the duration
    /// they produce, then the tax status. Dan's own argument for it: "what happens
    /// if I set the tax status before the hours? That line just disappears and
    /// nothing takes its place."
    @Test("the times are asked for before the tax status, which is the settled order")
    func thetimesComeBeforeTheTaxStatus() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context, taxStatus: .neverRecorded)
        try Self.shoot(on: invoice, from: "19:30", until: nil)

        #expect(invoice.refusals.contains(.shootEndTimeNotGiven))
        #expect(invoice.refusals.contains(.taxStatusNeverRecorded), "both are really present")
        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) ==
                "Waiting on the time the shoot ended.")
    }

    /// And Settings still comes before both, so the case above cannot be satisfied
    /// by a gate that simply always answers about the times (L159).
    @Test("but a Settings problem is still said before the times")
    func settingsStillComesFirst() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        try Self.shoot(on: invoice, from: nil, until: nil)
        var footer = InvoiceFooter.fixed
        footer.payment = ""

        #expect(ReviewGate.refusal(for: invoice, footer: footer) ==
                "Settings has no payment instructions, so no invoice can be sent.")
    }

    // MARK: the state has a name the surfaces ask for

    @Test("an invoice waiting on a time says it is unpriced")
    func thestateHasAName() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        try Self.shoot(on: invoice, from: "19:30", until: nil)

        #expect(invoice.isUnpriced)
    }

    /// THE CASE THE ISSUE EXISTS FOR. A comped invoice really does come to zero
    /// and is sendable; an unpriced one comes to zero because nothing has been
    /// priced yet and is not. The two must not answer the same question the same
    /// way (L11, PRD 1b).
    @Test("a comped invoice comes to nothing, is NOT unpriced, and is not refused")
    func acompedInvoiceIsNotAnUnpricedOne() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        let shoot = try Self.shoot(on: invoice, from: "19:00", until: "20:00")
        let line = LineItem.hourly(hours: Hours(whole: 1), at: .zero, describedAs: "Photography",
                                   for: shoot)
        invoice.add(line)

        #expect(invoice.total == .zero, "a comped shoot really does come to nothing")
        #expect(invoice.isUnpriced == false)
        #expect(ReviewGate.refusal(for: invoice, footer: .fixed) == nil,
                "PRD 1b: no guard may refuse a zero invoice")
    }

    @Test("an invoice whose shoots are all timed is not unpriced")
    func atimedInvoiceIsNotUnpriced() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        try Self.shoot(on: invoice, from: "19:30", until: "21:00")

        #expect(invoice.isUnpriced == false)
        #expect(invoice.refusals.isEmpty)
    }

    /// PRD 5.1a puts more than one shoot on an invoice, so one timed shoot must
    /// not answer for an untimed sibling.
    @Test("one timed shoot does not cover an untimed one beside it")
    func onetimedShootDoesNotCoverAnother() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        try Self.shoot(on: invoice, from: "19:30", until: "21:00")
        try Self.shoot(on: invoice, from: "14:00", until: nil)

        #expect(invoice.isUnpriced)
        #expect(invoice.refusals.contains(.shootEndTimeNotGiven))
    }

    // MARK: what the year end export does with one

    /// PRD 24b and ovation#61. An unpriced draft must not silently reach a return
    /// as a zero. It cannot: it is never sent, so it is excluded and NAMED rather
    /// than counted, which is what `IncomeOmission` exists for (L540).
    @Test("an unpriced draft is excluded from income and named as never issued")
    func anunpricedDraftIsNamedInTheExport() throws {
        let context = try Self.store()
        let invoice = Self.invoice(context)
        try Self.shoot(on: invoice, from: "19:30", until: nil)
        let range = TaxExportRange.calendarYear(2026)

        let omissions = TaxExport.omissions(from: [invoice], in: range)

        #expect(omissions[.neverIssued] == 1)
        #expect(TaxExport.income(from: [invoice], in: range).rowsIncluded == 0,
                "and it is in no row, so no zero reaches the return")
    }
}
