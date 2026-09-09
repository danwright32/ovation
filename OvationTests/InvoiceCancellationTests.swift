import Foundation
import SwiftData
import Testing
@testable import Ovation

/// ovation#47, PRD 5.13. Cancelling an invoice, and the two things that make it
/// more than a status change.
///
/// THE PRIOR YEAR REFUSAL. Under accrual an invoice issued in a prior tax year is
/// income already reported, so cancelling it removes income from a return that
/// has been filed. Ovation refuses, names the year, and leaves the invoice
/// standing until Dan has raised it with his accountant. The refusal carries its
/// own sentence, because a control that is dead with no reason is one somebody
/// presses repeatedly and then works around (L109, L148).
///
/// THE MONEY MUST BE ACCOUNTED FOR. A cancelled invoice that has been paid is a
/// different situation from one that has not, and the plan decides it: cancelling
/// an invoice carrying payments asks what happened to the money and records a
/// refund with its own date. So the ANSWER is a required argument here rather
/// than a question a screen may forget to ask: a behaviour each call site must
/// opt into is enforced by nothing (L621).
///
/// AND IT IS A VERSION RATHER THAN AN ERASURE. The number is not reused, the
/// allocations are released rather than deleted, and the refund is a row of its
/// own. A gap in a sequence is explainable; a number that means two things is not.
@MainActor
struct InvoiceCancellationTests {

    // MARK: it cancels

    @Test("an issued invoice with no money against it is cancelled")
    func aplainCancellation() async throws {
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, number: 12)
        try world.save()

        try await world.closer().cancel(invoice.persistentModelID,
                                        reason: "the show was called off",
                                        money: nil, on: .stamping(World.now), now: World.now)

        let read = try world.reread(invoice)
        guard case .cancelled(let on, let reason) = read.closure else {
            Issue.record("it was not cancelled: \(String(describing: read.closure))")
            return
        }
        #expect(reason == "the show was called off")
        #expect(on.dayKey == BusinessCalendar.dayKey(for: World.now))
    }

    @Test("the number is NOT reused, because a gap is explainable and a repeat is not")
    func thenumberSurvivesCancellation() async throws {
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, number: 12)
        try world.save()

        try await world.closer().cancel(invoice.persistentModelID, reason: "called off",
                                        money: nil, on: .stamping(World.now), now: World.now)

        #expect(try world.reread(invoice).number == 12)
    }

    @Test("a cancelled invoice is still there, with its shoots and its line items")
    func cancellationIsNotAnErasure() async throws {
        // An edit that deletes and recreates discards everything accumulated
        // alongside the invoice (L580). Cancelling is the same shape and must not.
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, number: 12)
        try world.save()

        try await world.closer().cancel(invoice.persistentModelID, reason: "called off",
                                        money: nil, on: .stamping(World.now), now: World.now)

        let read = try world.reread(invoice)
        #expect(read.lineItems.count == 1)
        #expect(read.total > .zero, "and it still says what it was for")
    }

    // MARK: the prior year refusal

    @Test("an invoice from a prior tax year is REFUSED, and the refusal names the year")
    func apriorYearInvoiceIsRefused() async throws {
        let world = try World()
        let invoice = world.invoice(dayKey: "2025-06-01", sent: true, number: 3)
        try world.save()

        do {
            try await world.closer().cancel(invoice.persistentModelID, reason: "called off",
                                            money: nil, on: .stamping(World.now), now: World.now)
            Issue.record("a prior year invoice was cancelled")
        } catch let refusal as CancellationRefusal {
            #expect(refusal == .fromAPriorTaxYear(year: 2025))
            #expect(refusal.sentence.contains("2025"))
            #expect(refusal.sentence.lowercased().contains("accountant"),
                    "and it says what to do instead rather than only refusing")
        }

        #expect(try world.reread(invoice).closure == nil, "and it is left standing")
    }

    @Test("an invoice from THIS tax year is not refused, so the rule is not simply always on")
    func thisyearIsAllowed() async throws {
        // The positive control. A refusal that fired on everything would satisfy
        // the test above and make cancelling impossible (L159).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-01-01", sent: true, number: 4)
        try world.save()

        try await world.closer().cancel(invoice.persistentModelID, reason: "called off",
                                        money: nil, on: .stamping(World.now), now: World.now)

        #expect(try world.reread(invoice).closure != nil)
    }

    @Test("the year is the one the invoice is STAMPED with, not the one it is cancelled in")
    func theyearComesFromTheStamp() async throws {
        // The stamped day key decides the tax year everywhere else (ovation#55),
        // and an invoice dated 31 December in Dan's shooting zone is already the
        // next year in UTC. A rule reading the instant would refuse a December
        // invoice cancelled the same week.
        let world = try World()
        let lateOnNewYearsEve = ISO8601DateFormatter().date(from: "2027-01-01T04:30:00Z")!
        #expect(BusinessCalendar.dayKey(for: lateOnNewYearsEve) == "2026-12-31")
        let invoice = world.invoice(stamping: lateOnNewYearsEve, sent: true, number: 5)
        try world.save()

        try await world.closer().cancel(invoice.persistentModelID, reason: "called off",
                                        money: nil, on: .stamping(World.now), now: World.now)

        #expect(try world.reread(invoice).closure != nil,
                "2026 is the current year here, so this is not a prior year invoice")
    }

    // MARK: the money

    @Test("an invoice carrying money REFUSES unless the caller says what happened to it")
    func moneyMustBeAccountedFor() async throws {
        // The question the plan says cancelling asks. Making it a required answer
        // rather than a screen's responsibility is what stops a call site
        // forgetting it (L621).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, number: 6)
        world.pay(invoice, Money(dollars: 100))
        try world.save()

        do {
            try await world.closer().cancel(invoice.persistentModelID, reason: "called off",
                                            money: nil, on: .stamping(World.now), now: World.now)
            Issue.record("an invoice carrying money was cancelled with no answer")
        } catch let refusal as CancellationRefusal {
            guard case .moneyIsNotAccountedFor(let paid) = refusal else {
                Issue.record("it refused for the wrong reason: \(refusal)")
                return
            }
            #expect(paid == Money(dollars: 100))
        }

        #expect(try world.reread(invoice).closure == nil)
    }

    @Test("refunding it records a refund of its own, with its own date")
    func refundingRecordsARefund() async throws {
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, number: 7)
        world.pay(invoice, Money(dollars: 100))
        try world.save()

        let refundDay = BusinessDate.stamping(
            BusinessCalendar.startOfDay(forDayKey: "2026-07-04")!)
        try await world.closer().cancel(
            invoice.persistentModelID, reason: "called off",
            money: .refunded(amount: Money(dollars: 100), on: refundDay, method: .zelle),
            on: .stamping(World.now), now: World.now)

        let read = try world.reread(invoice)
        #expect(read.refunds.count == 1)
        #expect(read.refunds.first?.amount == Money(dollars: 100))
        #expect(read.refunds.first?.refundedOn.dayKey == "2026-07-04",
                "the refund's own date, not the cancellation's")
        #expect(read.closure != nil)
    }

    @Test("and the allocations are RELEASED rather than destroyed")
    func cancellingReleasesRatherThanDeletes() async throws {
        // PRD 5.14d. An allocation is a statement about money that actually
        // arrived, so it outlives the invoice it was pointed at; deleting the row
        // would destroy the record of what was decided and when (L529).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, number: 8)
        let payment = world.pay(invoice, Money(dollars: 100))
        try world.save()

        try await world.closer().cancel(
            invoice.persistentModelID, reason: "called off",
            money: .refunded(amount: Money(dollars: 100),
                             on: .stamping(World.now), method: .zelle),
            on: .stamping(World.now), now: World.now)

        let read = try world.reread(invoice)
        #expect(read.allocations.count == 1, "the record of the decision is kept")
        #expect(read.allocations.first?.releasedOn != nil)
        #expect(read.amountPaid == .zero, "and it no longer counts against the invoice")
        let readPayment = try world.reread(payment)
        #expect(readPayment.unallocated == Money(dollars: 100),
                "so the money is back on the client rather than gone")
    }

    @Test("keeping the money on the client releases it without inventing a refund")
    func keepingTheMoneyRecordsNoRefund() async throws {
        // The other honest answer: nothing went back, and the money stays on the
        // client for the next invoice. A cancellation that always wrote a refund
        // would put money on the return that never moved.
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, number: 9)
        world.pay(invoice, Money(dollars: 100))
        try world.save()

        try await world.closer().cancel(invoice.persistentModelID, reason: "called off",
                                        money: .heldForTheClient,
                                        on: .stamping(World.now), now: World.now)

        let read = try world.reread(invoice)
        #expect(read.refunds.isEmpty)
        #expect(read.amountPaid == .zero)
        #expect(read.closure != nil)
    }

    @Test("a refund for more than was paid is refused, carrying both numbers")
    func arefundCannotExceedWhatArrived() async throws {
        // Money that never arrived cannot go back, and a refusal that says what
        // is actually possible lets the caller offer that instead (L11).
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, number: 10)
        world.pay(invoice, Money(dollars: 100))
        try world.save()

        do {
            try await world.closer().cancel(
                invoice.persistentModelID, reason: "called off",
                money: .refunded(amount: Money(dollars: 250),
                                 on: .stamping(World.now), method: .zelle),
                on: .stamping(World.now), now: World.now)
            Issue.record("a refund larger than the payment was accepted")
        } catch let refusal as CancellationRefusal {
            #expect(refusal == .refundExceedsWhatWasPaid(paid: Money(dollars: 100),
                                                         asked: Money(dollars: 250)))
        }
        #expect(try world.reread(invoice).closure == nil, "and nothing was written")
    }

    // MARK: what cannot be cancelled

    @Test("a DRAFT is not cancelled, it is dismissed, and the refusal says so")
    func adraftIsNotCancellable() async throws {
        // Two words for two states. A draft was never issued, so there is no
        // income to remove and nothing a client has seen; ovation#150 owns
        // dismissing one. Folding them would make a cancelled invoice and an
        // abandoned draft the same row (L11).
        let world = try World()
        let draft = world.invoice(dayKey: "2026-06-01", sent: false, number: nil)
        try world.save()

        do {
            try await world.closer().cancel(draft.persistentModelID, reason: "changed my mind",
                                            money: nil, on: .stamping(World.now), now: World.now)
            Issue.record("a draft was cancelled")
        } catch let refusal as CancellationRefusal {
            #expect(refusal == .neverIssued)
            #expect(refusal.sentence.lowercased().contains("dismiss"))
        }
    }

    @Test("an invoice already closed is refused rather than closed twice")
    func analreadyClosedInvoiceIsRefused() async throws {
        // Assume it runs twice: a retry, a double press, a second window. The
        // second must not overwrite the first cancellation's date and reason.
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, number: 11)
        try world.save()
        try await world.closer().cancel(invoice.persistentModelID, reason: "the first reason",
                                        money: nil, on: .stamping(World.now), now: World.now)

        do {
            try await world.closer().cancel(invoice.persistentModelID, reason: "the second reason",
                                            money: nil, on: .stamping(World.now), now: World.now)
            Issue.record("it was cancelled twice")
        } catch let refusal as CancellationRefusal {
            guard case .alreadyClosed = refusal else {
                Issue.record("it refused for the wrong reason: \(refusal)")
                return
            }
        }

        guard case .cancelled(_, let reason) = try world.reread(invoice).closure else {
            Issue.record("the first cancellation did not stand")
            return
        }
        #expect(reason == "the first reason")
    }

    @Test("an invoice that is not there is refused by name rather than crashing")
    func amissingInvoiceIsRefused() async throws {
        let world = try World()
        let invoice = world.invoice(dayKey: "2026-06-01", sent: true, number: 13)
        try world.save()
        let id = invoice.persistentModelID
        world.context.delete(invoice)
        try world.save()

        do {
            try await world.closer().cancel(id, reason: "called off", money: nil,
                                            on: .stamping(World.now), now: World.now)
            Issue.record("a deleted invoice was cancelled")
        } catch let refusal as CancellationRefusal {
            #expect(refusal == .noSuchInvoice)
        }
    }

    @Test("every refusal can say what happened, in a sentence that is not a case name")
    func everyRefusalHasASentence() {
        let refusals: [CancellationRefusal] = [
            .fromAPriorTaxYear(year: 2025),
            .moneyIsNotAccountedFor(paid: Money(dollars: 100)),
            .refundExceedsWhatWasPaid(paid: Money(dollars: 100), asked: Money(dollars: 250)),
            .neverIssued,
            .alreadyClosed(on: "2026-06-01"),
            .noSuchInvoice
        ]
        for refusal in refusals {
            #expect(refusal.sentence.count > 40,
                    Comment(rawValue: "\(refusal) says too little"))
        }
    }

    // MARK: fixtures

    @MainActor
    private final class World {
        static let now = Date(timeIntervalSince1970: 1_780_000_000)  // 2026-06-08
        let container: ModelContainer
        let context: ModelContext

        init() throws {
            container = try OvationSchema.container(inMemory: true)
            context = ModelContext(container)
        }

        func closer() -> InvoiceCloser { InvoiceCloser(modelContainer: container) }
        func save() throws { try context.save() }

        /// Read back through a FRESH context, because the writer has its own and
        /// a context holding an object from before another wrote to it still
        /// holds the old value (ovation#133, measured).
        func reread<T: PersistentModel>(_ model: T) throws -> T {
            let id = model.persistentModelID
            let reader = ModelContext(container)
            guard let read = reader.model(for: id) as? T else {
                throw CancellationRefusal.noSuchInvoice
            }
            return read
        }

        @discardableResult
        func invoice(dayKey: String? = nil, stamping instant: Date? = nil,
                     sent: Bool, number: Int64?) -> Invoice {
            let date = instant ?? dayKey.flatMap { BusinessCalendar.startOfDay(forDayKey: $0) }
            let client = Client(name: "A fictional ensemble", taxStatus: .notExempt)
            context.insert(client)
            let invoice = Invoice(client: client, kind: .photography,
                                  invoiceDate: date.map { BusinessDate.stamping($0) },
                                  hourlyRate: Money(dollars: 100), taxRate: .newYorkCity)
            context.insert(invoice)
            invoice.number = number
            invoice.add(LineItem.flat(Money(dollars: 100), describedAs: "Photography"))
            if sent {
                invoice.sentStatus = .sent(route: .ovationSentIt, at: Self.now)
            }
            return invoice
        }

        @discardableResult
        func pay(_ invoice: Invoice, _ amount: Money) -> Payment {
            let payment = Payment(client: invoice.client, amount: amount,
                                  method: .zelle, receivedOn: .stamping(Self.now))
            context.insert(payment)
            let allocation = PaymentAllocation(payment: payment, invoice: invoice,
                                               amount: amount, allocatedOn: .stamping(Self.now))
            context.insert(allocation)
            payment.allocations.append(allocation)
            invoice.allocations.append(allocation)
            return payment
        }
    }
}
