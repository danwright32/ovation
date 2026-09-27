import Foundation
import SwiftData
import Testing

/// ovation#185, PRD 14g to 14k. Putting a client's held money on an invoice, and
/// taking it back off.
///
/// EVERY CASE READS THE STORE BACK FROM A FRESH CONTEXT, because the writes run
/// on `PaymentAllocator`'s own context and what matters is what was committed.
///
/// THE MONEY A CLIENT HOLDS IS BUILT AS A PAYMENT WITH NOTHING ALLOCATED, which is
/// exactly what `Client.moneyHeld` reads (PRD 14a): an overpayment and a deposit
/// are both that shape once received (PRD 14l).
struct HeldMoneyTests {

    /// 2026-09-26 12:00 America/New_York, and the day after.
    private static let noon = Date(timeIntervalSince1970: 1_790_438_400)
    private static let today = BusinessDate.stamping(noon)
    private static let tomorrow = BusinessDate.stamping(noon.addingTimeInterval(86_400))

    private struct World {
        let container: ModelContainer
        let context: ModelContext
        let client: Client

        var allocator: PaymentAllocator { PaymentAllocator(modelContainer: container) }

        func fresh() -> ModelContext { ModelContext(container) }

        func read(_ invoice: Invoice) throws -> Invoice {
            try #require(try fresh().fetch(FetchDescriptor<Invoice>()).first { $0.id == invoice.id })
        }

        func held() throws -> Money {
            try #require(try fresh().fetch(FetchDescriptor<Client>()).first { $0.id == client.id })
                .moneyHeld
        }

        func allocations() throws -> [PaymentAllocation] {
            try fresh().fetch(FetchDescriptor<PaymentAllocation>())
        }
    }

    private static func world() throws -> World {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .exempt)
        context.insert(client)
        return World(container: container, context: context, client: client)
    }

    /// An invoice for the world's client charging `owing`, sent unless `sent` is
    /// false, which leaves it a draft.
    @discardableResult
    private static func invoice(_ world: World, owing: Money, sent: Bool = true,
                                for client: Client? = nil) -> Invoice {
        let invoice = Invoice(client: client ?? world.client, kind: .photography,
                              invoiceDate: today, hourlyRate: Money(dollars: 250),
                              taxRate: .newYorkCity, createdOn: today)
        world.context.insert(invoice)
        invoice.add(LineItem.flat(owing, describedAs: "Photography"))
        if sent { invoice.recordSendState(.sent(route: .ovationSentIt, at: noon)) }
        return invoice
    }

    /// Money the client is holding: a payment with nothing allocated from it.
    @discardableResult
    private static func holding(_ world: World, _ amount: Money,
                                received: BusinessDate = today) -> Payment {
        let payment = Payment(client: world.client, amount: amount, method: .zelle,
                              receivedOn: received)
        world.context.insert(payment)
        return payment
    }

    // MARK: exactly one open invoice, PRD 14h

    @Test("with one open invoice Ovation applies the held money itself, and what is left stays held")
    func oneOpenInvoiceTakesIt() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let invoice = Self.invoice(world, owing: Money(cents: 40_828))
        try world.context.save()

        let touched = try await world.allocator.placeHeldMoney(on: Self.today)

        #expect(touched == [invoice.persistentModelID])
        let read = try world.read(invoice)
        #expect(read.amountPaid == Money(cents: 40_828))
        #expect(read.amountOutstanding == .zero)
        // PRD 14k and 5.14e: exactly the rest is held, never both driven to zero.
        #expect(try world.held() == Money(cents: 9_172))
        let allocation = try #require(try world.allocations().only)
        #expect(allocation.isHeldMoney, "it is held money applied, which Remove may take off")
        #expect(allocation.source == .heldMoney)
    }

    @Test("held money smaller than the invoice is all applied and the rest is still owed")
    func lessThanTheInvoice() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 200))
        let invoice = Self.invoice(world, owing: Money(cents: 40_828))
        try world.context.save()

        try await world.allocator.placeHeldMoney(on: Self.today)

        let read = try world.read(invoice)
        #expect(read.amountPaid == Money(dollars: 200))
        #expect(read.amountOutstanding == Money(cents: 20_828))
        #expect(try world.held() == .zero)
    }

    @Test("a draft is an open invoice, so a client whose only open invoice is a draft has it applied there")
    func aDraftTakesIt() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 100))
        let draft = Self.invoice(world, owing: Money(dollars: 300), sent: false)
        try world.context.save()

        try await world.allocator.placeHeldMoney(on: Self.today)

        #expect(try world.read(draft).amountPaid == Money(dollars: 100))
    }

    @Test("held money from two payments is taken oldest first, one allocation per payment")
    func oldestMoneyFirst() async throws {
        let world = try Self.world()
        let newer = Self.holding(world, Money(dollars: 300), received: Self.tomorrow)
        let older = Self.holding(world, Money(dollars: 100), received: Self.today)
        let invoice = Self.invoice(world, owing: Money(dollars: 250))
        try world.context.save()

        try await world.allocator.placeHeldMoney(on: Self.tomorrow)

        let byPayment = Dictionary(grouping: try world.allocations(), by: { $0.payment?.id })
        #expect(byPayment[older.id]?.only?.amount == Money(dollars: 100))
        #expect(byPayment[newer.id]?.only?.amount == Money(dollars: 150))
        #expect(try world.read(invoice).amountOutstanding == .zero)
        #expect(try world.held() == Money(dollars: 150))
    }

    // MARK: it runs twice

    @Test("placing twice writes nothing the second time")
    func placingTwiceIsPlacingOnce() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let invoice = Self.invoice(world, owing: Money(cents: 40_828))
        try world.context.save()

        try await world.allocator.placeHeldMoney(on: Self.today)
        let again = try await world.allocator.placeHeldMoney(on: Self.today)

        #expect(again.isEmpty, "the second pass found the first pass's answer already there")
        #expect(try world.allocations().count == 1)
        #expect(try world.read(invoice).amountPaid == Money(cents: 40_828))
    }

    /// PRD 14b's own case: two writers of one client's money arriving at once.
    /// The gate queues them, so the second reads the first's allocation.
    @Test("two passes started at once apply the money once")
    func twoPassesAtOnce() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let invoice = Self.invoice(world, owing: Money(cents: 40_828))
        try world.context.save()
        let first = world.allocator, second = world.allocator

        async let one = first.placeHeldMoney(on: Self.today)
        async let two = second.placeHeldMoney(on: Self.today)
        let touched = try await one + (try await two)

        #expect(touched.count == 1)
        #expect(try world.allocations().count == 1)
        #expect(try world.read(invoice).amountPaid == Money(cents: 40_828))
        #expect(try world.held() == Money(cents: 9_172))
    }

    // MARK: what is not an open invoice

    @Test("a paid invoice is not one, so nothing is applied to it")
    func aPaidInvoiceTakesNothing() async throws {
        let world = try Self.world()
        let invoice = Self.invoice(world, owing: Money(dollars: 300))
        try world.context.save()
        try await world.allocator.record(Money(dollars: 300), method: .zelle,
                                         receivedOn: Self.today,
                                         onto: invoice.persistentModelID, press: UUID())
        Self.holding(world, Money(dollars: 100))
        try world.context.save()

        let touched = try await world.allocator.placeHeldMoney(on: Self.today)

        #expect(touched.isEmpty)
        #expect(try world.held() == Money(dollars: 100))
    }

    /// Dan, 2026-09-26: an invoice paid in full by a check that has not cleared is
    /// treated as paid, and a bounce makes it open again.
    @Test("an invoice paid by a check that has not cleared takes nothing, and takes it once the check stops standing")
    func anUnclearedCheckIsPaid() async throws {
        let world = try Self.world()
        let invoice = Self.invoice(world, owing: Money(dollars: 300))
        try world.context.save()
        try await world.allocator.record(Money(dollars: 300), method: .check,
                                         receivedOn: Self.today,
                                         onto: invoice.persistentModelID, press: UUID())
        Self.holding(world, Money(dollars: 100))
        try world.context.save()

        #expect(try await world.allocator.placeHeldMoney(on: Self.today).isEmpty)
        #expect(try world.held() == Money(dollars: 100))

        // What a bounce has to do to the money: the check's allocation stops
        // standing. Nothing records a bounce yet, so it is driven directly.
        let context = world.fresh()
        let check = try #require(try context.fetch(FetchDescriptor<PaymentAllocation>()).only)
        check.releasedOn = Self.tomorrow
        try context.save()

        #expect(try await world.allocator.placeHeldMoney(on: Self.tomorrow)
                    == [invoice.persistentModelID])
        #expect(try world.read(invoice).amountPaid == Money(dollars: 100))
    }

    @Test("a cancelled invoice is not open, and an unsettled send is not counted")
    func closedAndUnsettledTakeNothing() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 100))
        let cancelled = Self.invoice(world, owing: Money(dollars: 300))
        cancelled.closure = .cancelled(on: Self.today, reason: "the concert was called off")
        let unsettled = Self.invoice(world, owing: Money(dollars: 300), sent: false)
        unsettled.recordSendState(.couldNotDetermine(checkedAt: Self.noon))
        try world.context.save()

        #expect(try await world.allocator.placeHeldMoney(on: Self.today).isEmpty)
        #expect(try world.held() == Money(dollars: 100))
    }

    @Test("another client's held money is never applied here")
    func onlyTheInvoicesOwnClient() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 100))
        let stranger = Client(name: "Riverside Chorale", taxStatus: .exempt)
        world.context.insert(stranger)
        let theirs = Self.invoice(world, owing: Money(dollars: 300), for: stranger)
        try world.context.save()

        #expect(try await world.allocator.placeHeldMoney(on: Self.today).isEmpty)
        #expect(try world.read(theirs).amountPaid == .zero)
    }

    // MARK: more than one open invoice, PRD 14j

    @Test("with two open invoices nothing is applied to either, drafts included")
    func twoOpenInvoicesTakeNothing() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let sent = Self.invoice(world, owing: Money(cents: 40_828))
        let draft = Self.invoice(world, owing: Money(dollars: 300), sent: false)
        try world.context.save()

        #expect(try await world.allocator.placeHeldMoney(on: Self.today).isEmpty)
        #expect(try world.read(sent).amountPaid == .zero)
        #expect(try world.read(draft).amountPaid == .zero)
        #expect(try world.held() == Money(dollars: 500))
    }

    // MARK: drafts waiting on their shoot times (ovation#582)

    /// A draft carrying one shoot with no times, which is what the Downbeat drain
    /// makes: it has no hours and so no amount (PRD 3c).
    @discardableResult
    private static func unpricedDraft(_ world: World) -> Invoice {
        let invoice = Invoice(client: world.client, kind: .fromABooking,
                              invoiceDate: today, hourlyRate: Money(dollars: 250),
                              taxRate: .newYorkCity, createdOn: today)
        world.context.insert(invoice)
        invoice.add(Shoot(name: "Autumn Evensong", when: nil, venue: "St Anne's"))
        return invoice
    }

    /// Prices an unpriced draft by giving its shoot hours, through a context of
    /// its own as a screen would.
    private static func price(_ invoice: Invoice, in world: World) throws {
        let context = world.fresh()
        let editing = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.id == invoice.id })
        let shoot = try #require(editing.shoots.first)
        editing.add(LineItem.hourly(hours: Hours(whole: 2), at: editing.hourlyRate,
                                    describedAs: "Photography", for: shoot))
        try context.save()
        #expect(!editing.isUnpriced, "the fixture has to price it for this to prove anything")
    }

    /// THE DRAIN'S OWN CASE. Two drafts from Downbeat, both still waiting on their
    /// times, are two open invoices, so the client's held money waits on Dan (PRD
    /// 14j). Read as paid, they counted as none, and pricing one then made it the
    /// only open invoice and the money went onto it by itself: the choice PRD 14j
    /// gives Dan was taken for him.
    @Test("two drafts waiting on their times are two open invoices, and pricing one does not take the choice from Dan")
    func twoUnpricedDraftsWaitOnDan() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let first = Self.unpricedDraft(world)
        let second = Self.unpricedDraft(world)
        try world.context.save()

        #expect(InvoiceStanding.invoicesOpenForHeldMoney(of: world.client, on: Self.today).count == 2)
        #expect(try await world.allocator.placeHeldMoney(on: Self.today).isEmpty)

        try Self.price(first, in: world)

        #expect(try await world.allocator.placeHeldMoney(on: Self.today).isEmpty,
                "the other draft is still open, so this is still PRD 14j's question")
        #expect(try world.read(first).amountPaid == .zero)
        #expect(try world.read(second).amountPaid == .zero)
        #expect(try world.held() == Money(dollars: 500))
    }

    @Test("a priced invoice beside a draft waiting on its times is one of two, so nothing is applied")
    func anUnpricedDraftMakesItTwo() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let priced = Self.invoice(world, owing: Money(dollars: 300))
        Self.unpricedDraft(world)
        try world.context.save()

        #expect(try await world.allocator.placeHeldMoney(on: Self.today).isEmpty)
        #expect(try world.read(priced).amountPaid == .zero)
        #expect(try world.held() == Money(dollars: 500))
    }

    /// PRD 14h WITH ITS ONE OPEN INVOICE UNPRICED. Nothing can go on it yet,
    /// because it owes an amount nobody knows; once priced it is still the one
    /// open invoice, and 14h applies the money there as it always did.
    @Test("a client's only open invoice waiting on its times takes nothing until it is priced, then takes it")
    func theOnlyOpenInvoiceUnpriced() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 100))
        let draft = Self.unpricedDraft(world)
        try world.context.save()

        #expect(try await world.allocator.placeHeldMoney(on: Self.today).isEmpty)
        #expect(try world.held() == Money(dollars: 100))

        try Self.price(draft, in: world)

        #expect(try await world.allocator.placeHeldMoney(on: Self.today) == [draft.persistentModelID])
        #expect(try world.read(draft).amountPaid == Money(dollars: 100))
    }

    /// USE IT HERE ON AN UNPRICED DRAFT SAYS WHY, rather than that nothing is owed,
    /// which would be untrue: something is owed, and nobody knows how much (L11).
    @Test("Use it here on a draft waiting on its times is refused because it has no price, and writes nothing")
    func useItHereOnAnUnpricedDraft() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let draft = Self.unpricedDraft(world)
        Self.unpricedDraft(world)
        try world.context.save()

        await #expect(throws: HeldMoneyRefusal.invoiceIsUnpriced) {
            try await world.allocator.applyHeldMoney(to: draft.persistentModelID, on: Self.today)
        }
        #expect(try world.allocations().isEmpty)
        #expect(try world.held() == Money(dollars: 500))
    }

    @Test("Use it here applies it to that invoice alone, and pressing it again adds nothing")
    func useItHere() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let chosen = Self.invoice(world, owing: Money(cents: 40_828))
        let other = Self.invoice(world, owing: Money(dollars: 300), sent: false)
        try world.context.save()

        let placed = try await world.allocator.applyHeldMoney(to: chosen.persistentModelID,
                                                              on: Self.today)
        #expect(placed == HeldMoneyApplied(applied: Money(cents: 40_828),
                                           stillHeld: Money(cents: 9_172)))
        let again = try await world.allocator.applyHeldMoney(to: chosen.persistentModelID,
                                                             on: Self.today)

        #expect(again == placed, "a second press answers with the first rather than refusing")
        #expect(try world.allocations().count == 1)
        #expect(try world.read(chosen).amountPaid == Money(cents: 40_828))
        #expect(try world.read(other).amountPaid == .zero)
        #expect(try world.allocations().only?.isHeldMoney == true)
    }

    // MARK: Remove, PRD 14i

    /// What applying held money changes, read back whole, so Remove can be held
    /// to restoring every one of them rather than the one somebody thought of.
    private struct Reading: Equatable {
        let subtotal: Money
        let tax: Money
        let total: Money
        let paid: Money
        let outstanding: Money
        let state: InvoicePaymentState
        let held: Money
        let unallocated: [Money]
    }

    private static func reading(_ world: World, _ invoice: Invoice) throws -> Reading {
        let read = try world.read(invoice)
        let payments = try world.fresh().fetch(FetchDescriptor<Payment>())
            .sorted { $0.receivedOn.dayKey < $1.receivedOn.dayKey }
        return Reading(subtotal: read.subtotal, tax: read.tax, total: read.total,
                       paid: read.amountPaid, outstanding: read.amountOutstanding,
                       state: read.paymentState, held: try world.held(),
                       unallocated: payments.map(\.unallocated))
    }

    @Test("Remove is the true inverse of applying it: every figure reads as it did before")
    func removeIsTheInverse() async throws {
        let world = try Self.world()
        world.client.taxStatus = .notExempt
        Self.holding(world, Money(dollars: 500))
        let invoice = Self.invoice(world, owing: Money(cents: 40_828))
        try world.context.save()
        let before = try Self.reading(world, invoice)

        try await world.allocator.placeHeldMoney(on: Self.today)
        let applied = try Self.reading(world, invoice)
        #expect(applied != before, "applying it has to change something for this to prove anything")
        // PRD 14k: below the Total and never inside the subtotal, so the tax base
        // is untouched by applying it.
        #expect(applied.subtotal == before.subtotal)
        #expect(applied.tax == before.tax)
        #expect(applied.total == before.total)

        let released = try await world.allocator.removeHeldMoney(from: invoice.persistentModelID,
                                                                 on: Self.today)

        #expect(released == before.total)
        #expect(try Self.reading(world, invoice) == before)
        // RELEASED, NEVER DELETED (PRD 5.14d): the record of what was decided stays.
        let allocation = try #require(try world.allocations().only)
        #expect(allocation.releasedOn != nil)
        #expect(try world.read(invoice).heldMoneyRemovedOn == Self.today)
    }

    @Test("once removed, Ovation does not put it back by itself, and Use it does")
    func removedStaysRemoved() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let invoice = Self.invoice(world, owing: Money(cents: 40_828))
        try world.context.save()
        try await world.allocator.placeHeldMoney(on: Self.today)
        try await world.allocator.removeHeldMoney(from: invoice.persistentModelID, on: Self.today)

        #expect(try await world.allocator.placeHeldMoney(on: Self.tomorrow).isEmpty,
                "the next pass would otherwise put back what Dan just took off")
        #expect(try world.held() == Money(dollars: 500))

        try await world.allocator.applyHeldMoney(to: invoice.persistentModelID, on: Self.tomorrow)

        let read = try world.read(invoice)
        #expect(read.amountPaid == Money(cents: 40_828))
        #expect(read.heldMoneyRemovedOn == nil, "Use it takes back the decision to remove it")
    }

    @Test("Remove takes off held money and never a payment recorded against the invoice")
    func removeLeavesPaymentsAlone() async throws {
        let world = try Self.world()
        let invoice = Self.invoice(world, owing: Money(dollars: 300))
        try world.context.save()
        try await world.allocator.record(Money(dollars: 100), method: .zelle,
                                         receivedOn: Self.today,
                                         onto: invoice.persistentModelID, press: UUID())
        Self.holding(world, Money(dollars: 50))
        try world.context.save()
        try await world.allocator.placeHeldMoney(on: Self.today)
        #expect(try world.read(invoice).amountPaid == Money(dollars: 150))

        let released = try await world.allocator.removeHeldMoney(from: invoice.persistentModelID,
                                                                 on: Self.today)

        #expect(released == Money(dollars: 50))
        #expect(try world.read(invoice).amountPaid == Money(dollars: 100),
                "the recorded payment still stands")
    }

    @Test("pressing Remove twice takes it off once")
    func removeTwice() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let invoice = Self.invoice(world, owing: Money(cents: 40_828))
        try world.context.save()
        try await world.allocator.placeHeldMoney(on: Self.today)

        try await world.allocator.removeHeldMoney(from: invoice.persistentModelID, on: Self.today)
        let second = try await world.allocator.removeHeldMoney(from: invoice.persistentModelID,
                                                               on: Self.tomorrow)

        #expect(second == .zero)
        #expect(try world.read(invoice).heldMoneyRemovedOn == Self.today,
                "the day it was removed is a fact, and a second press is not a newer one")
        #expect(try world.held() == Money(dollars: 500))
    }

    // MARK: an invoice that shrinks under its held money

    /// ovation#108's rule, which a draft's changing total could otherwise break: an
    /// invoice may never take more than it is owed. A line taken off a draft
    /// carrying held money leaves the allocation bigger than the invoice.
    @Test("a draft whose total falls below its held money gives the difference back to the client")
    func aShrinkingDraftGivesBack() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let draft = Self.invoice(world, owing: Money(dollars: 300), sent: false)
        try world.context.save()
        try await world.allocator.placeHeldMoney(on: Self.today)
        #expect(try world.read(draft).amountPaid == Money(dollars: 300))

        let context = world.fresh()
        let editing = try #require(try context.fetch(FetchDescriptor<Invoice>()).first)
        let line = try #require(editing.lineItems.first)
        line.unitAmount = Money(dollars: 100)
        try context.save()

        let touched = try await world.allocator.placeHeldMoney(on: Self.tomorrow)

        #expect(touched == [draft.persistentModelID])
        let read = try world.read(draft)
        #expect(read.amountPaid == Money(dollars: 100))
        #expect(read.amountOutstanding == .zero, "never below zero")
        #expect(try world.held() == Money(dollars: 400))
        #expect(try await world.allocator.placeHeldMoney(on: Self.tomorrow).isEmpty,
                "and the repair is a fixed point")
    }

    // MARK: refusals, each by name and each writing nothing

    @Test("Use it here refuses by name where it could do nothing, and writes nothing")
    func useItHereRefusals() async throws {
        let world = try Self.world()
        let cancelled = Self.invoice(world, owing: Money(dollars: 300))
        cancelled.closure = .cancelled(on: Self.today, reason: "called off")
        let owesNothing = Self.invoice(world, owing: .zero)
        let open = Self.invoice(world, owing: Money(dollars: 300))
        let unsettled = Self.invoice(world, owing: Money(dollars: 300), sent: false)
        unsettled.recordSendState(.couldNotDetermine(checkedAt: Self.noon))
        let clientless = Invoice(client: nil, kind: .photography, invoiceDate: Self.today,
                                 hourlyRate: Money(dollars: 250), taxRate: .newYorkCity,
                                 createdOn: Self.today)
        world.context.insert(clientless)
        clientless.add(LineItem.flat(Money(dollars: 300), describedAs: "Photography"))
        try world.context.save()
        let allocator = world.allocator

        await #expect(throws: HeldMoneyRefusal.invoiceIsClosed) {
            try await allocator.applyHeldMoney(to: cancelled.persistentModelID, on: Self.today)
        }
        await #expect(throws: HeldMoneyRefusal.nothingIsOwed) {
            try await allocator.applyHeldMoney(to: owesNothing.persistentModelID, on: Self.today)
        }
        await #expect(throws: HeldMoneyRefusal.sendIsUnsettled) {
            try await allocator.applyHeldMoney(to: unsettled.persistentModelID, on: Self.today)
        }
        await #expect(throws: HeldMoneyRefusal.invoiceHasNoClient) {
            try await allocator.applyHeldMoney(to: clientless.persistentModelID, on: Self.today)
        }
        await #expect(throws: HeldMoneyRefusal.clientHoldsNothing) {
            try await allocator.applyHeldMoney(to: open.persistentModelID, on: Self.today)
        }
        #expect(try world.allocations().isEmpty)
    }

    @Test("an invoice deleted since the screen read it is refused by name")
    func aDeletedInvoiceIsRefused() async throws {
        let world = try Self.world()
        let invoice = Self.invoice(world, owing: Money(dollars: 300))
        try world.context.save()
        let id = invoice.persistentModelID
        world.context.delete(invoice)
        try world.context.save()

        await #expect(throws: HeldMoneyRefusal.noSuchInvoice) {
            try await world.allocator.applyHeldMoney(to: id, on: Self.today)
        }
        await #expect(throws: HeldMoneyRefusal.noSuchInvoice) {
            try await world.allocator.removeHeldMoney(from: id, on: Self.today)
        }
    }

    /// ovation#589. THE GUARD LIVES WITH THE WRITE (L42). The invoice screen offers
    /// no Remove on a cancelled invoice, but the writer must refuse on its own, as
    /// `applyHeldMoney` already does: releasing a closed invoice's held money would
    /// change a closed record's figures and stamp a decision on it.
    @Test("Remove on a cancelled invoice is refused by name and changes nothing")
    func removeOnAClosedInvoiceIsRefused() async throws {
        let world = try Self.world()
        Self.holding(world, Money(dollars: 500))
        let invoice = Self.invoice(world, owing: Money(dollars: 300))
        try world.context.save()
        try await world.allocator.placeHeldMoney(on: Self.today)
        #expect(try world.read(invoice).amountPaid == Money(dollars: 300),
                "held money has to be on it for the refusal to protect anything")

        // Closed straight in the store, as the premise needs: InvoiceCloser would
        // release the money itself, and this is about a closed invoice still
        // carrying some, which the writer cannot assume never exists.
        let context = world.fresh()
        let closing = try #require(try context.fetch(FetchDescriptor<Invoice>())
            .first { $0.id == invoice.id })
        closing.closure = .cancelled(on: Self.today, reason: "the concert was called off")
        try context.save()
        let before = try world.allocations().map { $0.releasedOn }

        await #expect(throws: HeldMoneyRefusal.invoiceIsClosed) {
            try await world.allocator.removeHeldMoney(from: invoice.persistentModelID,
                                                      on: Self.tomorrow)
        }
        #expect(try world.allocations().map { $0.releasedOn } == before)
        #expect(try world.read(invoice).heldMoneyRemovedOn == nil)
        #expect(try world.read(invoice).amountPaid == Money(dollars: 300))
    }

    @Test("Remove on an invoice carrying no held money is refused by name and writes nothing")
    func nothingToRemove() async throws {
        let world = try Self.world()
        let invoice = Self.invoice(world, owing: Money(dollars: 300))
        try world.context.save()

        await #expect(throws: HeldMoneyRefusal.nothingToRemove) {
            try await world.allocator.removeHeldMoney(from: invoice.persistentModelID,
                                                      on: Self.today)
        }
        #expect(try world.read(invoice).heldMoneyRemovedOn == nil,
                "a refused Remove records no decision")
    }

    @Test("every refusal says which thing stopped it, in words of its own")
    func everyRefusalHasItsOwnSentence() {
        let all: [HeldMoneyRefusal] = [.noSuchInvoice, .invoiceIsClosed, .invoiceHasNoClient,
                                       .nothingIsOwed, .sendIsUnsettled, .clientHoldsNothing,
                                       .nothingToRemove, .invoiceIsUnpriced]
        let sentences = all.map(\.sentence)
        #expect(Set(sentences).count == all.count)
        #expect(sentences.allSatisfy { !$0.isEmpty })
    }
}

private extension Array {
    /// The one element, or nil where there is not exactly one.
    var only: Element? { count == 1 ? first : nil }
}
