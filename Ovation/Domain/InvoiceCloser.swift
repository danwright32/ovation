// ovation#47, PRD 5.13 and 5.14d. Cancelling an invoice, which is more than a
// status change.
//
// THE PRIOR YEAR REFUSAL. Under accrual an invoice issued in a prior tax year is
// income already reported (PRD 24), so cancelling it removes income from a return
// that has been filed. Ovation refuses, NAMES the year, and leaves the invoice
// standing until Dan has raised it with his accountant. The sentence says what to
// do instead, because a control that is dead with no reason is one somebody
// presses repeatedly and then works around (L109, L148).
//
// THE MONEY IS A REQUIRED ANSWER RATHER THAN A QUESTION A SCREEN MAY FORGET. The
// plan says cancelling an invoice carrying payments asks what happened to the
// money and records a refund with its own date. Written as an optional argument
// that defaults to "nothing happened", the case that matters would be the quiet
// one; here an invoice with money against it REFUSES until the caller says, so
// the omission is impossible rather than discouraged (L621, L168).
//
// IT IS A VERSION, NOT AN ERASURE. The number is never reused, because a gap in a
// sequence is explainable and a number that means two different things is not.
// The allocations are RELEASED rather than deleted (PRD 5.14d): an allocation is
// a statement about money that actually arrived, so it outlives the invoice it
// was pointed at, and deleting it would destroy the record of what was decided
// and when (L529).
//
// A DRAFT IS NOT CANCELLED, IT IS DISMISSED. It was never issued, so there is no
// income to remove and nothing a client has seen. Two words for two states, and
// folding them would make a cancelled invoice and an abandoned draft the same row
// (L11). ovation#150 owns dismissing.
//
// IT IS A SERIALIZED WRITER for the same reason `PaymentAllocator` is: the checks
// above are read, decide, write, and a screen's own context would make them
// advice rather than enforcement. Everything one cancellation does happens in ONE
// context and ONE save, so a crash cannot leave the allocations released and the
// invoice still open (L33).
import Foundation
import SwiftData

/// What happened to money that had already arrived. There is no default: the
/// caller says which, or the cancellation refuses.
enum CancelledInvoiceMoney: Equatable, Sendable {
    /// It went back, on its own date, which is not the cancellation's date.
    case refunded(amount: Money, on: BusinessDate, method: PaymentMethod?)
    /// Nothing went back. The allocations are released and the money stays on the
    /// client for the next invoice, where PRD 5.14a already gives it a home.
    case heldForTheClient
}

enum CancellationRefusal: Error, Equatable {
    /// The income was reported on a return that has been filed.
    case fromAPriorTaxYear(year: Int)
    /// Money has arrived against it and the caller did not say what happened.
    case moneyIsNotAccountedFor(paid: Money)
    /// Money that never arrived cannot go back. Carries both numbers so the
    /// caller can offer what is actually possible.
    case refundExceedsWhatWasPaid(paid: Money, asked: Money)
    /// It is a draft. Dismissing is the word for that (ovation#150).
    case neverIssued
    /// It has been cancelled or dismissed already, carrying the day it happened.
    case alreadyClosed(on: String)
    case noSuchInvoice

    /// What Dan is told. Each names what to do rather than only refusing.
    var sentence: String {
        switch self {
        case .fromAPriorTaxYear(let year):
            return "This invoice belongs to the \(year) tax year, and that year's income has "
                + "already been reported. Cancelling it here would take income off a return "
                + "that has been filed, so Ovation has left it standing. Raise it with your "
                + "accountant and record what they decide."
        case .moneyIsNotAccountedFor(let paid):
            return "\(paid.exportAmount) has been paid against this invoice, so cancelling it "
                + "needs an answer about the money: it was refunded, on its own date, or it "
                + "stays on the client for the next invoice. Nothing has been changed."
        case .refundExceedsWhatWasPaid(let paid, let asked):
            return "The refund of \(asked.exportAmount) is more than the \(paid.exportAmount) "
                + "that arrived against this invoice. Money that never arrived cannot go back. "
                + "Nothing has been changed."
        case .neverIssued:
            return "This invoice has never been sent, so there is nothing to cancel: no client "
                + "has seen it and no income was reported. Dismiss the draft instead, which "
                + "keeps it out of the way without pretending it was ever issued."
        case .alreadyClosed(let day):
            return "This invoice was already closed on \(day), and closing it again would "
                + "overwrite the reason and the date recorded then. Nothing has been changed."
        case .noSuchInvoice:
            return "That invoice is no longer in the store, so there was nothing to cancel. "
                + "It may have been removed by another window since this one read it."
        }
    }
}

@ModelActor
actor InvoiceCloser {

    /// Cancels one issued invoice.
    ///
    /// - Parameters:
    ///   - money: what happened to anything already paid. Required whenever
    ///     something has been; refused when it is missing and needed, and
    ///     ignored when nothing has arrived.
    ///   - on: the day the cancellation is recorded against.
    ///   - now: what decides which tax year is the current one. Injected rather
    ///     than read from the clock, so the prior year rule can be tested at a
    ///     chosen moment instead of only in whatever year the suite runs (L130).
    func cancel(_ invoiceID: PersistentIdentifier, reason: String,
                money: CancelledInvoiceMoney?, on day: BusinessDate, now: Date) throws {
        // FETCHED RATHER THAN SUBSCRIPTED, and this is measured rather than
        // stylistic: `self[id, as:]` on a model deleted since the caller read it
        // TRAPS with "this model instance was invalidated", which takes the whole
        // process down instead of refusing. `PaymentAllocator` already learned it
        // (ovation#108), and the test that catches it here crashed the test
        // runner, which then reported the remaining test as a passing run.
        guard let invoice = try modelContext.fetch(FetchDescriptor<Invoice>())
            .first(where: { $0.persistentModelID == invoiceID }) else {
            throw CancellationRefusal.noSuchInvoice
        }

        if let closure = invoice.closure {
            throw CancellationRefusal.alreadyClosed(on: closure.closedOn.dayKey)
        }

        // SENT IS THE TEST, not the presence of a number, because Sent is what
        // makes it income at all (PRD 24b, ovation#45). An invoice with a number
        // that was never sent is still a draft.
        guard invoice.sentStatus.wasSent else {
            throw CancellationRefusal.neverIssued
        }

        // THE STAMPED DAY DECIDES THE YEAR, never the instant. An invoice dated 31
        // December in Dan's shooting zone is already the next year in UTC, and a
        // rule reading the instant would refuse a December invoice cancelled in
        // the same week (ovation#55).
        if let dayKey = invoice.invoiceDate?.dayKey,
           let invoiceYear = BusinessCalendar.year(forDayKey: dayKey),
           invoiceYear < BusinessCalendar.year(for: now) {
            throw CancellationRefusal.fromAPriorTaxYear(year: invoiceYear)
        }

        let paid = invoice.amountPaid
        if paid > .zero {
            guard let money else {
                throw CancellationRefusal.moneyIsNotAccountedFor(paid: paid)
            }
            if case .refunded(let amount, _, _) = money, amount > paid {
                throw CancellationRefusal.refundExceedsWhatWasPaid(paid: paid, asked: amount)
            }
        }

        // From here everything is one context and one save.
        if paid > .zero, case .refunded(let amount, let refundedOn, let method) = money {
            let refund = Refund(invoice: invoice, payment: nil, amount: amount,
                                refundedOn: refundedOn, method: method)
            modelContext.insert(refund)
            invoice.refunds.append(refund)
        }

        invoice.releaseActiveAllocations(on: day)
        invoice.closure = .cancelled(on: day, reason: reason)
        try modelContext.save()
    }
}
