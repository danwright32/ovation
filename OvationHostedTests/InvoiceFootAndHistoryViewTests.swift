import Foundation
import SwiftData
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#548 and ovation#556. The invoice screen's second foot word and its history
/// pane, pressed the way Dan presses them and asserted by what each hands back (L442).
@MainActor
struct InvoiceFootAndHistoryViewTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let today = BusinessDate.stamping(noon)

    private static func context() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    /// A sent invoice for 375.00 plus tax, numbered 1123, created and sent.
    private static func sent(_ context: ModelContext, paid: Bool = false) -> Invoice {
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        client.email = "booker@example.com"
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity,
                              createdOn: .stamping(noon.addingTimeInterval(-10 * 86_400)))
        context.insert(invoice)
        invoice.add(LineItem.flat(Money(dollars: 375), describedAs: "Photography"))
        invoice.number = 1_123
        invoice.sentStatus = .sent(route: .ovationSentIt, at: noon.addingTimeInterval(-5 * 86_400))
        if paid {
            let payment = Payment(client: client, amount: invoice.total, method: .check, receivedOn: today)
            context.insert(payment)
            context.insert(PaymentAllocation(payment: payment, invoice: invoice, amount: invoice.total,
                                             allocatedOn: today, source: .recordedWithThePayment))
        }
        return invoice
    }

    private static func present(_ invoice: Invoice) -> InvoiceScreenPresenter {
        InvoiceScreenPresenter(invoice: invoice, footer: .fixed, today: today)
    }

    private static func text(in view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    private static func button(_ words: String, in view: some View) throws -> InspectableView<ViewType.Button> {
        try view.inspect().find(ViewType.Button.self, where: { button in
            (try? button.labelView().text().string()) == words
        })
    }

    private final class Asked {
        var resent: [InvoiceMailKind] = []
        var toggled = 0
    }

    // MARK: the foot (ovation#548)

    @Test("a sent invoice's foot offers Remind beside Record a payment, and Remind asks for a reminder")
    func remindIsOffered() throws {
        let asked = Asked()
        let view = InvoiceScreenView(presenter: Self.present(Self.sent(try Self.context())), close: {},
                                     resend: { asked.resent.append($0) })
        let said = try Self.text(in: view)
        #expect(said.contains("Remind"))
        #expect(said.contains("Record a payment"))
        try Self.button("Remind", in: view).tap()
        #expect(asked.resent == [.reminder])
    }

    @Test("a paid invoice's foot offers Send a copy beside Paid in full, and it asks for a copy")
    func sendACopyIsOffered() throws {
        let asked = Asked()
        let view = InvoiceScreenView(presenter: Self.present(Self.sent(try Self.context(), paid: true)),
                                     close: {}, resend: { asked.resent.append($0) })
        let said = try Self.text(in: view)
        #expect(said.contains("Paid in full"))
        #expect(said.contains("Send a copy"))
        #expect(!said.contains("Remind"))
        try Self.button("Send a copy", in: view).tap()
        #expect(asked.resent == [.copy])
    }

    @Test("with nowhere to send from, the word is drawn and cannot be pressed")
    func nowhereToSendFrom() throws {
        let view = InvoiceScreenView(presenter: Self.present(Self.sent(try Self.context())), close: {})
        #expect(try Self.button("Remind", in: view).isDisabled())
    }

    @Test("why the sheet did not open is said at the foot, beside the word")
    func arefusalIsSaid() throws {
        let view = InvoiceScreenView(presenter: Self.present(Self.sent(try Self.context())), close: {},
                                     resend: { _ in }, refusedResend: "That invoice is no longer there.")
        #expect(try Self.text(in: view).contains("That invoice is no longer there."))
    }

    @Test("a draft's foot carries neither word")
    func adraftCarriesNeither() throws {
        let context = try Self.context()
        let invoice = Self.sent(context)
        invoice.sentStatus = .notSent
        let view = InvoiceScreenView(presenter: Self.present(invoice), close: {}, resend: { _ in })
        let said = try Self.text(in: view)
        #expect(!said.contains("Remind"))
        #expect(!said.contains("Send a copy"))
    }

    // MARK: the history (ovation#556)

    private static func history(isOpen: Bool, marked: Set<String> = [], asked: Asked)
        -> InvoiceScreenView.HistoryControls {
        InvoiceScreenView.HistoryControls(isOpen: isOpen, marked: marked, toggle: { asked.toggled += 1 })
    }

    @Test("History is a word in the header, and pressing it asks for the pane")
    func historyIsInTheHeader() throws {
        let asked = Asked()
        let view = InvoiceScreenView(presenter: Self.present(Self.sent(try Self.context())), close: {},
                                     history: Self.history(isOpen: false, asked: asked))
        try Self.button("History", in: view).tap()
        #expect(asked.toggled == 1)
    }

    @Test("open, the pane lists what the system did and the word says Hide history")
    func theopenPaneLists() throws {
        let asked = Asked()
        let view = InvoiceScreenView(presenter: Self.present(Self.sent(try Self.context(), paid: true)),
                                     close: {}, history: Self.history(isOpen: true, asked: asked))
        let said = try Self.text(in: view)
        #expect(said.contains("Draft created"))
        #expect(said.contains("Sent"))
        #expect(said.contains("Payment recorded"))
        #expect(said.contains { $0.hasPrefix("$") && $0.hasSuffix("by check") })
        _ = try Self.button("Hide history", in: view)
    }

    @Test("closed, the pane's entries are hidden from a screen reader")
    func theclosedPaneIsHidden() throws {
        let asked = Asked()
        let view = InvoiceScreenView(presenter: Self.present(Self.sent(try Self.context())), close: {},
                                     history: Self.history(isOpen: false, asked: asked))
        let pane = try view.inspect().find(viewWithAccessibilityIdentifier: InvoiceScreenView.historyPaneID)
        #expect(try pane.accessibilityHidden())
    }

    @Test("the payment just recorded is marked, and it alone")
    func thejustRecordedPaymentIsMarked() throws {
        let asked = Asked()
        let presenter = Self.present(Self.sent(try Self.context(), paid: true))
        let payment = try #require(presenter.history.entries.first { $0.what == "Payment recorded" })
        let view = InvoiceScreenView(presenter: presenter, close: {},
                                     history: Self.history(isOpen: true, marked: [payment.id], asked: asked))
        let spoken = try view.inspect().findAll(where: { (try? $0.accessibilityLabel().string()) != nil })
            .compactMap { try? $0.accessibilityLabel().string() }
        #expect(spoken.filter { $0.hasSuffix(InvoiceScreenView.justRecorded) }.count == 1)
        #expect(InvoiceScreenView.spoken(payment, marked: true).hasPrefix(payment.when))
    }

    @Test("with nowhere to hold the pane, no History word is drawn")
    func noHistoryControlsNoWord() throws {
        let view = InvoiceScreenView(presenter: Self.present(Self.sent(try Self.context())), close: {})
        #expect(!(try Self.text(in: view).contains("History")))
    }

    // MARK: reachable by VoiceOver (L20)

    /// The one view that says what the invoice is to VoiceOver, carrying the label
    /// "client, shoot, state". Whatever it holds is replaced by that one sentence, so
    /// any button inside it is swallowed: VoiceOver can neither reach nor press it.
    ///
    /// READ FROM THE VIEW TREE, because the rendered accessibility tree is not built
    /// offscreen: measured 2026-09-27, an NSHostingView ordered back off every display
    /// answers with one bare AXGroup and no children, so walking it finds no button
    /// whether or not one is reachable, which is no measurement at all (L411).
    private static func buttonsInsideTheInvoiceLabel(of view: some View) throws -> [String] {
        let labelled = try view.inspect().find(where: { node in
            ((try? node.accessibilityLabel().string()) ?? "").hasPrefix("Cedar Hill Youth Orchestra, ")
        })
        return labelled.findAll(ViewType.Button.self)
            .compactMap { try? $0.labelView().text().string() }
    }

    @Test("History and Back to the list are each their own button to VoiceOver, History saying whether the pane is expanded")
    func historyIsReachable() throws {
        let asked = Asked()
        let closed = InvoiceScreenView(presenter: Self.present(Self.sent(try Self.context())), close: {},
                                       history: Self.history(isOpen: false, asked: asked))
        #expect(try Self.buttonsInsideTheInvoiceLabel(of: closed) == [],
                "the invoice's one combined element swallows these buttons")
        _ = try Self.button("Back to the list", in: closed)
        #expect(try Self.button("History", in: closed).accessibilityValue().string() == "collapsed")

        let open = InvoiceScreenView(presenter: Self.present(Self.sent(try Self.context())), close: {},
                                     history: Self.history(isOpen: true, asked: asked))
        #expect(try Self.button("Hide history", in: open).accessibilityValue().string() == "expanded")
        // And the invoice itself is still said, once, as one element.
        let spoken = try open.inspect().findAll(where: { (try? $0.accessibilityLabel().string()) != nil })
            .compactMap { try? $0.accessibilityLabel().string() }
        #expect(spoken.filter { $0.hasPrefix("Cedar Hill Youth Orchestra, ") && $0.hasSuffix(", Invoice 1123") }
                    .count == 1)
    }
}
