// ovation#510. WHAT VERSION 3 HELD, frozen, so version 4 has something to
// migrate FROM.
//
// THIS FILE IS HISTORY AND IS NEVER EDITED TO MATCH THE APP, for the reason
// `OvationSchemaV1Shape.swift` sets out in full: adding a field the app grew, or
// deleting one it dropped, makes this version describe the current one and leaves
// the stage between them with nothing to carry (L70, L1010). The only legitimate
// change is a correction where it fails to describe what was actually on disk.
//
// VERSION 3 WAS WRITTEN TO DISK, by the installed app, so unlike version 2 its
// shape is not only a ratchet: `SchemaFingerprintTests` pins what it writes, and
// this copy passes that pin, which is the proof it describes the stores already
// out there rather than a guess at them.
//
// WHY ALL TEN AGAIN, for the reason version 1's copy records: SwiftData keys an
// entity by its CLASS NAME, so a version that reuses another version's type for
// anything it is related to dies casting the model, and every one of Ovation's
// ten models sits in one relationship graph.
//
// THE ONE DIFFERENCE FROM VERSION 2 is `Shoot.shotFrom` and `Shoot.shotUntil`,
// which ovation#43 added, and `Invoice.sentStatus` holding `SentStatus` with the
// case ovation#460 added. The one difference from version 4 is the absence of
// `Invoice.createdOn`, which ovation#510 added.
//
// THE VALUE TYPES ARE NOT FROZEN WITH IT, the same stated limitation both older
// copies carry: `Money`, `BusinessDate`, `ClockTime`, `SentStatus` and the
// vocabularies are shared by every version, so a change to one of THEM changes
// what this file describes, and the fingerprint pin is what would say so.
//
// NOTHING HERE HAS BEHAVIOUR, for the reason version 1's copy gives.
import Foundation
import SwiftData

extension OvationSchemaV3 {

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
        var shotFrom: ClockTime?
        var shotUntil: ClockTime?

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
        var clearedOn: BusinessDate?
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
