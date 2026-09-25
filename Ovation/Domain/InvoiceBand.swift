// ovation#49, PRD section 6, 46, 46a, 46d, 46f, 46g. The one list, and the proof
// that it holds everything.
//
// THE LIST IS THE ONLY WAY TO REACH AN INVOICE, so a state matching no band is not
// merely awkward, it is invisible, and an invisible unbilled shoot stays unbilled
// (L45). That is the whole reason this file is shaped the way it is.
//
// EACH BAND IS ITS OWN PREDICATE, and the classifier is checked AGAINST them
// rather than being the only statement of what a band means. A first-match chain
// is a perfectly good implementation and a terrible specification: read as a
// specification it says "whatever the earlier arms did not take", so every band
// after the first is defined by the ones above it and a state nobody thought of
// lands in whichever arm happens to be last. Written as independent predicates the
// partition becomes a property something can actually assert in both directions:
// no state claimed twice, and no state claimed by nothing (L517, L107).
//
// THE BANDS ARE NOT DRAWN (PRD 46). They decide the ORDER and nothing else: a
// heading reading "Send it today" over a row whose action word reads Send labels
// one fact three times. Anyone reading this file for the screen should build the
// grouping and not the headings.
import Foundation

/// Where an invoice sits in the list, top to bottom.
///
/// THE ORDER OF THE CASES IS THE ORDER ON SCREEN, and it is read as such by the
/// list rather than restated beside it (L41). PRD section 6 numbers eight groups;
/// there are ten cases here because 46d put `To place` above all of them and
/// ovation#45's sent triple earns its own band, which is the placement PRD section
/// 6 records as the one still needing one.
enum InvoiceBand: String, CaseIterable, Codable, Hashable, Sendable {

    /// PRD 46d. A client's held money could settle more than one of their open
    /// invoices, so Ovation applies it to none of them and asks.
    ///
    /// IT CUTS ACROSS THE REST AND MOVES ITS ROWS RATHER THAN COPYING THEM, which
    /// is what keeps the partition true with a band that is not a status: an
    /// invoice in here is also a draft or also overdue, and it is drawn once.
    case toPlace

    /// Group 1. Draft, shoot is today. Send it today.
    case draftShootToday

    /// Group 2. Overdue. Chase it.
    case overdue

    /// Group 3. Draft, the shoot has passed, so it should have been sent.
    ///
    /// AND A DRAFT WITH NO SHOOT DATE AT ALL, which PRD section 6 places here
    /// rather than giving it a ninth band, because "should have been sent" is what
    /// needs Dan about it. An invoice can be created from scratch with no booking
    /// behind it, and every band keyed on a shoot date has nowhere to put one.
    case draftNeedsSending

    /// Group 4. Paid by check, not yet cleared. Confirm it cleared.
    case checkNotCleared

    /// ovation#45's third answer, which is the one that needs a person. The match
    /// ran against the mailbox and could not tell whether this went out.
    ///
    /// IT IS NOT FOLDED INTO EITHER NEIGHBOUR. Read as sent it puts money on a tax
    /// return on a guess; read as a draft it hides a shoot that may well have been
    /// billed already (L11, L53).
    case sayWhetherItWasSent

    /// Group 5. Sent, awaiting payment. Waiting on them.
    case sentAwaitingPayment

    /// Group 6. Draft, shoot still ahead. Nothing to do yet.
    case draftShootAhead

    /// Group 7. Paid or cleared.
    case paidOrCleared

    /// Group 8. Cancelled, which is where a refunded invoice is drawn too: a
    /// refund only ever follows a cancellation (PRD section 6).
    case cancelled
}

/// Everything the list needs to know about one invoice, and nothing else.
///
/// A VALUE RATHER THAN THE MODEL, for two reasons that are not style. The state
/// space this has to be proved over is every combination of six independent
/// facts, and building each one as a stored invoice would pay a container per case
/// to assert something no store is involved in. And a banding written against the
/// model would be free to consult anything the model carries, which is how a band
/// quietly starts depending on a field nobody listed here.
struct InvoiceStanding: Equatable, Hashable, Sendable {

    /// How the invoice ended, where it ended at all.
    enum Ending: Equatable, Hashable, Sendable, CaseIterable {
        case cancelled
        /// Dan deleted a draft he was never going to bill (PRD 1b, Dan 2026-09-20).
        /// It leaves the list entirely; the row survives only so the January
        /// reconcile can tell a shoot deliberately not billed from a shoot lost
        /// between Downbeat and here (ovation#36, L258).
        case deleted
    }

    /// What is known about the money against it.
    ///
    /// THE UNCLEARED CHECK IS ITS OWN MEMBER rather than a flag beside `paid`,
    /// because a payment's cleared step belongs to the payment and only a check
    /// has one (PRD 5.15), so "paid" and "paid, not yet cleared" are two answers
    /// to one question and a pair of fields would allow a row that is neither
    /// (L544).
    enum Money: Equatable, Hashable, Sendable, CaseIterable {
        /// Nothing has arrived.
        case nothing
        /// Some of it has, and not all. PRD section 6: this is NOT a band. It sits
        /// wherever its dates already put it and the ROW shows the outstanding
        /// balance rather than the invoice total.
        case some
        /// All of it, and everything that needed to clear has.
        case allOfItCleared
        /// All of it, and a check against it has not cleared yet.
        case allOfItAwaitingAClearedCheck
    }

    var ending: Ending?
    var sent: SentStatus
    /// The shoot's day number, and nil for an invoice created from scratch with no
    /// booking behind it. That nil is the state PRD section 6 records as having no
    /// band at all before ovation#49.
    var shootDay: Int?
    /// The day payment is due, and nil where nothing has been issued to be due.
    var dueDay: Int?
    var money: Money
    /// PRD 46d, decided across the client's whole set of open invoices rather than
    /// from this one, which is why it arrives as an answer rather than being read
    /// off the invoice here.
    var couldSettleMoreThanOne: Bool

    /// A date is STORED on this invoice and would not read back (L50).
    ///
    /// IT IS NOT THE SAME AS HAVING NO DATE, and separating them is the whole
    /// reason this exists. A stored day key is PARSED to be compared, so the parse
    /// can fail; folded into the same nil as "no date given", a due date that will
    /// not read lands in "waiting on them", which is the permissive side. An
    /// invoice months past its terms would then sit among the ones not due yet,
    /// with nothing on any screen saying its date could not be read.
    ///
    /// IT CANNOT HAPPEN THROUGH THE APP, and that is why it must fail safe rather
    /// than be validated away. Every `BusinessDate` Ovation writes comes from
    /// `.stamping(_:)`, which always produces a readable key, so reaching this
    /// means the store was damaged or edited by hand. That is exactly the case
    /// where a silent permissive default is worst.
    var datesCouldNotBeRead: Bool

    init(ending: Ending? = nil, sent: SentStatus = .notSent, shootDay: Int? = nil,
         dueDay: Int? = nil, money: Money = .nothing,
         couldSettleMoreThanOne: Bool = false, datesCouldNotBeRead: Bool = false) {
        self.ending = ending
        self.sent = sent
        self.shootDay = shootDay
        self.dueDay = dueDay
        self.money = money
        self.couldSettleMoreThanOne = couldSettleMoreThanOne
        self.datesCouldNotBeRead = datesCouldNotBeRead
    }

    /// Whether this invoice is drawn in the list at all.
    ///
    /// DELETED IS THE ONLY WAY OUT, and it is stated here once so that "absent from
    /// the list" has exactly one cause. A band that returned nothing for a state it
    /// could not place would make a defect and a deliberate deletion look alike on
    /// the one screen where an invoice can be reached (L622).
    var isDrawn: Bool { ending != .deleted }

    /// Whether the invoice is still waiting on money.
    var isOpen: Bool {
        ending == nil && money != .allOfItCleared
    }

    /// Whether this is one of the open invoices a client's held money could
    /// settle, which is what PRD 14h and 14j count: exactly one and Ovation applies
    /// it, more than one and it applies it to none and asks on each.
    ///
    /// A DRAFT IS ONE (Dan, 2026-09-23, ovation#453): "drafts COUNT as open
    /// invoices for PRD 14j ... each (draft or sent) offers `Use it here`; their
    /// drafts join the held money band." Before that only an issued invoice was
    /// counted, which had been read off the design record's Cedar Hill fixture
    /// rather than decided.
    ///
    /// THE TWO UNSETTLED SENDS ARE NOT, because the decision names drafts and sent
    /// invoices and they are neither. Each already carries its own question
    /// (ovation#45, ovation#460), and sweeping it into this one would take that
    /// question off the list. They keep what they had, which was not counted.
    ///
    /// ONE PREDICATE FOR BOTH HALVES. The list's band reads it now, and applying
    /// the money on the invoice (ovation#185) must read it too, or the invoice and
    /// the list will disagree about how many are open (L16, L370).
    var isOpenForHeldMoney: Bool {
        switch sent {
        case .notSent, .sent: return isOpen
        case .couldNotDetermine, .attempting: return false
        }
    }
}

extension InvoiceBand {

    /// Whether this band claims that invoice, written as a standalone description
    /// of the band rather than as "what the arms above me did not take".
    ///
    /// READ THESE AS A SET, NOT IN ORDER. Nothing here may say "and not one of the
    /// others": the whole value of writing them separately is that the partition is
    /// then a fact something can check rather than a consequence of the order they
    /// happen to be asked in (L70).
    func claims(_ it: InvoiceStanding) -> Bool {
        guard it.isDrawn else { return false }
        switch self {
        case .cancelled:
            return it.ending == .cancelled

        // 46d MOVES ITS ROWS. Every other band below therefore has to exclude it,
        // and that exclusion is the one piece of cross-band reasoning in this file.
        // It is written into each band rather than left to the classifier's order
        // because a band that cuts across the rest is exactly the case where an
        // order-defined specification stops being readable (PRD 46a says so in its
        // own words: the rule now has to be read over a list where one group cuts
        // across the rest).
        case .toPlace:
            return it.ending == nil && it.couldSettleMoreThanOne

        case .sayWhetherItWasSent:
            return it.isLive && it.sent.needsAPerson

        case .draftShootToday:
            return it.isLiveDraft && !it.datesCouldNotBeRead && it.shootDay == Self.today

        case .draftShootAhead:
            return it.isLiveDraft && !it.datesCouldNotBeRead
                && (it.shootDay ?? Int.min) > Self.today

        // THE DATELESS DRAFT LIVES HERE, and it is the reason this band is not
        // simply "the shoot has passed" (PRD section 6, ovation#49). An invoice can
        // be created from scratch with no booking behind it, and every band keyed
        // on a shoot date has nowhere to put one, so before this the state was in
        // the data and absent from the product. It is placed here rather than given
        // a ninth band because "should have been sent" is what needs Dan about it.
        //
        // WRITTEN AS `?? Int.min` DELIBERATELY: a missing date sorts as long ago,
        // which is the reading that puts it in front of him. The sibling bands use
        // the opposite default for the same reason, so a nil is claimed here and
        // nowhere else.
        case .draftNeedsSending:
            return it.isLiveDraft
                && (it.datesCouldNotBeRead || (it.shootDay ?? Int.min) < Self.today)

        case .checkNotCleared:
            return it.isLiveIssued && it.money == .allOfItAwaitingAClearedCheck

        case .paidOrCleared:
            return it.isLiveIssued && it.money == .allOfItCleared

        // PART PAID IS NOT A BAND (PRD section 6). It sits wherever its dates put
        // it, which is here when it is past its terms, and the row carries the
        // outstanding figure rather than the total.
        // A DATE THAT WOULD NOT READ BACK IS CHASED, NOT LEFT WAITING (L50, L42).
        // It is a fault in a stored record, and the invoice list is the only way
        // to reach an invoice, so this is the one place Dan can see it at all.
        case .overdue:
            return it.isLiveIssued && it.isStillOwedSomething
                && (it.datesCouldNotBeRead || (it.dueDay ?? Int.max) < Self.today)

        // A SENT INVOICE WITH NO DUE DATE IS WAITING, NOT LATE, and that pair was
        // the SECOND gap this band's property test found (ovation#49, 2026-09-20).
        // Nobody had named it: `overdue` asks whether the due day has passed and
        // `sentAwaitingPayment` asked whether it has not, and an invoice carrying
        // no due day at all answered neither, so it was claimed by nothing and
        // could not be reached from the only screen that reaches invoices. Nothing
        // has been missed when there is no date to have missed, so it waits.
        //
        // THAT IT IS REACHABLE AT ALL IS ITS OWN QUESTION, and a separate one: PRD
        // 7 dates every invoice and gives it a due date 14 days later, so a sent
        // invoice with neither is a send that should arguably have been refused
        // before it went out. Placing it here is the list's answer, not the send
        // gate's, and the gate is where the refusal belongs (ovation#446).
        case .sentAwaitingPayment:
            return it.isLiveIssued && it.isStillOwedSomething && !it.datesCouldNotBeRead
                && (it.dueDay ?? Int.max) >= Self.today
        }
    }

    /// The day everything here is judged against.
    ///
    /// A CONSTANT RATHER THAN THE CLOCK. Every date in a standing is a day NUMBER
    /// relative to this, so a band cannot be right today and wrong tomorrow, and a
    /// fixture cannot walk into another state while the suite runs (L130, L74).
    /// The list converts real dates into this frame once, at the top.
    static let today = 0
}

private extension InvoiceStanding {

    /// Still in the list and not ended.
    var isLive: Bool { isDrawn && ending == nil && !couldSettleMoreThanOne }

    /// Live, and the mailbox match has not raised a question about it.
    var isLiveAndAnswered: Bool { isLive && !sent.needsAPerson }

    /// A draft: nothing has established that it went out.
    var isLiveDraft: Bool { isLiveAndAnswered && !sent.wasSent }

    /// Issued: a send was established, so a client has it.
    var isLiveIssued: Bool { isLiveAndAnswered && sent.wasSent }

    /// Money is still owed on it.
    var isStillOwedSomething: Bool {
        money == .nothing || money == .some
    }
}

// MARK: reading a stored invoice as a standing

extension InvoiceStanding {

    /// Reads one stored invoice as the handful of facts the bands are written over.
    ///
    /// EVERY DATE BECOMES A DAY NUMBER RELATIVE TO `today`, which is what lets the
    /// bands be written with no calendar in them and no clock behind them. A band
    /// comparing stored dates against `Date()` could never be tested at a chosen
    /// moment and would walk into another answer while a suite ran (L74, L130).
    ///
    /// IT DERIVES NOTHING THE INVOICE ALREADY ANSWERS. The money comes through
    /// `paymentState`, which is the app's one statement of where an invoice stands
    /// on money; asking the allocations again here would be a second predicate over
    /// the same facts, and two predicates over one question is how two surfaces come
    /// to disagree about one invoice (L370, L16).
    init(of invoice: Invoice, today: BusinessDate, couldSettleMoreThanOne: Bool) {
        self.init(
            ending: invoice.closure.map { closure in
                switch closure {
                case .cancelled: return Ending.cancelled
                case .deleted: return Ending.deleted
                }
            },
            sent: invoice.sentStatus,
            // THE INVOICE DATE IS THE SHOOT DATE (PRD 7): the invoice is dated its
            // booking's shoot day, and that stamped value is what decides the tax
            // year, so it is the one the list bands on rather than a date read back
            // off a shoot record that a combined invoice has several of.
            shootDay: Self.day(of: invoice.invoiceDate, from: today),
            dueDay: Self.day(of: invoice.dueDate, from: today),
            money: Self.money(of: invoice),
            couldSettleMoreThanOne: couldSettleMoreThanOne,
            // A DATE THAT IS THERE AND DID NOT READ. Asked as "present but
            // produced no day", which is the only way to tell it from a date
            // nobody gave (L50).
            datesCouldNotBeRead:
                (invoice.invoiceDate != nil && Self.day(of: invoice.invoiceDate, from: today) == nil)
                || (invoice.dueDate != nil && Self.day(of: invoice.dueDate, from: today) == nil))
    }

    /// How many days after `today` that day falls, and nil where there is no day.
    ///
    /// NIL SURVIVES, and that is the whole point of this function. A missing date
    /// defaulted to today would put a dateless draft in "send it today" looking like
    /// an ordinary row, which is exactly the invisibility ovation#49 exists to end
    /// (L67, L168).
    private static func day(of date: BusinessDate?, from today: BusinessDate) -> Int? {
        guard let date,
              let start = BusinessCalendar.startOfDay(forDayKey: date.dayKey),
              let base = BusinessCalendar.startOfDay(forDayKey: today.dayKey)
        else { return nil }
        return InvoiceBand.today
            + BusinessCalendar.dayNumber(for: start) - BusinessCalendar.dayNumber(for: base)
    }

    /// Where the invoice stands on money, in the four answers the bands need.
    ///
    /// THE CLEARED STEP BELONGS TO THE PAYMENT, NEVER THE INVOICE (PRD 5.15), and
    /// only a check has one. Reading "has not cleared" off a Zelle payment would
    /// park an invoice in "confirm it cleared" permanently, with no control anywhere
    /// able to answer it, which is a dead end rather than a wrong label (L109).
    private static func money(of invoice: Invoice) -> Money {
        switch invoice.paymentState {
        case .unpaid: return .nothing
        case .partlyPaid: return .some
        case .paid:
            let waiting = invoice.allocations.contains { allocation in
                guard allocation.releasedOn == nil, let payment = allocation.payment
                else { return false }
                return payment.isWaitingToClear
            }
            return waiting ? .allOfItAwaitingAClearedCheck : .allOfItCleared
        }
    }
}
