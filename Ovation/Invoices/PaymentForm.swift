// ovation#510, PRD 51m. What the payment sheet holds while it is open, and every
// rule about it, as a value.
//
// THE RULES LIVE HERE AND NOT IN THE VIEW, because a view tree test cannot type
// into a field and then see what a view's own state made of it (L442). So the
// sheet draws this value and hands edits to it, and what counts as a readable
// amount, a readable date, a change, and the reason Record is unavailable are all
// answered here, where a plain test can reach every one of them.
//
// THE READERS ARE THE APP'S OWN. An amount is read by `Money.read` and a date by
// `PaymentTerms.read`, the two every other typed figure and date on the invoice
// screen already go through, so the sheet cannot come to accept a form the due
// date refuses (L370).
import Foundation

/// A payment the sheet hands back when Record is pressed.
struct PaymentEntry: Equatable, Sendable {
    let amount: Money
    let method: PaymentMethod
    let received: BusinessDate
    /// The press, which becomes the payment's identity, so the same press
    /// arriving twice records one payment (`PaymentAllocator.record`).
    let press: UUID
}

struct PaymentForm: Equatable {
    var amount: String
    var received: String
    var method: PaymentMethod
    /// What the sheet opened with, which is what "changed" is measured from.
    let opened: Opened

    struct Opened: Equatable {
        let amount: String
        let received: String
        let method: PaymentMethod
    }

    /// The sheet as it opens: what is owed, today, and Zelle (PRD 51m).
    init(starting start: InvoiceScreenPresenter.PaymentStart) {
        let day = BusinessCalendar.shortDate(start.received) ?? ""
        opened = Opened(amount: start.amount, received: day, method: start.method)
        amount = start.amount
        received = day
        method = start.method
    }

    /// Whether anything differs from how the sheet opened, which decides whether
    /// a click outside it or Escape closes it or asks first (Dan, 2026-09-25).
    var changed: Bool {
        amount != opened.amount || received != opened.received || method != opened.method
    }

    /// Why Record is unavailable, or nil where it may be pressed. The amount is
    /// asked about first, because it is the field the sheet opens on.
    var whyNot: String? {
        guard let money = Money.read(amount), money > .zero else { return "Needs an amount." }
        guard PaymentTerms.read(received) != nil else { return "Needs a date like 26 Sep 2026." }
        return nil
    }

    /// The payment Record hands back, or nil where it cannot be recorded.
    func entry(press: UUID) -> PaymentEntry? {
        guard whyNot == nil,
              let money = Money.read(amount),
              let day = PaymentTerms.read(received) else { return nil }
        return PaymentEntry(amount: money, method: method, received: day, press: press)
    }
}
