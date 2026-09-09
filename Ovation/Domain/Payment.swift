// ovation#60 step 3b, PRD 5.14 to 5.15. Money that arrived, and where it went.
//
// A PAYMENT IS ITS OWN RECORD, NOT A CHILD OF AN INVOICE. Dan settled this on
// 2026-09-06, replacing the earlier shape. One check settling two invoices is ONE
// record for the amount actually written, split between them, so what is stored
// is what the bank shows rather than a pair of halves nobody wrote.
//
// PAID IN FULL IS CALCULATED AND NEVER TYPED, from what is ALLOCATED to an
// invoice. A stored paid flag is a second copy of a number the allocations
// already answer, and the copy is the one that would be believed (L107).
//
// MONEY RECEIVED AND NOT YET ALLOCATED IS A REAL STATE, NOT AN ERROR (PRD 5.14a).
// It is where an overpayment goes and where a deposit taken before the shoot
// goes. It belongs to the CLIENT and is surfaced under Clients, never on the
// invoice list; how it appears there is ovation#98 and is deliberately not
// decided here.
//
// IT IS NOT REFERRAL CREDIT AND MUST NEVER BE ADDED TO IT (PRD 5.14c). Both read
// as a balance on a client screen, which is exactly why they are easy to merge:
// unallocated money actually arrived and is owed back if it is never used, and
// credit was earned against a ledger and is spent as a negative line inside an
// invoice. Merging them would let credit nobody paid settle an invoice.
import Foundation
import SwiftData

extension OvationSchemaV1 {
    @Model
    final class Payment {
        var id: UUID = UUID()

        var client: Client?

        /// The amount actually written, stamped with the business day it arrived.
        var amount: Money = Money.zero
        var receivedOn: BusinessDate = BusinessDate(storedInstant: .distantPast, storedDayKey: "")

        var method: PaymentMethod = PaymentMethod.zelle

        /// PRD 5.15. CLEARED BELONGS TO THE PAYMENT AND NEVER TO AN ALLOCATION, so
        /// one check clears once however many invoices it settled, and an invoice can
        /// never be cleared on its own.
        ///
        /// SETTABLE ONLY THROUGH `markCleared` (ovation#48). The rule that only a
        /// check has a cleared step lived in that method, which every call site
        /// had to choose to use; a rule each caller must opt into is not enforced
        /// by anything and the first site that assigns the field directly gives a
        /// Zelle payment a cleared date nothing can explain (L621, L27). A
        /// `private(set)` makes the omission impossible rather than discouraged.
        private(set) var clearedOn: BusinessDate?

        /// A check number, a Zelle reference, whatever identifies it on a statement.
        var reference: String?

        /// Deleting a payment takes its allocations with it: they are statements
        /// about money this record represents and mean nothing without it. Releasing
        /// one is a different thing entirely and does not delete anything, see
        /// `PaymentAllocation.releasedOn`.
        @Relationship(deleteRule: .cascade, inverse: \PaymentAllocation.payment)
        var allocations: [PaymentAllocation] = []

        init(client: Client?, amount: Money, method: PaymentMethod, receivedOn: BusinessDate) {
            self.client = client
            self.amount = amount
            self.method = method
            self.receivedOn = receivedOn
        }

        /// The allocations that still stand. A released one is kept for the record
        /// and counts towards nothing.
        var activeAllocations: [PaymentAllocation] { allocations.filter { $0.releasedOn == nil } }

        /// THE ONE PREDICATE. Every reader of how much of this payment is spoken for
        /// goes through here, so a count and the rows it promises cannot disagree
        /// (L16).
        var allocated: Money { Money.sum(of: activeAllocations.map(\.amount)) }

        /// What is still being held on the client's behalf.
        var unallocated: Money { amount - allocated }

        var canBeCleared: Bool { method.gainsAClearedStep }

        /// Records that a check cleared. Answers whether it did anything, because a
        /// control that silently does nothing is worse than one that refuses (L109).
        @discardableResult
        func markCleared(on day: BusinessDate) -> Bool {
            guard canBeCleared else { return false }
            clearedOn = day
            return true
        }
    }
}

/// One decision that a share of one payment settles one invoice.
///
/// IT IS RELEASED, NEVER DELETED (PRD 5.14d). Cancelling an invoice that carries
/// allocations returns the money to unallocated on the client, and the money
/// still exists and still arrived. Deleting the row would destroy the record of
/// what was decided and when, which is the question an audit exists to answer
/// (L529).
extension OvationSchemaV1 {
    @Model
    final class PaymentAllocation {
        var id: UUID = UUID()

        var payment: Payment?
        var invoice: Invoice?

        var amount: Money = Money.zero
        var allocatedOn: BusinessDate = BusinessDate(storedInstant: .distantPast, storedDayKey: "")

        /// When it stopped standing. Nil while it stands.
        var releasedOn: BusinessDate?

        init(payment: Payment?, invoice: Invoice?, amount: Money, allocatedOn: BusinessDate) {
            self.payment = payment
            self.invoice = invoice
            self.amount = amount
            self.allocatedOn = allocatedOn
        }
    }
}

/// Money that went back out. PRD 5.13.
///
/// It carries its OWN date, because under the accrual basis the invoice was
/// income in the year it was issued and a refund can move in a different calendar
/// year. How that is reported is one of the questions for the accountant recorded
/// in PRD 9.3, so nothing here asserts a year for it.
extension OvationSchemaV1 {
    @Model
    final class Refund {
        var id: UUID = UUID()

        var invoice: Invoice?
        /// Which payment went back, where it was one payment.
        var payment: Payment?

        var amount: Money = Money.zero
        var refundedOn: BusinessDate = BusinessDate(storedInstant: .distantPast, storedDayKey: "")
        var method: PaymentMethod?
        var note: String?

        init(
            invoice: Invoice?, payment: Payment?, amount: Money,
            refundedOn: BusinessDate, method: PaymentMethod?
        ) {
            self.invoice = invoice
            self.payment = payment
            self.amount = amount
            self.refundedOn = refundedOn
            self.method = method
        }
    }
}

// THE NAME THE REST OF THE APP USES (ovation#134). The type belongs to a
// schema VERSION, because a version has to be able to describe a shape that
// is no longer current. Everything outside the store speaks about the shape
// in force, so it says the bare name and this is what points that name at the
// version in force. When a version 2 exists, this line moves to it and every
// call site is already correct.
typealias Payment = OvationSchemaV1.Payment
typealias PaymentAllocation = OvationSchemaV1.PaymentAllocation
typealias Refund = OvationSchemaV1.Refund
