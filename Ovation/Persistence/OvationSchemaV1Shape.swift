// ovation#382 and ovation#134. WHAT VERSION 1 HELD, frozen, so version 2 has
// something to migrate FROM.
//
// THIS FILE IS HISTORY AND IS NEVER EDITED TO MATCH THE APP. Every class here
// describes the shape that was on disk before version 2, and the only legitimate
// change to it is a correction where it fails to describe that shape. Adding a
// field the app grew, or deleting one the app dropped, makes version 1 describe
// version 2 and leaves the stage between them with nothing to carry (L70).
//
// WHY A FULL COPY OF ALL TEN RATHER THAN THE ONE TYPE THAT CHANGED. The schema
// file used to say a version could declare its own copy of whatever changed and
// name the previous version's types for everything else, "which is what keeps ten
// identical copies from appearing the first time one field moves". MEASURED FALSE
// on 2026-09-19, macOS 26.5.1, in a standalone program and then as a standing case
// in SchemaMigrationTests: with two versions of ONE entity in the process and the
// other entity reused from the older version, writing a row and setting the
// relationship dies with
//
//     Fatal error: Failed to cast model RelV2.Parent for PersistentIdentifier(...)
//                  to Parent
//
// because SwiftData keys an entity by its CLASS NAME, so the reused type's
// relationship resolves to the wrong version's class. Duplicating BOTH entities
// works, carries the rows, drops the removed column and keeps the link. Every one
// of Ovation's ten models is in one relationship graph, so every one is copied.
// That belief was load bearing and wrong, and it is corrected where it was stated
// rather than annotated (L244).
//
// THE VALUE TYPES ARE NOT FROZEN WITH IT, and that is a stated limitation rather
// than an oversight. `Money`, `BusinessDate`, `ShootWhen`, `Discount` and the
// vocabularies are global Codable types shared by both versions, so a change to
// one of THEM changes what this file describes. The day a stored value type
// changes shape, it needs the same treatment as these classes.
//
// NOTHING HERE HAS BEHAVIOUR. No computed properties, no methods, no
// documentation of what a field means: all of that belongs with the CURRENT
// shape, in the domain files, and a second copy of it here would be two
// implementations of one rule (L370).
import Foundation
import SwiftData

extension OvationSchemaV1 {

    @Model final class Client {
        var id: UUID = UUID()
        var name: String = ""
        var taxStatus: TaxStatus = TaxStatus.neverRecorded
        var email: String = ""
        var contractEmail: String?
        var sharedAddressAcknowledgedFor: String?
        var sharedAddressAcknowledgedOn: BusinessDate?
        var downbeatClientID: UUID?
        var paymentTermDays: Int?

        @Relationship(deleteRule: .nullify, inverse: \Invoice.client)
        var invoices: [Invoice] = []
        @Relationship(deleteRule: .nullify, inverse: \Payment.client)
        var payments: [Payment] = []
        @Relationship(deleteRule: .nullify, inverse: \ReferralLedgerEntry.client)
        var referralEntries: [ReferralLedgerEntry] = []

        init() {}
    }

    @Model final class Invoice {
        var id: UUID = UUID()
        var number: Int64?
        var kind: InvoiceKind = InvoiceKind.photography
        var client: Client?
        var invoiceDate: BusinessDate?
        var dueDate: BusinessDate?
        var hourlyRate: Money = Money.zero
        var taxRate: TaxRate = TaxRate.newYorkCity
        var discount: Discount?
        var referralCredit: ReferralCredit?
        var sentStatus: SentStatus = SentStatus.notSent
        var closure: InvoiceClosure?
        /// REMOVED IN VERSION 2 (ovation#382). Stored, never read or written by
        /// anything in the app, and it collided by name with the standing note
        /// Settings puts at the foot of every invoice (ovation#319). Dan's
        /// decision, 2026-09-19: there is no per invoice note. It is here because
        /// version 1 had it, and that is the whole job of this file.
        var noteToClient: String?
        var bookingKey: String?
        var importKey: String?

        @Relationship(deleteRule: .cascade, inverse: \Shoot.invoice)
        var shoots: [Shoot] = []
        @Relationship(deleteRule: .cascade, inverse: \LineItem.invoice)
        var lineItems: [LineItem] = []
        @Relationship(deleteRule: .nullify, inverse: \PaymentAllocation.invoice)
        var allocations: [PaymentAllocation] = []
        @Relationship(deleteRule: .cascade, inverse: \Refund.invoice)
        var refunds: [Refund] = []

        init() {}
    }

    @Model final class Shoot {
        var id: UUID = UUID()
        var name: String = ""
        var when: ShootWhen?
        var venue: String?
        var bookingKey: String?
        var sortIndex: Int = 0
        var invoice: Invoice?

        init() {}
    }

    @Model final class LineItem {
        var id: UUID = UUID()
        var sortIndex: Int = 0
        var summary: String = ""
        var hours: Hours?
        var unitAmount: Money = Money.zero
        var serviceType: ServiceType?
        var shoot: Shoot?
        var invoice: Invoice?

        init() {}
    }

    @Model final class ServiceType {
        var id: UUID = UUID()
        var name: String = ""
        var role: ServiceRole = ServiceRole.ordinary
        var defaultUnitAmount: Money?
        var retiredOn: BusinessDate?

        init() {}
    }

    @Model final class Payment {
        var id: UUID = UUID()
        var client: Client?
        var amount: Money = Money.zero
        var receivedOn: BusinessDate = BusinessDate(storedInstant: .distantPast, storedDayKey: "")
        var method: PaymentMethod = PaymentMethod.zelle
        var reference: String?

        @Relationship(deleteRule: .cascade, inverse: \PaymentAllocation.payment)
        var allocations: [PaymentAllocation] = []
        @Relationship(deleteRule: .nullify, inverse: \Refund.payment)
        var refunds: [Refund] = []

        init() {}
    }

    @Model final class PaymentAllocation {
        var id: UUID = UUID()
        var payment: Payment?
        var invoice: Invoice?
        var amount: Money = Money.zero
        var allocatedOn: BusinessDate = BusinessDate(storedInstant: .distantPast, storedDayKey: "")
        var releasedOn: BusinessDate?

        init() {}
    }

    @Model final class Refund {
        var id: UUID = UUID()
        var invoice: Invoice?
        var payment: Payment?
        var amount: Money = Money.zero
        var refundedOn: BusinessDate = BusinessDate(storedInstant: .distantPast, storedDayKey: "")
        var method: PaymentMethod?
        var note: String?

        init() {}
    }

    @Model final class Expense {
        var id: UUID = UUID()
        var amount: Money = Money.zero
        var incurredOn: BusinessDate = BusinessDate(storedInstant: .distantPast, storedDayKey: "")
        var vendor: String?
        var category: ExpenseCategory?
        var assetJudgement: AssetJudgement = AssetJudgement.notDecided
        var bothAreRealAcknowledgedOn: BusinessDate?
        var receipt: ReceiptEvidence = ReceiptEvidence.noneRecorded
        var note: String?
        var gmailMessageKey: String?
        var attachmentPartIndex: Int?
        var gmailAttachmentID: String?
        var importKey: String?

        init() {}
    }

    @Model final class ReferralLedgerEntry {
        var id: UUID = UUID()
        var client: Client?
        var hours: Hours = Hours.zero
        var occurredOn: BusinessDate = BusinessDate(storedInstant: .distantPast, storedDayKey: "")
        var earnedFromBookingKey: String?
        var spentOnInvoiceID: UUID?
        var note: String?

        init() {}
    }
}
