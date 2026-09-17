// ovation#319, PRD 9. The three sentences at the foot of every invoice, stored
// where Dan can change them.
//
// THE FALLBACK IS PER FIELD, NOT ALL OR NOTHING. Each of the three falls back on
// its own, because a reader that only falls back when NOTHING is stored would
// serve today's fixed text for two fields the moment Dan edits the third.
//
// AND A STORED EMPTY STRING IS A VALUE, NOT AN ABSENCE. This is the case worth
// the suite on its own: clearing the payment line is a deliberate act with a
// consequence (invoices stop going out until it is written), and a reader that
// treated blank as "nothing stored" would quietly serve the old sentence back and
// send it to a client under Dan's name (L214).
import Foundation
import Testing

struct InvoiceFooterSettingTests {

    /// A defaults suite of its own per case, so nothing here reads or writes Dan's
    /// real settings (L2). This type WRITES, so the seam matters on the way out as
    /// well as in (L201).
    ///
    /// THROUGH `ThrowawayDefaults`, NOT A NAMED SUITE (ovation#263). The first
    /// version of this made `UserDefaults(suiteName: "ovation.tests.footer.<uuid>")`
    /// and removed the domain afterwards, which is not enough: a BARE name is a
    /// domain in ~/Library/Preferences, and the run left four of them on this Mac
    /// (measured 2026-09-17, caught by the runner's own leftover check rather than
    /// by this suite). The helper names the suite by an absolute path in a
    /// temporary folder, so there is nothing in Preferences to leave behind.
    private static func setting(_ body: (InvoiceFooterSetting) throws -> Void) throws {
        let throwaway = try ThrowawayDefaults()
        try body(InvoiceFooterSetting(defaults: throwaway.defaults))
    }

    @Test("with nothing stored the footer reads as the text the app ships with")
    func nothingStored() throws {
        try Self.setting { setting in
            #expect(setting.footer == InvoiceFooter.fixed)
        }
    }

    @Test("what is saved is what comes back")
    func savedIsRead() throws {
        try Self.setting { setting in
            let written = InvoiceFooter(payment: "Bank transfer, details on request",
                                        note: "See you next season",
                                        contact: "dan@example.com")
            setting.save(written)
            #expect(setting.footer == written)
        }
    }

    @Test("editing one field leaves the other two as they were, rather than resetting them")
    func perFieldFallback() throws {
        try Self.setting { setting in
            var footer = setting.footer
            footer.payment = "Bank transfer to Ovation"
            setting.save(footer)

            #expect(setting.footer.payment == "Bank transfer to Ovation")
            #expect(setting.footer.note == InvoiceFooter.fixed.note)
            #expect(setting.footer.contact == InvoiceFooter.fixed.contact)
        }
    }

    // THE ONE THIS SUITE EXISTS FOR. A blank that Dan typed must survive being read
    // back, because the whole point of blanking it is that sending stops.
    @Test("a field cleared on purpose stays cleared, and does not revert to the shipped text")
    func clearedStaysCleared() throws {
        try Self.setting { setting in
            var footer = setting.footer
            footer.payment = ""
            setting.save(footer)

            #expect(setting.footer.payment == "")
            #expect(setting.footer.payment != InvoiceFooter.fixed.payment)
        }
    }

    @Test("what Dan typed is stored as typed, spacing and all")
    func storedAsTyped() throws {
        try Self.setting { setting in
            var footer = setting.footer
            footer.contact = "dan@example.com\n(000) 000 0000"
            setting.save(footer)
            #expect(setting.footer.contact == "dan@example.com\n(000) 000 0000")
        }
    }

    // MARK: what stops a send

    @Test("a footer with all three written stops nothing")
    func completeFooterRefusesNothing() {
        #expect(InvoiceFooter.fixed.refusals.isEmpty)
    }

    @Test("an empty payment line stops the send, and says so as its own reason")
    func emptyPaymentRefuses() {
        var footer = InvoiceFooter.fixed
        footer.payment = ""
        #expect(footer.refusals == [.paymentInstructionsNotSet])
    }

    @Test("an empty contact stops the send, and says so as its own reason")
    func emptyContactRefuses() {
        var footer = InvoiceFooter.fixed
        footer.contact = ""
        #expect(footer.refusals == [.contactDetailsNotSet])
    }

    // TWO CAUSES, TWO REASONS, never one combined one (L11). Both empty is a real
    // state: it is what a fresh Mac would look like if the defaults were ever
    // cleared, and Dan has to be told which to write.
    @Test("both empty are two separate reasons, not one")
    func bothEmptyAreTwoReasons() {
        let footer = InvoiceFooter(payment: "", note: "", contact: "")
        #expect(footer.refusals == [.paymentInstructionsNotSet, .contactDetailsNotSet])
    }

    // SPACE IS NOT TEXT. A line holding a space or a newline looks empty on the page
    // and would print as a blank line under a heading, so it counts as empty here.
    @Test("a field holding only spaces counts as empty, because that is how it prints")
    func whitespaceIsEmpty() {
        var footer = InvoiceFooter.fixed
        footer.payment = "   \n  "
        #expect(footer.refusals == [.paymentInstructionsNotSet])
    }

    // THE NOTE IS OPTIONAL, and this asserts the decision rather than leaving it to
    // whichever fields happen to be checked (Dan, 2026-09-17).
    @Test("an empty note stops nothing, because the note is optional")
    func emptyNoteRefusesNothing() {
        var footer = InvoiceFooter.fixed
        footer.note = ""
        #expect(footer.refusals.isEmpty)
    }
}
