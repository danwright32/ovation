// ovation#319. Whether the Settings pane actually stores what is typed into it.
//
// THE GAP THIS CLOSES. `InvoiceFooterSetting` was tested directly and the pane was
// rendered and looked at, and neither of those is the thing Dan does: the save runs
// through the view's own change handler, and until this existed nothing drove that
// handler. A pane that drew perfectly and saved nothing would have passed every
// test in this repository and been found by Dan losing an afternoon's typing
// (L3: built is not wired, and wired is not proven).
//
// IT DRIVES WHAT THE BOXES WRITE THROUGH, not the setting. Calling `save` here
// would be asserting about a function this suite already trusts; what is in
// question is the WIRING between the box and the store, so the binding the boxes
// are handed is what these cases write into (L442).
//
// AN EARLIER VERSION SAVED FROM AN `onChange` BESIDE THE VIEW, which could only be
// reached by driving SwiftUI itself. Rather than write a test that reached into the
// view hierarchy to find a control, the pane was changed so the save lives in the
// binding's setter: the storing IS the editing, there is no path that edits without
// saving, and an ordinary value can be written through. Hard to test was the design
// telling us something.
//
// EVERY CASE USES A THROWAWAY DEFAULTS SUITE, named by an absolute path in a
// temporary folder, so nothing here can read or write Dan's real footer. This pane
// WRITES, so the seam matters on the way out as much as the way in (L201).
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

@MainActor
struct InvoiceSettingsPaneTests {

    @Test("what is typed into the payment box is stored")
    func typingThePaymentLineStoresIt() throws {
        let throwaway = try ThrowawayDefaults()
        let setting = InvoiceFooterSetting(defaults: throwaway.defaults)
        let pane = InvoiceSettingsPane(setting: setting)

        pane.footerBinding.wrappedValue.payment = "Bank transfer, details below"

        #expect(setting.footer.payment == "Bank transfer, details below")
    }

    @Test("the pane opens on what is already stored rather than on the shipped text")
    func thePaneOpensOnWhatIsStored() throws {
        let throwaway = try ThrowawayDefaults()
        let setting = InvoiceFooterSetting(defaults: throwaway.defaults)
        var stored = InvoiceFooter.fixed
        stored.contact = "somebody@example.example"
        setting.save(stored)

        let pane = InvoiceSettingsPane(setting: setting)
        let shown = pane.footerBinding.wrappedValue

        #expect(shown.contact == "somebody@example.example")
    }

    /// CLEARING IS AN EDIT LIKE ANY OTHER, and the one most easily lost: a pane that
    /// treated an empty box as "nothing to save" would put the shipped sentence back
    /// and send it to a client under Dan's name (L214). It is also what makes the
    /// send refuse, so a clear that did not persist would leave the refusal unarmed.
    @Test("clearing a box is stored as cleared, and the send then refuses")
    func clearingIsStored() throws {
        let throwaway = try ThrowawayDefaults()
        let setting = InvoiceFooterSetting(defaults: throwaway.defaults)
        let pane = InvoiceSettingsPane(setting: setting)

        pane.footerBinding.wrappedValue.payment = ""

        #expect(setting.footer.payment == "")
        #expect(setting.footer.refusals.contains(.paymentInstructionsNotSet))
    }

    /// THE PANE IS REACHABLE, which is the other half of being wired: a pane nothing
    /// presents works perfectly and is invisible to everybody (L546, ovation#231,
    /// where two presenters existed with tests and nothing presented either).
    @Test("Settings presents the invoices pane beside the backups one")
    func settingsPresentsThePane() throws {
        let throwaway = try ThrowawayDefaults()
        let view = SettingsView(
            backups: BackupSettingsPresenter(
                setting: BackupFolderSetting(defaults: throwaway.defaults,
                                             isDisposableLaunch: { true }),
                dataDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
                problems: ProblemsStore(journal: InMemoryProblemsJournal()),
                now: Date.init,
                askForAFolder: { nil }),
            invoiceFooter: InvoiceFooterSetting(defaults: throwaway.defaults))

        #expect(throws: Never.self) {
            try view.inspect().find(text: "Invoices")
        }
        #expect(throws: Never.self) {
            try view.inspect().find(text: "Backups")
        }
    }
}
