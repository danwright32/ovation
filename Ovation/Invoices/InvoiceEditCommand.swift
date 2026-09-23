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

        init(_ invoice: Invoice) {
            id = invoice.persistentModelID
            hasDiscount = invoice.discount != nil
            sentStatus = invoice.sentStatus
        }
    }

    /// What the shell is showing, or nil while the list is.
    var open: Open?

    /// What adding a discount does, given by the app, or nil where this launch
    /// has no store to write to.
    var addDiscount: ((PersistentIdentifier, Discount) -> Void)?

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
}
