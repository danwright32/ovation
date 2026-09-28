import SwiftData
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#485. Every write the invoice screen offers REACHES it, through the layers
/// the app really uses, and reaches the WRITER it is named for.
///
/// Each write travels from `OvationApp` through `RootView` and `ShellView` as a
/// closure passed down by name at every layer, and nil is a legitimate value there,
/// meaning this launch has no store: the screen then draws the value as text with
/// no control. So a layer that forgets one draws exactly the screen of a launch that
/// cannot write, and every other test passed that screen, because each built
/// `InvoiceScreenView` directly and handed it the closure itself (L718, L3). The two
/// menu entries are worse: a lost closure there leaves an entry present, enabled and
/// doing nothing, and the referral credit has no other interface at all.
///
/// SO THIS STARTS AT `RootView`, takes the `ShellView` that RootView itself builds,
/// puts THAT on screen, opens the invoice the way Dan does, from a row of the list,
/// and then presses what the screen and the menu were given. It is the shell RootView
/// built rather than one made here, so both hops are the app's own. Each spy says
/// which writer it is, so a layer passing the right closure to the wrong control
/// fails here as well as one passing none. The hop above `RootView`, from the app
/// itself, is `scripts/check-writers-wired.sh`, because an `App`'s scene cannot be
/// built in a test.
///
/// ON SCREEN, THROUGH `Inspection`, because the open invoice is the shell's `@State`
/// and a view value inspected off screen reads that as nil for ever. The first
/// version of this test inspected RootView directly and never found the screen.
///
/// THE WRITERS ARE ENUMERATED FROM `RootView` ITSELF rather than typed here, so the
/// next write added to it fails this until it is routed below (L41, L96).
/// The conformance that lets a test wait on a view on screen. Declared here, so the
/// app target carries no dependency on the inspector.
extension Inspection: InspectionEmissary {}

@MainActor
struct WritersReachTheScreenTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let today = BusinessDate.stamping(noon)

    /// Which writer each spy is, as `RootView` names it.
    @MainActor
    final class Heard {
        var names: [String] = []
        func record(_ name: String) { names.append(name) }
    }

    /// One draft with a shoot and a line, in a store that lives as long as the test.
    struct Draft {
        let context: ModelContext
        let invoice: Invoice
        let shoot: Shoot
        let client: Client
        let type: ServiceType
    }

    private static func draft() throws -> Draft {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .notExempt)
        client.email = "booker@example.com"
        context.insert(client)
        let type = ServiceType(name: "Rush turnaround", role: .ordinary,
                               defaultUnitAmount: Money(dollars: 150))
        context.insert(type)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        invoice.dueDate = .stamping(noon.addingTimeInterval(14 * 86_400))
        context.insert(invoice)
        let shoot = Shoot(name: "Autumn Evensong", when: .dayOnly(today), venue: "St Anne's")
        shoot.shotFrom = ClockTime("19:00")
        invoice.add(shoot)
        let line = LineItem.hourly(hours: Hours(whole: 1), at: Money(dollars: 250),
                                   describedAs: "Photography", for: shoot)
        invoice.add(line)
        try context.save()
        return Draft(context: context, invoice: invoice, shoot: shoot, client: client, type: type)
    }

    /// The window the app builds once the shell owns it, with every writer either a
    /// spy that says its own name or, with `spying` false, absent as on a launch
    /// with no store.
    /// `writePayment` and `writeCleared` replace the spy for one case, a double
    /// optional so a case can hand over an explicit nil.
    private static func window(
        _ draft: Draft, heard: Heard, edits: InvoiceEditCommand, spying: Bool,
        writePayment: ((PersistentIdentifier, PaymentEntry) async -> String?)?? = nil,
        writeCleared: ((PersistentIdentifier) async -> String?)?? = nil,
        openings: Heard? = nil, on destination: Destination = .invoices,
        reviewer: InvoiceReviewer? = nil
    ) -> RootView {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        let blocking = Client(name: "Client 0", taxStatus: .neverRecorded)
        blocking.email = "c0@example.example"
        let roster = RosterPresenter(clients: [blocking], write: { _, _ in })
        return RootView(
            presenter: LaunchPresenter(store: store), store: store,
            roster: roster,
            shell: ShellPresenter(selected: destination, rosterHasWork: { true }),
            invoices: InvoiceListPresenter(invoices: [draft.invoice], heldMoney: [:], today: today),
            openInvoice: { _ in
                openings?.record("openInvoice")
                return InvoiceScreenPresenter(invoice: draft.invoice, footer: .fixed, today: today,
                                              serviceTypes: [draft.type])
            },
            writeTime: spying ? { _, _, _ in heard.record("writeTime"); return nil } : nil,
            writeDueDate: spying ? { _, _ in heard.record("writeDueDate"); return nil } : nil,
            writeTaxStatus: spying ? { _, _ in heard.record("writeTaxStatus"); return nil } : nil,
            writeLine: spying ? { _, _, _ in heard.record("writeLine"); return nil } : nil,
            writeServiceType: spying ? { _, _ in heard.record("writeServiceType"); return nil } : nil,
            writeDiscount: spying ? { _, _ in heard.record("writeDiscount"); return nil } : nil,
            writeReferralCredit: spying ? { _, _ in heard.record("writeReferralCredit"); return nil } : nil,
            writePayment: writePayment
                ?? (spying ? { _, _ in heard.record("writePayment"); return nil } : nil),
            writeCleared: writeCleared
                ?? (spying ? { _ in heard.record("writeCleared"); return nil } : nil),
            writeHeldMoney: spying ? { _, _ in heard.record("writeHeldMoney"); return nil } : nil,
            clients: ClientsPresenter(clients: [draft.client]),
            writePaymentTerm: spying ? { _, _ in heard.record("writePaymentTerm"); return nil } : nil,
            acknowledgeSharedAddress: spying ? { _ in heard.record("acknowledgeSharedAddress"); return nil } : nil,
            edits: edits, reviewer: reviewer)
    }

    /// What an inspection found, carried out of its closure.
    @MainActor
    final class Found {
        var screen: InvoiceScreenView?
    }

    /// The shell RootView builds for this window: the first hop, and the value that
    /// is put on screen for the rest.
    private static func shell(of root: RootView) throws -> ShellView {
        try root.inspect().find(ShellView.self).actualView()
    }

    /// Opens the draft from its row, through the list's own `open` on the shell that
    /// is on screen, which is the only way its invoice comes to be open.
    private static func open(_ draft: Draft, in shell: ShellView) async throws -> InvoiceScreenView {
        let id = draft.invoice.persistentModelID
        try await shell.inspection.inspect { view in
            let list = try view.find(InvoiceListView.self).actualView()
            let open = try #require(list.open, "the list was given no way to open a row")
            open(id)
        }
        let found = Found()
        try await shell.inspection.inspect { view in
            found.screen = try view.find(InvoiceScreenView.self).actualView()
        }
        return try #require(found.screen, "opening the row did not put the invoice on screen")
    }

    /// Waits for the writes the presses start, which run in tasks of their own, and
    /// gives up at a bound rather than hanging, so a write that never arrives is a
    /// failure with its name rather than a stalled run (L110, L290).
    private static func settle(_ heard: Heard, until count: Int) async {
        for _ in 0..<500 where heard.names.count < count {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test("every write RootView is given reaches the control or menu entry named for it")
    func everyWriterReachesItsControl() async throws {
        let draft = try Self.draft()
        let heard = Heard()
        let edits = InvoiceEditCommand()
        let root = Self.window(draft, heard: heard, edits: edits, spying: true)
        let shell = try Self.shell(of: root)
        ViewHosting.host(view: shell)
        defer { ViewHosting.expel() }

        let screen = try await Self.open(draft, in: shell)
        let shoot = draft.shoot.persistentModelID
        let invoice = draft.invoice.persistentModelID

        // What each press is, and the writer it must reach. The screen's own
        // controls first, then the Edit menu's, which the shell publishes on open.
        var presses: [(control: String, writer: String, press: (() -> Void)?)] = [
            ("setTime", "writeTime", screen.setTime.map { set in { set(shoot, .start, ClockTime("20:00")) } }),
            ("setDueDate", "writeDueDate", screen.setDueDate.map { set in { set(Self.today) } }),
            ("answerTax", "writeTaxStatus",
             screen.answerTax.map { answer in { answer(draft.client.persistentModelID, .exempt) } }),
            ("addLine", "writeLine",
             screen.addLine.map { add in { add(draft.type.persistentModelID, Money(dollars: 150)) } }),
            ("createType", "writeServiceType", screen.createType.map { make in { make("Travel", nil) } }),
            ("setDiscount", "writeDiscount",
             screen.setDiscount.map { set in { set(InvoiceEditCommand.whatItAdds) } }),
        ]
        // ovation#510. The payment sheet's Record, and Mark cleared on a check.
        let entry = PaymentEntry(amount: Money(dollars: 100), method: .zelle,
                                 received: Self.today, press: UUID())
        presses.append(("payment sheet: Record", "writePayment",
                        screen.payment.map { payment in { payment.record(entry) } }))
        presses.append(("Mark cleared", "writeCleared",
                        screen.payment.map { payment in { payment.markCleared(invoice) } }))
        // ovation#185. Use it here and Remove on the held money lines.
        presses.append(("held money: Use it here", "writeHeldMoney",
                        screen.heldMoney.map { held in { held.apply(invoice) } }))
        presses.append(("held money: Remove", "writeHeldMoney",
                        screen.heldMoney.map { held in { held.remove(invoice) } }))
        presses.append(("Edit menu: add a discount", "writeDiscount",
                        edits.addDiscount.map { add in { add(invoice, InvoiceEditCommand.whatItAdds) } }))
        presses.append(("Edit menu: apply the referral credit", "writeReferralCredit",
                        edits.applyReferralCredit.map { apply in { apply(invoice) } }))
        presses.append(("Edit menu: remove the referral credit", "writeReferralCredit",
                        edits.removeReferralCredit.map { remove in { remove(invoice) } }))

        // THE LIST ABOVE COVERS EVERY WRITER ROOTVIEW DECLARES, read off RootView
        // rather than typed, so a new one fails here until it is routed.
        // EVERY CLOSURE THAT WRITES, not only those named `write...`: the shared
        // address's `acknowledgeSharedAddress` writes too (review of ovation#600).
        let declared = Set(Mirror(reflecting: root).children.compactMap(\.label)
            .filter { $0.hasPrefix("write") || $0.hasPrefix("acknowledge") })
        #expect(!declared.isEmpty, "no writer was read off RootView, so nothing was judged")
        #expect(declared == Set(presses.map(\.writer)).union(Self.clientsScreenWriters),
                "RootView's writers and the ones this test presses differ")

        for (control, writer, press) in presses {
            let before = heard.names.count
            guard let press else {
                Issue.record("\(control) was not given to the screen or menu, so \(writer) cannot be reached")
                continue
            }
            press()
            await Self.settle(heard, until: before + 1)
            #expect(heard.names.count == before + 1, "pressing \(control) wrote nothing")
            #expect(heard.names.last == writer,
                    "pressing \(control) reached \(heard.names.last ?? "nothing") instead of \(writer)")
        }
    }

    /// ovation#568. The writes that reach the Clients screen rather than the invoice
    /// screen, pressed by the case below and counted by the one above.
    private static let clientsScreenWriters: Set<String> = ["writePaymentTerm", "acknowledgeSharedAddress"]

    @Test("the Clients screen is given the tax status, payment terms and shared address writes")
    func theclientsScreenIsGivenItsWrites() async throws {
        let draft = try Self.draft()
        let heard = Heard()
        let root = Self.window(draft, heard: heard, edits: InvoiceEditCommand(), spying: true,
                               on: .clients)
        let screen = try Self.shell(of: root).inspect().find(ClientsView.self).actualView()
        let client = draft.client.persistentModelID

        let presses: [(control: String, writer: String, press: (() async -> Void)?)] = [
            ("Sales tax", "writeTaxStatus", screen.writeTax.map { w in { _ = await w(client, .exempt) } }),
            ("Payment terms", "writePaymentTerm",
             screen.writeTerm.map { w in { _ = await w(client, PaymentTerms.standard) } }),
            ("That is correct", "acknowledgeSharedAddress",
             screen.acknowledgeShared.map { w in { _ = await w(client) } }),
        ]
        #expect(Set(presses.map(\.writer)).isSuperset(of: Self.clientsScreenWriters))
        for (control, writer, press) in presses {
            guard let press else {
                Issue.record("\(control) was not given to the Clients screen, so \(writer) cannot be reached")
                continue
            }
            await press()
            #expect(heard.names.last == writer, "pressing \(control) reached \(heard.names.last ?? "nothing")")
        }
    }

    /// THE OTHER DIRECTION, or the test above is satisfied by a shell that offers
    /// every control unconditionally (L98, L159). A launch with no store is given no
    /// writers, and then the screen draws no control and the menu has no action.
    /// The screen as the shell draws it now, read again rather than kept, because
    /// the shell rebuilds it after every write.
    private static func current(in shell: ShellView) async throws -> InvoiceScreenView? {
        let found = Found()
        try await shell.inspection.inspect { view in
            found.screen = try? view.find(InvoiceScreenView.self).actualView()
        }
        return found.screen
    }

    /// ovation#510. The payment controls offer Record AND Mark cleared, so they
    /// need both writers: one without the other would draw a word that does
    /// nothing (L109).
    @Test("with a payment writer and no clearing writer, no payment controls are offered")
    func halfTheWritersOffersNoPayment() async throws {
        let draft = try Self.draft()
        let shell = try Self.shell(of: Self.window(
            draft, heard: Heard(), edits: InvoiceEditCommand(), spying: false,
            writePayment: .some({ _, _ in nil }), writeCleared: .some(nil)))
        ViewHosting.host(view: shell)
        defer { ViewHosting.expel() }
        let screen = try await Self.open(draft, in: shell)
        #expect(screen.payment == nil)
    }

    /// A refused Mark cleared is said beside the foot, and opening the payment sheet
    /// clears it, so an old refusal never sits beside a new action (L680).
    @Test("a refused Mark cleared is said, and opening the sheet clears it")
    func arefusedClearingIsClearedOnOpen() async throws {
        let draft = try Self.draft()
        let refusal = PaymentRecordingRefusal.hasNoClearedStep.sentence
        let shell = try Self.shell(of: Self.window(
            draft, heard: Heard(), edits: InvoiceEditCommand(), spying: false,
            writePayment: .some({ _, _ in nil }), writeCleared: .some({ _ in refusal })))
        ViewHosting.host(view: shell)
        defer { ViewHosting.expel() }
        let screen = try await Self.open(draft, in: shell)
        let controls = try #require(screen.payment)

        controls.markCleared(draft.invoice.persistentModelID)
        var said: String?
        for _ in 0..<200 {
            said = try await Self.current(in: shell)?.payment?.refusedClearing
            if said != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(said == refusal)

        try #require(try await Self.current(in: shell)?.payment).open()
        var after: String? = refusal
        for _ in 0..<200 {
            after = try await Self.current(in: shell)?.payment?.refusedClearing
            if after == nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(after == nil)
    }

    /// ovation#185. A write the screen did not make still changes the invoice on
    /// it: the held money pass puts money on a draft the moment its times price
    /// it, after the screen has already read it back. So the open invoice is read
    /// again whenever the list is, which is on every committed write (L14).
    @Test("the open invoice is read again whenever the list is")
    func theopenInvoiceFollowsTheList() async throws {
        let draft = try Self.draft()
        let openings = Heard()
        let shell = try Self.shell(of: Self.window(
            draft, heard: Heard(), edits: InvoiceEditCommand(), spying: false,
            openings: openings))
        ViewHosting.host(view: shell)
        defer { ViewHosting.expel() }
        _ = try await Self.open(draft, in: shell)
        let before = openings.names.count
        #expect(before >= 1, "opening the row read the invoice")

        let reread = InvoiceListPresenter(invoices: [draft.invoice], heldMoney: [:], today: Self.today)
        try await shell.inspection.inspect { view in
            try view.hStack().callOnChange(oldValue: ObjectIdentifier?.none,
                                           newValue: Optional(ObjectIdentifier(reread)))
        }

        #expect(openings.names.count == before + 1, "a new list did not read the open invoice again")
    }

    @Test("with no writers given, the screen offers no write and the menu no action")
    func noWriterNoControl() async throws {
        let draft = try Self.draft()
        let edits = InvoiceEditCommand()
        let shell = try Self.shell(of: Self.window(draft, heard: Heard(), edits: edits, spying: false))
        ViewHosting.host(view: shell)
        defer { ViewHosting.expel() }

        let screen = try await Self.open(draft, in: shell)

        #expect(screen.setTime == nil)
        #expect(screen.setDueDate == nil)
        #expect(screen.answerTax == nil)
        #expect(screen.addLine == nil)
        #expect(screen.createType == nil)
        #expect(screen.setDiscount == nil)
        #expect(screen.payment == nil, "no payment writer, so no Record a payment and no Mark cleared")
        #expect(screen.heldMoney == nil, "no held money writer, so no Use it here and no Remove")
        #expect(screen.resend == nil, "no reviewer, so neither Remind nor Send a copy can send")
        #expect(edits.addDiscount == nil)
        #expect(edits.applyReferralCredit == nil)
        #expect(edits.removeReferralCredit == nil)
        // The invoice really is on screen and the menu knows it, so the absences
        // above are about the writers rather than about nothing being open.
        #expect(edits.open?.id == draft.invoice.persistentModelID)
    }

    /// ovation#566 and ovation#99. A notice arriving while an invoice is open, and
    /// Read pressed on it, leave the invoice open (Dan, 2026-09-26). Before this a
    /// mid session notice replaced the whole window and closed the invoice; the
    /// foot now carries it, and Read opens a popover without moving anything.
    @Test("a notice arriving and Read pressed on it leave the open invoice open")
    func aNoticeAndItsReadLeaveTheInvoiceOpen() async throws {
        let draft = try Self.draft()
        let shell = try Self.shell(of: Self.window(draft, heard: Heard(),
                                                   edits: InvoiceEditCommand(), spying: false))
        ViewHosting.host(view: shell)
        defer { ViewHosting.expel() }
        _ = try await Self.open(draft, in: shell)

        let notice = shell.problems.raise(kind: .exportWritten, subject: "year-end-export-2026",
                                          sentence: "The 2026 export is written.", now: Self.noon)
        try await shell.inspection.inspect { view in
            try view.find(text: "2026 export written")
            let reads = try view.findAll(ViewType.Button.self)
                .filter { (try? $0.labelView().text().string()) == RailFoot.readWord }
            try #require(reads.count == 1)
            try reads[0].tap()
        }

        #expect(shell.shell.reading == notice.id)
        let still = try await Self.current(in: shell)
        #expect(still != nil, "pressing Read closed the invoice")
    }

    /// ovation#548. Remind and Send a copy reach the screen through the one reviewer
    /// RootView is given, the same one Review uses, so a reminder cannot travel a
    /// second sending path (L263).
    @Test("with a reviewer, the screen is given Remind and Send a copy")
    func theReviewerReachesResend() async throws {
        let draft = try Self.draft()
        let container = draft.context.container
        let noon = Self.noon
        let reviewer = InvoiceReviewer(container: container, footer: { .fixed }, settingsFile: nil,
                                       makeSender: { _ in .failure(SenderUnavailable(sentence: "no")) },
                                       clock: { noon })
        let shell = try Self.shell(of: Self.window(draft, heard: Heard(), edits: InvoiceEditCommand(),
                                                   spying: false, reviewer: reviewer))
        ViewHosting.host(view: shell)
        defer { ViewHosting.expel() }
        let screen = try await Self.open(draft, in: shell)
        #expect(screen.resend != nil)
        #expect(screen.history != nil, "the shell holds the history pane")
    }

    /// ovation#556, PRD 51o. ONCE RECORD IS PRESSED THE HISTORY OPENS WITH THE NEW
    /// PAYMENT MARKED, and the mark clears when the history is closed. The writer here
    /// writes a real payment into the store the screen is read from, so what is
    /// marked is found by the same re-read the app does.
    @Test("recording a payment opens the history with that payment marked, and closing clears the mark")
    func recordingOpensTheHistory() async throws {
        let draft = try Self.draft()
        draft.shoot.shotUntil = ClockTime("20:00")
        draft.invoice.number = 1_123
        draft.invoice.recordSendState(.sent(route: .ovationSentIt, at: Self.noon))
        try draft.context.save()
        let context = draft.context
        let invoice = draft.invoice
        let shell = try Self.shell(of: Self.window(
            draft, heard: Heard(), edits: InvoiceEditCommand(), spying: false,
            writePayment: .some({ _, entry in
                let payment = Payment(client: invoice.client, amount: entry.amount,
                                      method: entry.method, receivedOn: entry.received)
                context.insert(payment)
                context.insert(PaymentAllocation(payment: payment, invoice: invoice, amount: entry.amount,
                                                 allocatedOn: entry.received,
                                                 source: .recordedWithThePayment))
                return nil
            }),
            writeCleared: .some({ _ in nil })))
        ViewHosting.host(view: shell)
        defer { ViewHosting.expel() }
        let screen = try await Self.open(draft, in: shell)
        #expect(screen.history?.isOpen == false, "the pane starts closed")

        try #require(screen.payment).record(PaymentEntry(amount: Money(dollars: 100), method: .zelle,
                                                         received: Self.today, press: UUID()))
        var history: InvoiceScreenView.HistoryControls?
        for _ in 0..<300 {
            history = try await Self.current(in: shell)?.history
            if history?.isOpen == true { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let opened = try #require(history)
        #expect(opened.isOpen, "recording a payment did not open the history")
        #expect(opened.marked.count == 1)
        let entries = try #require(try await Self.current(in: shell)).presenter.history.entries
        #expect(entries.filter { opened.marked.contains($0.id) }.map(\.what) == ["Payment recorded"])

        opened.toggle()
        var after: InvoiceScreenView.HistoryControls?
        for _ in 0..<300 {
            after = try await Self.current(in: shell)?.history
            if after?.isOpen == false { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(after?.isOpen == false)
        #expect(after?.marked.isEmpty == true, "closing the history left the payment marked")
    }
}
