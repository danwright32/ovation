// ovation#457, PRD 5.4a. What the Edit menu offers about the invoice on screen.
//
// WHY A MENU NEEDS AN OBJECT AT ALL. The invoice being worked on is the shell's
// state and the menu is declared on the app, outside every view, so the two
// cannot see each other. This is the one place that says what the menu may do,
// the shell publishes into it, and the app reads it and acts. It is the shape
// `ReviewSamplesCommand` already uses, with the direction reversed: there the
// menu presses and the view listens, here the view publishes and the menu reads.
//
// THE ENTRY IS DRAWN ONLY WHILE THERE IS NO DISCOUNT: hidden, not disabled,
// where one exists. That is `docs/design/invoice.html` round 5, and Dan decided
// on 2026-09-23 to follow it (ovation#495), which retired an earlier version that
// kept the entry and disabled it. Once there is a discount the row carries its
// own controls, and a second way to change it would be the same action twice,
// with the menu copy further from the thing it acts on (L605).
//
// Where there is no discount and it still cannot be added (no invoice open, a
// sent invoice), it stays and is disabled with its reason said out loud, which is
// the menu's own rule for every other entry (L49, L109).
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class InvoiceEditCommand {

    /// The invoice on screen, as the menu needs to know it.
    ///
    /// VALUES, NEVER THE OBJECT. This outlives any one read of the store and is
    /// held by the app, so holding a model object here would be the stale
    /// snapshot PRD 51l exists to prevent (ovation#440).
    struct Open: Equatable {
        let id: PersistentIdentifier
        let hasDiscount: Bool
        let sentStatus: SentStatus

        /// Whether a referral credit is already on it, which is what turns the
        /// one credit entry from Apply into Remove (the design record's round 5
        /// draws it as one entry whose word changes, not as two).
        let hasReferralCredit: Bool

        /// Whether the client has anything banked to spend, and whether the
        /// invoice is charging anything to spend it on. BOOLEANS RATHER THAN THE
        /// FIGURES, because the menu never shows either number: it decides only
        /// whether the entry can be pressed, and carrying the amounts here would
        /// be state with no reader (L46).
        let clientHasCreditBanked: Bool
        let isChargingSomething: Bool

        init(_ invoice: Invoice) {
            id = invoice.persistentModelID
            hasDiscount = invoice.discount != nil
            sentStatus = invoice.sentStatus
            hasReferralCredit = invoice.referralCredit != nil
            clientHasCreditBanked = invoice.clientHasReferralCreditBanked
            isChargingSomething = Money.sum(of: invoice.lineItems.map(\.amount)) > .zero
        }
    }

    /// What the shell is showing, or nil while the list is.
    var open: Open?

    /// What adding a discount does, given by the app, or nil where this launch
    /// has no store to write to.
    var addDiscount: ((PersistentIdentifier, Discount) -> Void)?

    /// What applying and removing a referral credit do, given by the app, or nil
    /// where this launch has no store to write to.
    ///
    /// TWO CLOSURES RATHER THAN ONE TAKING A FLAG, because a boolean at the call
    /// site says nothing about which way round it means, and these two do
    /// opposite things to a client's balance.
    var applyReferralCredit: ((PersistentIdentifier) -> Void)?
    var removeReferralCredit: ((PersistentIdentifier) -> Void)?

    /// The entry's words, the design record's own.
    static let addDiscountTitle = "Add a discount"

    /// TEN PERCENT, which is round 5's measurement rather than a guess: it is the
    /// commonest of the five discounts in the whole of Dan's history.
    ///
    /// FORCE UNWRAPPED DELIBERATELY AND SAFELY: `Discount(percentBasisPoints:)`
    /// refuses only a share outside nothing to everything, and this is a
    /// constant inside it. A fallback here would be a second answer to a question
    /// that cannot be asked (L11).
    static let whatItAdds = Discount(percentBasisPoints: 1_000)!

    /// Why the entry would do nothing, in Dan's words rather than the code's
    /// (L399), or nil when it can be pressed.
    ///
    /// ONE ANSWER GOVERNS BOTH whether it is disabled and what it says, because
    /// two conditions about one thing are two things that can disagree (L70).
    ///
    /// ASKED ONLY WHILE THERE IS NO DISCOUNT. An invoice that already carries
    /// one does not draw the entry at all (`offersToAddADiscount`, ovation#495),
    /// so the reasons here are only the invoice's own state.
    static func whyADiscountCannotBeAdded(_ open: Open?) -> String? {
        guard let open else { return "No invoice is open." }
        switch open.sentStatus {
        case .notSent: break
        // SAID IN THE WRITER'S OWN WORDS, never a second wording of one fact
        // (L118). `InvoiceDiscountWriter` refuses the same states, because a
        // screen gating a write is not the write being guarded (L196).
        case .sent: return InvoiceDiscountRefusal.invoiceWasSent.sentence
        case .attempting, .couldNotDetermine:
            return InvoiceDiscountRefusal.sendIsUnsettled.sentence
        }
        return nil
    }

    /// Whether the entry is drawn at all. ovation#495.
    ///
    /// ONLY WHILE THERE IS NO DISCOUNT, whatever else is true of the invoice,
    /// because the design record's own test is `if (!DISCOUNT)` and asks nothing
    /// else: a sent invoice carrying one hides the entry too, rather than drawing
    /// it to refuse. With no invoice open there is no discount, so it is drawn.
    static func offersToAddADiscount(_ open: Open?) -> Bool {
        open?.hasDiscount != true
    }

    // MARK: the referral credit, PRD 5.8 and 5.51e

    /// What the credit entry says, which is the whole of its interface.
    ///
    /// ONE ENTRY WHOSE WORD CHANGES, never two. The design record's round 5 draws
    /// it that way (`Apply a referral credit` against `Remove the referral
    /// credit`), and PRD 5.51e says why the menu is the only place it can be
    /// done: the credit "keeps its menu entry, having no controls of its own
    /// anywhere", unlike the discount, which has a line of its own on the
    /// invoice.
    ///
    /// WITH NO INVOICE OPEN IT OFFERS TO APPLY, because that is what the entry
    /// will do the moment there is one, and a menu that renames itself as you
    /// open a screen is harder to learn than one that does not.
    static func referralCreditTitle(_ open: Open?) -> String {
        open?.hasReferralCredit == true ? removeReferralCreditTitle : applyReferralCreditTitle
    }

    /// The entry's two words, the design record's own.
    static let applyReferralCreditTitle = "Apply a referral credit"
    static let removeReferralCreditTitle = "Remove the referral credit"

    /// Why the credit entry would do nothing, in Dan's words rather than the
    /// code's (L399), or nil when it can be pressed.
    ///
    /// ONE ANSWER GOVERNS BOTH whether it is disabled and what it says, because
    /// two conditions about one thing are two things that can disagree (L70).
    ///
    /// A CREDIT ALREADY ON THE INVOICE CAN ALWAYS COME OFF. The balance and the
    /// charges decide whether one can be SPENT and a removal spends nothing, so
    /// asking them of a removal would strand the credit on the invoice the moment
    /// its last line was deleted.
    ///
    /// THE ORDER IS WRITTEN AND IT MATCHES THE WRITER'S. The invoice's state comes
    /// first, then the balance, then the charges;
    /// `InvoiceReferralCreditWriter.applyReferralCredit` refuses in that same
    /// order, and both say it in the refusal's own sentence, because a screen
    /// gating a write is not the write being guarded (L196, L118).
    static func whyTheReferralCreditCannotChange(_ open: Open?) -> String? {
        guard let open else { return "No invoice is open." }
        switch open.sentStatus {
        case .notSent: break
        case .sent: return InvoiceReferralCreditRefusal.invoiceWasSent.sentence
        case .attempting, .couldNotDetermine:
            return InvoiceReferralCreditRefusal.sendIsUnsettled.sentence
        }
        if open.hasReferralCredit { return nil }
        if !open.clientHasCreditBanked {
            return InvoiceReferralCreditRefusal.noCreditToSpend.sentence
        }
        if !open.isChargingSomething {
            return InvoiceReferralCreditRefusal.nothingIsBeingCharged.sentence
        }
        return nil
    }

    // MARK: what the menu draws (ovation#657)

    /// What an entry says when a store IS open and the invoice's screen has not
    /// given the menu anything to run for it.
    ///
    /// SAID BY WHAT WAS MEASURED, a writer missing, never as no store, which is
    /// a different cause read from a different thing (L11, L440). The app builds
    /// every writer from the open store, so with a store open this should not
    /// happen; if it does, it is a fault in what the screen published, and the
    /// sentence says only that the press would do nothing and why.
    static let nothingRegistered = "The invoice on screen has not given the menu "
        + "anything to run for this, so pressing it would do nothing."

    /// Why adding a discount from the menu would do nothing right now, or nil
    /// when a press will run.
    ///
    /// THE INVOICE'S OWN REASON FIRST, THEN WHY NOTHING WOULD RUN. Before
    /// ovation#657 the entry judged only the invoice, so with an invoice open and
    /// no writer registered it was enabled and a press returned silently, leaving
    /// pressing it again as the only diagnosis (L109, L148). The invoice's reason
    /// wins because it would still stop the press once the rest was fixed (L111).
    ///
    /// IT TAKES THE STORE, as the export's and the draft's `whyItCannotRun` do,
    /// so that "no store" is said only where the store itself was read and found
    /// missing. A missing writer with a store open is the other sentence.
    func whyTheDiscountEntryIsDisabled(container: ModelContainer?) -> String? {
        if let why = Self.whyADiscountCannotBeAdded(open) { return why }
        return Self.whyNothingWouldRun(writerIsThere: addDiscount != nil,
                                       container: container)
    }

    /// Why pressing the credit entry would do nothing right now, or nil when a
    /// press will run. The same order and the same two causes as the discount's.
    func whyTheReferralCreditEntryIsDisabled(container: ModelContainer?) -> String? {
        if let why = Self.whyTheReferralCreditCannotChange(open) { return why }
        // ONLY THE WRITER THE WORD POINTS AT. A credit to remove needs the
        // remover and nothing else, so a missing applier must not grey it.
        let writer = open?.hasReferralCredit == true
            ? removeReferralCredit : applyReferralCredit
        return Self.whyNothingWouldRun(writerIsThere: writer != nil, container: container)
    }

    /// Nil while the writer is there, because then a press runs; otherwise the
    /// cause that was actually read: no store, or a store with nothing
    /// registered. One place, so the two entries cannot word it differently.
    private static func whyNothingWouldRun(writerIsThere: Bool,
                                           container: ModelContainer?) -> String? {
        if writerIsThere { return nil }
        return container == nil ? NoStoreOpen.sentence : nothingRegistered
    }
}
