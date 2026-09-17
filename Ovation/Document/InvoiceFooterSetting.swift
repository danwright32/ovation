// ovation#319, PRD 9. Where the three sentences at the foot of every invoice are
// kept, so Dan can change them without a code change.
//
// THEY GO TO CLIENTS UNDER HIS NAME (PRD 41a), which is why they may not stay
// fixed in the source: outbound copy that can only be changed by somebody editing
// code is copy that does not get changed.
//
// THE FALLBACK IS PER FIELD. Each of the three falls back to the shipped text on
// its own, because a reader that only fell back when NOTHING was stored would
// serve the shipped sentence for two fields the moment Dan edited the third.
//
// A STORED EMPTY STRING IS A VALUE, NOT AN ABSENCE, and that is the case this type
// exists to get right. Clearing the payment line is a deliberate act with a
// consequence, that invoices stop going out until it is written again, and a
// reader treating blank as "nothing stored" would quietly serve the old sentence
// back and send it to a client (L214). `UserDefaults.string(forKey:)` answers ""
// for a stored empty string and nil only when the key is absent, which is exactly
// the distinction this needs, so it is read rather than worked around.
import Foundation

struct InvoiceFooterSetting {

    static let paymentKey = "invoice.footer.payment"
    static let noteKey = "invoice.footer.note"
    static let contactKey = "invoice.footer.contact"

    /// INJECTED WITH NO DEFAULT RESOLVING TO `.standard`, the same as
    /// `BackupFolderSetting`: this type WRITES, and a seam that keeps a test off
    /// live data on the way in does not cover the way out (L201). A rendered
    /// settings pane in a test would otherwise overwrite Dan's real footer.
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var footer: InvoiceFooter {
        InvoiceFooter(
            payment: defaults.string(forKey: Self.paymentKey) ?? InvoiceFooter.fixed.payment,
            note: defaults.string(forKey: Self.noteKey) ?? InvoiceFooter.fixed.note,
            contact: defaults.string(forKey: Self.contactKey) ?? InvoiceFooter.fixed.contact)
    }

    /// Stored AS TYPED, spacing and all. What counts as empty is decided when the
    /// page is drawn and when the send is refused, through one predicate
    /// (`isBlankOnThePage`), never here: a writer that tidied the text would make
    /// what Dan sees in Settings differ from what he typed, and would decide on his
    /// behalf that a deliberate blank line is not wanted.
    func save(_ footer: InvoiceFooter) {
        defaults.set(footer.payment, forKey: Self.paymentKey)
        defaults.set(footer.note, forKey: Self.noteKey)
        defaults.set(footer.contact, forKey: Self.contactKey)
    }
}
