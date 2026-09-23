// ovation#457, PRD 5.4a. What the Edit menu offers about the invoice on screen.
//
// WHY A MENU NEEDS AN OBJECT AT ALL. The invoice being worked on is the shell's
// state and the menu is declared on the app, outside every view, so the two
// cannot see each other. This is the one place that says what the menu may do,
// the shell publishes into it, and the app reads it and acts. It is the shape
// `ReviewSamplesCommand` already uses, with the direction reversed: there the
// menu presses and the view listens, here the view publishes and the menu reads.
//
// TWO RECORDED DECISIONS MEET HERE AND NEITHER IS OVERRULED (L542).
// `docs/design/invoice.html` round 5 draws "Add a discount" only while there is
// no discount, because once there is one the row carries its own controls and a
// second way to change it would be the same action twice, with the menu copy
// further from the thing it acts on (L605). `OvationApp`'s own rule for this
// menu is written into it: an entry "IS NEVER HIDDEN, only disabled with a
// reason said out loud, because a control that is not there cannot be asked
// why" (L49, L109).
//
// So the entry stays and, where there is already a discount, it is disabled and
// NAMES WHERE THE DISCOUNT IS CHANGED. The design's concern is that there is one
// place to edit a discount, and that is kept; the app's is that a menu never
// goes quiet, and that is kept too.
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
    /// THE ORDER IS WRITTEN. The invoice's state comes before its discount: a
    /// sent invoice carrying one cannot have a discount added for the stronger
    /// reason, and sending Dan to a control that a sent invoice does not offer
    /// either would name a remedy that changes nothing (L111).
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
        if open.hasDiscount {
            return "This invoice already has a discount, which is changed on the invoice."
        }
        return nil
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
}
