// ovation#60. The invoice, the shoots it covers, the lines it charges, and the
// arithmetic that decides what a client is asked to pay.
//
// NO @Attribute(.unique) ANYWHERE, INCLUDING ON id. PRD 42c: the attribute does
// not prevent a duplicate, it chooses which failure the duplicate becomes, and
// with it a colliding id destroys the row that was there. Without it the
// collision leaves two rows, which the export reconciliation can find and a
// person can repair. `SwiftDataBehaviourTests` holds both halves against each
// other so the choice is defended rather than inherited.
//
// EXTERNAL IDENTIFIERS ARE ORDINARY LOOKUP FIELDS AND NEVER THE IDENTITY. A
// booking id or a QuickBooks row key is stored so a re-run can FIND an existing
// invoice through Ovation's own lookup, never land on it by construction. A
// lookup needing exactly one row refuses on more than one rather than taking the
// first (L521).
//
// THE RATES ARE FROZEN AT CREATION rather than read from settings when the
// document is rendered, so a settings change can never silently rewrite an
// invoice that has already been sent. PRD 9.5, whether tax applies to rush and
// preview charges, is still open, which is exactly why the rate AND its base
// travel with the invoice.
import Foundation
import SwiftData

/// How an invoice ended, where it ended at all.
///
/// ONE VALUE RATHER THAN TWO OPTIONAL DATES. Cancelled and dismissed are
/// mutually exclusive and each carries its own date and reason, so a pair of
/// nullable fields would allow a row that is both, and would let a reader answer
/// "was it dismissed" by testing a field that means something else (L163).
enum InvoiceClosure: Equatable, Hashable, Codable, Sendable {
    /// A sent invoice withdrawn. PRD 5.13: if it was issued in a filed tax year
    /// this is a refusal to be raised with the accountant, not a quiet edit.
    case cancelled(on: BusinessDate, reason: String)
    /// A draft Dan decided never to bill. PRD 5.1b: dismissing keeps the row and
    /// records the decision, which is what lets Ovation tell a comped shoot from
    /// an invoice he forgot.
    case dismissed(on: BusinessDate, reason: String)

    var closedOn: BusinessDate {
        switch self {
        case .cancelled(let on, _), .dismissed(let on, _): return on
        }
    }
}

/// Something wrong enough that the invoice must not go out as it stands.
///
/// ONE VOCABULARY, AND EVERY REASON IS IN IT. A surface asking "can this be sent"
/// must get one answer carrying every reason, because a control that asks two
/// independent questions can be enabled by whichever it asked last, and two
/// vocabularies for one decision drift (L118, L53). That is why the footer's two
/// reasons are members here rather than a second enum, and why the unpriced draft
/// (PRD 3c, ovation#117) joined this set rather than standing beside it.
enum InvoiceRefusal: String, CaseIterable, Codable, Hashable, Sendable {
    /// PRD 5.4a. Reported rather than clamped, because clamping destroys the
    /// evidence that somebody typed the wrong number (L340).
    case discountExceedsSubtotal

    /// PRD 5, corrected 2026-09-07 (ovation#128). A missing status is not the
    /// same as not exempt: the tax IS charged and the send is REFUSED until the
    /// status is answered.
    ///
    /// IT WAS A WARNING UNTIL THAT DATE, and the difference is the whole of
    /// ovation#128. Dan chose the refusal over stating the warning and letting
    /// the invoice go, and over asking at the moment of sending (round 7 of
    /// ovation#111). A guard written from the old wording would have shown the
    /// warning and sent anyway, while passing a reading of the requirement.
    case taxStatusNeverRecorded

    /// ovation#319, PRD 9. The foot of the page does not say how to pay.
    ///
    /// THE TWO BELOW ARE NOT PROPERTIES OF AN INVOICE. They come from Settings and
    /// are identical for every invoice in the app, so `Invoice.refusals` never
    /// produces them: `InvoiceFooter.refusals` does, and `ReviewGate` is what puts
    /// the two sets together. They are members of THIS vocabulary rather than a
    /// second one because a surface asking "can this be sent" must get ONE answer
    /// with every reason in it (L118, L53), and so the sentence table stays total
    /// over a single enum.
    case paymentInstructionsNotSet

    /// ovation#319, PRD 9. The foot of the page does not say how to reach Dan.
    case contactDetailsNotSet

    /// PRD 5.4c, ovation#136, Dan's decision 2026-09-19. A referral credit larger
    /// than the charges makes the total negative, and such an invoice may not be
    /// sent: it is a document titled Invoice, with a due date, asking a client for
    /// a negative amount, and it reaches the year end export as negative income on
    /// an accrual return. Dan chose the refusal over sending it with a warning and
    /// over producing a credit note instead.
    ///
    /// THE BOUNDARY IS BELOW ZERO AND NOT AT IT. PRD 5.1b makes a zero total an
    /// ordinary invoice, occasionally wanted for a comped shoot, and "no guard may
    /// refuse" one, so this asks `total < .zero` rather than `<= .zero`.
    ///
    /// IT ASKS THE TOTAL, NOT THE SUBTOTAL, and that is what makes it right about
    /// a percentage discount over a negative subtotal: a hundred percent of a
    /// credit driven subtotal brings the total back to exactly zero, which is a
    /// legitimate invoice rather than this refusal.
    case totalBelowZero

    /// PRD 3c, ovation#117. A shoot on this invoice has not been given both of
    /// its real times, so the invoice has no hours and no amount yet.
    ///
    /// THREE MEMBERS RATHER THAN ONE, and they are the design's own
    /// (`docs/design/rules/waiting.js`). A single "not priced yet" would make the
    /// screen ask for the times again over a draft already carrying its start,
    /// which is the defect that rule was written against (PRD 51b).
    ///
    /// AN UNPRICED DRAFT IS NOT A ZERO INVOICE. PRD 1b makes a zero total ordinary
    /// and says no guard may refuse one, so the two would be indistinguishable on
    /// every surface that shows an amount while needing opposite actions, which is
    /// exactly what L11 exists for. The list draws `no price` for this one and
    /// `comped` for that one, settled with Dan on 2026-09-09.
    case shootTimesNotGiven
    case shootEndTimeNotGiven
    case shootStartTimeNotGiven

    /// PRD 3b and 51c, ovation#43. A shoot on this invoice spans longer than
    /// `ShootDuration.cap`, so it prices nothing and the invoice may not go out.
    ///
    /// REFUSED RATHER THAN CLAMPED, which is PRD 3b's own wording: a span that long
    /// is a typo rather than a shoot, and rounding it into a sendable number
    /// destroys the evidence that somebody typed the wrong time (L340).
    ///
    /// IT IS NOT THE SAME AS NO TIMES AT ALL, and the difference is why it has its
    /// own member. Dan, 2026-09-08, on the design's own rule: both times being
    /// present is a different fact from no times at all, so asking for the times
    /// again here would ask for something already given (L111). The state where a
    /// time has NOT been typed is ovation#117, and it joins this vocabulary rather
    /// than standing beside it.
    case durationLongerThanAShoot

}

extension OvationSchemaV3 {
    @Model
    final class Invoice {
        /// Ovation's own identity, minted fresh and never derived from anything
        /// outside the app.
        var id: UUID = UUID()

        /// Allocated from the one continuous sequence when the invoice is issued.
        /// NIL WHILE IT IS A DRAFT, which is what lets Dan combine two drafts without
        /// burning a number (PRD 5.1a). The allocator itself is ovation#37.
        var number: Int64?

        /// What the money is for. PRD 5.2a.
        var kind: InvoiceKind = InvoiceKind.photography

        var client: Client?

        /// The date that decides the tax year, stamped at write. Nil only while a
        /// draft has no date at all, which is a real state the invoice list has to
        /// have a group for (ovation#49).
        var invoiceDate: BusinessDate?

        /// PRD 5.7, fourteen days after the invoice date, overridable per client and
        /// per invoice, which is why it is stored rather than derived at read.
        var dueDate: BusinessDate?

        /// Frozen at creation. See the header.
        var hourlyRate: Money = Money.zero
        var taxRate: TaxRate = TaxRate.newYorkCity

        /// PRD 5.4a. Below the subtotal, never a line.
        var discount: Discount?

        /// PRD 5.8 as corrected by round 6 of ovation#111. INSIDE the subtotal, and
        /// also never a line (ovation#126).
        var referralCredit: ReferralCredit?

        /// PRD 5.10a. Only ever observed.
        var sentStatus: SentStatus = SentStatus.notSent

        var closure: InvoiceClosure?

        // THERE IS NO PER INVOICE NOTE (ovation#382, Dan's decision 2026-09-19).
        // `noteToClient` was stored here, read and written by nothing, and it
        // collided by name with the standing note ovation#319 put in Settings that
        // appears at the foot of every invoice. Two differently scoped things with
        // one name is read as one thing (L263), and stored data needs a reader
        // (L46). Removing it is what made version 2 exist; version 1 still carries
        // it, in OvationSchemaV1Shape.swift, because version 1 had it.

        /// The booking this was drafted from, for LOOKUP only. See the header.
        var bookingKey: String?

        /// The QuickBooks row this was imported from, for lookup only. ovation#68
        /// owns what goes in it.
        var importKey: String?

        @Relationship(deleteRule: .cascade, inverse: \Shoot.invoice)
        var shoots: [Shoot] = []

        @Relationship(deleteRule: .cascade, inverse: \LineItem.invoice)
        var lineItems: [LineItem] = []

        /// NULLIFY, NOT CASCADE, and the difference is PRD 5.14d. An allocation is a
        /// statement about money that actually arrived, so it outlives the invoice it
        /// was pointed at; cancelling RELEASES it rather than destroying it.
        @Relationship(deleteRule: .nullify, inverse: \PaymentAllocation.invoice)
        var allocations: [PaymentAllocation] = []

        @Relationship(deleteRule: .cascade, inverse: \Refund.invoice)
        var refunds: [Refund] = []

        init(
            client: Client?,
            kind: InvoiceKind,
            invoiceDate: BusinessDate?,
            hourlyRate: Money,
            taxRate: TaxRate
        ) {
            self.client = client
            self.kind = kind
            self.invoiceDate = invoiceDate
            self.hourlyRate = hourlyRate
            self.taxRate = taxRate
        }

        // MARK: the order things are read in

        /// A collection read from a store carries no order unless the read declares
        /// one (L343), and a relationship is a collection. Both accessors below sort
        /// explicitly rather than rendering whatever came back.
        ///
        /// MEASURED, NOT ASSUMED. Removing the sort here and re-running returns three
        /// lines inserted first, second, third as `["third", "second", "first"]`, so
        /// an invoice rendered straight from the relationship would print its charges
        /// backwards. The rule is not theoretical in this store.
        var orderedLineItems: [LineItem] { lineItems.sorted { $0.sortIndex < $1.sortIndex } }

        var orderedShoots: [Shoot] { shoots.sorted { $0.sortIndex < $1.sortIndex } }

        func add(_ item: LineItem) {
            item.sortIndex = (lineItems.map(\.sortIndex).max() ?? -1) + 1
            lineItems.append(item)
        }

        /// Take back one shoot's typed times, and the hours stored beside them.
        ///
        /// DAN'S DECISION, 2026-09-19 (ovation#431), put to him against keeping the
        /// last price: clearing a time puts the invoice back to waiting on the
        /// times, exactly as a fresh draft is, and nothing may be sent until they
        /// are typed again.
        ///
        /// WHY THE HOURS GO IN THE SAME WRITE. `LineItem.billedHours` reads the
        /// shoot's times where they exist and the line's own stored hours where they
        /// do not, and that second arm is right for the population it was written
        /// for: a QuickBooks row imported under ovation#68 carries hours and was
        /// never timed, as the design record's own PDF fixtures are. A shoot whose
        /// times have been CLEARED is indistinguishable from one of those in the
        /// data, so the reader cannot tell them apart and the WRITER has to. Left
        /// alone, the invoice would go on pricing from a figure that appears on no
        /// screen (L46, L544).
        ///
        /// ADDRESSED TO THE SHOOT IT WAS ASKED ABOUT, by identity, because PRD 5.1a
        /// puts more than one shoot on an invoice and an action carrying out a
        /// decision must reach only the records that decision was made over (L166).
        func clearTimes(of shoot: Shoot) {
            shoot.shotFrom = nil
            shoot.shotUntil = nil
            for line in lineItems where line.shoot?.id == shoot.id {
                line.hours = nil
            }
        }

        func add(_ shoot: Shoot) {
            shoot.sortIndex = (shoots.map(\.sortIndex).max() ?? -1) + 1
            shoots.append(shoot)
        }

        // MARK: what it comes to

        /// What the referral credit takes off. Zero where there is none.
        var referralCreditAmount: Money { referralCredit?.amount ?? .zero }

        /// The lines, LESS the referral credit, because the credit sits inside the
        /// subtotal and the discount applies to what is left (PRD 5.4b).
        ///
        /// THE CREDIT IS NOT AMONG THE LINES (ovation#126). It used to be, as a
        /// negative one, and round 6 of ovation#111 took it out. The conclusion 5.4b
        /// draws is unchanged and its reason is not, so the subtotal composes two
        /// things here rather than summing one.
        var subtotal: Money { Money.sum(of: lineItems.map(\.amount)) - referralCreditAmount }

        /// What the discount takes off. Zero where there is none.
        var discountAmount: Money { discount?.amount(on: subtotal) ?? .zero }

        /// What the tax is charged on. PRD 5.4a: the subtotal AFTER the discount.
        var taxableAmount: Money { subtotal - discountAmount }

        /// The tax, or nothing at all for an exempt client.
        ///
        /// IT READS THE CLIENT'S STATUS AT RENDER TIME, and that is a decision
        /// rather than the absence of one (PRD 5a1, ovation#122). Dan's own history
        /// has three clients taxed on some invoices and untaxed on others after
        /// sales tax started in 2022, and a fourth with a taxed and an untaxed line
        /// on the same day, which reads as a status that CHANGES. Put to him on
        /// 2026-09-19 with the measurement, he answered that the tax was applied by
        /// hand and sometimes missed, so the history contains mistakes and the
        /// status stays a fact about the client. Every other rate on this invoice is
        /// frozen at creation; this one deliberately is not, and 5a1 records what
        /// that costs if a client ever does become exempt.
        var tax: Money {
            guard client?.taxStatus.isTaxed ?? true else { return .zero }
            return taxRate.tax(on: taxableAmount)
        }

        var total: Money { taxableAmount + tax }

        // MARK: what has been paid against it

        /// CALCULATED, NEVER TYPED (PRD 5.14). It reads through the allocations that
        /// still stand, so a released one stops counting the moment it is released
        /// and nothing has to remember to undo a flag.
        var amountPaid: Money {
            Money.sum(of: allocations.filter { $0.releasedOn == nil }.map(\.amount))
        }

        var amountOutstanding: Money { total - amountPaid }

        /// The day the money that settled this invoice arrived, where it is
        /// settled by money at all.
        ///
        /// THE LATEST STANDING ALLOCATION'S PAYMENT, because an invoice can be
        /// settled by more than one, and what a receipt states is the day it
        /// became paid rather than the day the first instalment turned up
        /// (ovation#326). Released allocations are excluded for the same reason
        /// `amountPaid` excludes them: they are money that no longer stands
        /// against this invoice.
        ///
        /// NIL WHERE NOTHING WAS APPLIED, and nil is not a date to be defaulted:
        /// a receipt with no payment date is a receipt that should not have been
        /// drawn, and `InvoiceDocument` refuses rather than printing one (L67).
        var settledOn: BusinessDate? {
            allocations
                .filter { $0.releasedOn == nil }
                .compactMap { $0.payment?.receivedOn }
                .max { $0.dayKey < $1.dayKey }
        }

        /// Releases every allocation that still stands against this invoice.
        ///
        /// RELEASED, NEVER DELETED (PRD 5.14d). An allocation is a statement about
        /// money that actually arrived, so it outlives the invoice it was pointed
        /// at, and the money returns to the client's unallocated balance rather
        /// than disappearing.
        ///
        /// IT IS HERE RATHER THAN IN EACH WRITER because two writers need it,
        /// `PaymentAllocator` and `InvoiceCloser`, and each one saves in its own
        /// context. Sharing the DATA while copying the code that applies it is not
        /// consolidation: the shared field reads as the single source of truth and
        /// nobody then asks whether the logic beside it was duplicated (L370).
        func releaseActiveAllocations(on day: BusinessDate) {
            for allocation in allocations where allocation.releasedOn == nil {
                allocation.releasedOn = day
            }
        }

        /// The shoots this invoice still has NO HOURS for.
        ///
        /// IT ASKS WHAT THE INVOICE CHARGES, NOT WHAT THE SHOOT RECORDS, and that
        /// distinction is the whole of it. PRD 3c's unpriced draft is one that "has
        /// no hours and no amount"; a shoot with no typed times whose line already
        /// carries hours is not that. Asking the shoot alone would refuse every
        /// QuickBooks row ovation#68 imports, since those carry hours and were never
        /// timed, and every fixture in the design record's own PDF, which is how the
        /// narrower reading was found rather than reasoned out.
        private var shootsWithNoHours: [Shoot] {
            orderedShoots.filter { shoot in
                !lineItems.contains { $0.shoot?.id == shoot.id && $0.billedHours != nil }
            }
        }

        /// PRD 3c. It has no duration yet, so it has no hours and no amount.
        ///
        /// A NAME RATHER THAN A NIL AT EACH SURFACE (ovation#117). Every screen that
        /// shows an amount has to tell this from a comped invoice that really does
        /// come to nothing, and a surface inferring it from a zero would draw the two
        /// the same way while they need opposite actions. The list asks this and
        /// draws `no price`; its action word is `Add hours` (PRD 46f).
        /// ASKED OF THE REFUSALS, not of the shoots again. A surface reading this
        /// and a send control reading `refusals` must never disagree about one
        /// invoice, and two predicates over the same facts is how they come to
        /// (L370, L16). A shoot that IS timed and simply has no line yet is not
        /// waiting on anything a person can give it, so it is not this state.
        var isUnpriced: Bool {
            !refusals.isDisjoint(with: [.shootTimesNotGiven, .shootEndTimeNotGiven,
                                        .shootStartTimeNotGiven])
        }

        /// Where this invoice stands on money alone.
        ///
        /// IT SAYS NOTHING ABOUT SENDING OR CANCELLING, which are different facts on
        /// different fields. The invoice list's groups (ovation#49) and the export's
        /// payment state column (ovation#61) compose this with `sentStatus` and
        /// `closure`; folding them together here would give one field two meanings
        /// and make a cancelled unpaid invoice indistinguishable from an open one.
        ///
        /// CLEARED IS DELIBERATELY NOT ONE OF THESE. PRD 5.15 puts cleared on the
        /// payment, so one check clears once however many invoices it settled, and an
        /// invoice can never be cleared on its own.
        var paymentState: InvoicePaymentState {
            if amountPaid <= .zero && total > .zero { return .unpaid }
            if amountPaid >= total { return .paid }
            return .partlyPaid
        }

        // MARK: what it says about itself

        /// Every reason THIS INVOICE must not go out as it stands, in one place.
        ///
        /// ONE ANSWER RATHER THAN TWO LISTS. A send control asking two independent
        /// questions is one that can be enabled by whichever it asks last, and
        /// two vocabularies for one decision drift (L53, L118). ovation#117's
        /// unpriced draft joins this set rather than standing beside it.
        ///
        /// IT IS THE NARROW QUESTION, AND THERE IS NO LONGER A BOOLEAN OVER IT
        /// (ovation#384). Since ovation#319 two of the reasons an invoice may not
        /// go out live on the footer, in Settings, and an invoice cannot read a
        /// setting. `ReviewGate.refusal(for:footer:)` is the send gate because it
        /// takes both. A `maySend` property used to sit here answering the narrow
        /// question under the whole question's name, with a comment saying so, and
        /// a comment is enforced by nothing while reading as binding (L407): the
        /// token is now refused by `scripts/check-forbidden-constructs.sh`, so the
        /// name cannot come back. Asking this set directly is also the better
        /// assertion, because it names WHICH refusal rather than that there was
        /// one (L140).
        var refusals: Set<InvoiceRefusal> {
            var found: Set<InvoiceRefusal> = []
            // THE DISCOUNT IS ONLY BLAMED WHERE IT IS THE CAUSE (ovation#136). Every
            // positive dollar discount is larger than a NEGATIVE subtotal, so without
            // this condition the discount refusal fires on every credit driven
            // invoice that happens to carry one, and it sends Dan to reduce a number
            // whose reduction changes nothing (L111). Where the subtotal has not gone
            // below zero on its own, an oversized discount genuinely is what takes
            // the invoice under, and it keeps its own name.
            if subtotal >= .zero, discount?.exceeds(subtotal) == true {
                found.insert(.discountExceedsSubtotal)
            }
            if client?.taxStatus == .neverRecorded { found.insert(.taxStatusNeverRecorded) }
            // PRD 5.4c. Below zero, never at it: a zero total is the comped invoice
            // PRD 5.1b says no guard may refuse.
            if total < .zero { found.insert(.totalBelowZero) }
            // PRD 3b. ASKED OF EVERY SHOOT, because PRD 5.1a puts more than one on
            // an invoice and a rule reading only the first would pass an invoice
            // whose second shoot is the mistyped one.
            if shoots.contains(where: \.isLongerThanAShoot) {
                found.insert(.durationLongerThanAShoot)
            }
            // PRD 3c. EVERY SHOOT WITH NO HOURS IS ASKED, and each names what IT is
            // waiting on, so an invoice covering two shoots can be waiting on two
            // different things at once. ReviewGate's order decides which one a
            // control says.
            for shoot in shootsWithNoHours {
                switch shoot.timesMissing {
                case .both: found.insert(.shootTimesNotGiven)
                case .end: found.insert(.shootEndTimeNotGiven)
                case .start: found.insert(.shootStartTimeNotGiven)
                case nil: break
                }
            }
            return found
        }
    }
}

// THE NAME THE REST OF THE APP USES (ovation#134). The type belongs to a
// schema VERSION, because a version has to be able to describe a shape that
// is no longer current. Everything outside the store speaks about the shape
// in force, so it says the bare name and this is what points that name at the
// version in force. When a newer version exists, this line moves to it and
// every call site is already correct.
typealias Invoice = OvationSchemaV3.Invoice
