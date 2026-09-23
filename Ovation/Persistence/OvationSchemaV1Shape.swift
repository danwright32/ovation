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
// THE VALUE TYPES ARE MOSTLY NOT FROZEN WITH IT, and this paragraph used to call
// that a stated limitation and predict what would happen. It happened (ovation#502).
//
// `SentStatus` GAINED A CASE WITH AN ASSOCIATED VALUE on 2026-09-21 (ovation#464),
// and because this file named the LIVE type, what version 1 claimed to have held
// changed two days after the fact with nobody editing this file at all. That
// commit recorded the opposite in as many words, "adding a CASE changes no
// attribute SwiftData can see", and it is measurably false: the four fields of
// `SendAttempt` are flattened into `ZINVOICE` as `ZDESTINATION`, `ZWASREDIRECTED`,
// `ZRENDERSHA256` and `ZSTARTEDAT`. Both stores on Dan's Mac then matched no
// declared version and the app could not open the store it had written.
//
// SO THE ONE TYPE THAT MOVED IS FROZEN HERE, below, and the rest are still shared.
// That is a deliberate choice rather than laziness: `SchemaFingerprintTests` now
// fails the moment ANY frozen version's fingerprint moves, so a shared type that
// changes is caught on the next test run instead of at somebody's install. Nine
// speculative hand copies would each be a fresh chance to transcribe one wrongly,
// which is exactly how `clearedOn` went missing below. Freeze a type when the
// guard says it moved, and not before.
//
// NOTHING HERE HAS BEHAVIOUR. No computed properties, no methods, no
// documentation of what a field means: all of that belongs with the CURRENT
// shape, in the domain files, and a second copy of it here would be two
// implementations of one rule (L370).
import Foundation
import SwiftData

/// ovation#502. `SentStatus` AS VERSIONS 1 AND 2 STORED IT, before ovation#464
/// added `attempting(SendAttempt)` on 2026-09-21.
///
/// IT IS A SEPARATE TYPE SO THE LIVE ONE CAN MOVE AGAIN. Naming the live type
/// here is what let version 1 change underneath itself; a frozen version has to
/// describe what was on disk whatever the app does next.
///
/// ONE COPY SERVES BOTH FROZEN VERSIONS, unlike the ten model CLASSES above,
/// which each need their own because SwiftData keys an entity by its class name.
/// A `Codable` value type is keyed by nothing: its stored shape comes from its
/// case names and associated values, so versions 1 and 2, which held the identical
/// shape, can share one description of it without the reuse failure measured on
/// 2026-09-19.
///
/// THE CASES AND THEIR LABELS ARE THE STORED FORM and may not be tidied. The
/// synthesized `Codable` keys off these names, so renaming a case or a label
/// rewrites what every stored row must say to decode.
enum SentStatusBeforeAttempting: Equatable, Hashable, Codable, Sendable {
    case notSent
    case sent(route: SentRoute, at: Date)
    case couldNotDetermine(checkedAt: Date)
}


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
        var sentStatus: SentStatusBeforeAttempting = SentStatusBeforeAttempting.notSent
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
        /// ovation#502. OMITTED WHEN THIS FILE WAS WRITTEN BY HAND on 2026-09-19,
        /// and version 1 did hold it: the stores written on 2026-09-12 carry its
        /// two columns. Restored rather than left out, because a frozen version
        /// that drops a field the store has makes the stage between versions carry
        /// nothing for it, and a later version re-adding it would arrive empty.
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
