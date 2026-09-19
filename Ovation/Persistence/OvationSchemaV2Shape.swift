// ovation#43 and ovation#134. WHAT VERSION 2 HELD, frozen, so version 3 has
// something to migrate FROM.
//
// THIS FILE IS HISTORY AND IS NEVER EDITED TO MATCH THE APP, for the reason
// `OvationSchemaV1Shape.swift` sets out in full: adding a field the app grew, or
// deleting one it dropped, makes this version describe the current one and leaves
// the stage between them with nothing to carry (L70). The only legitimate change
// is a correction where it fails to describe what was actually on disk.
//
// WHY ALL TEN AGAIN. Version 1's copy records the measurement: SwiftData keys an
// entity by its CLASS NAME, so a version that reuses another version's type for
// anything it is related to dies casting the model. Every one of Ovation's ten
// models sits in one relationship graph, so a version costs a copy of all ten.
// That is the price the schema file names, paid here for the second time.
//
// THE ONE DIFFERENCE FROM VERSION 1 is the absence of `Invoice.noteToClient`,
// which ovation#382 removed. The one difference from version 3 is the absence of
// `Shoot.shotFrom` and `Shoot.shotUntil`, which ovation#43 added.
//
// THE VALUE TYPES ARE NOT FROZEN WITH IT, and that is the same stated limitation
// version 1's copy carries: `Money`, `BusinessDate`, `ShootWhen`, `Discount` and
// the vocabularies are global Codable types shared by every version, so a change
// to one of THEM changes what this file describes. `ClockTime` is new in version
// 3 and appears on no class here, which is what makes version 3's change purely
// additive.
//
// NOTHING HERE HAS BEHAVIOUR, for the reason version 1's copy gives.
import Foundation
import SwiftData

extension OvationSchemaV2 {

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
