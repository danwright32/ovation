// ovation#40, PRD 44a and 44. The window: the espresso rail, and whatever screen
// you are standing on.
//
// THE RAIL IS FULL HEIGHT AND CARRIES THE COLOUR (PRD 44). In the design file
// the traffic lights are drawn on it by hand; here the system draws them, which
// is one of the three web idioms the design record says must be translated
// rather than copied.
//
// THE CARD SAYS WHAT IS TRUE ON DAY ONE. PRD 46a's five counts are counts of
// INVOICES, and Ovation holds none, so the card says `Nothing waiting` rather
// than borrowing the invoice list's fixture numbers. A number in this card means
// this many things need you (PRD 46b), and drawing four that nothing can produce
// would break that promise on the first screen that ever states it.
//
// MONEY HELD IS NOT DRAWN AT ALL YET, and that is the zero rule rather than an
// omission: PRD 46b makes it a quantity, and a quantity of nothing is not drawn.
import SwiftData
import SwiftUI

struct ShellView: View {
    @Bindable var shell: ShellPresenter
    @Bindable var roster: RosterPresenter
    /// WHERE A LAUNCH NOTICE LANDS ONCE THE SHELL OWNS THE WINDOW. `RootView` is
    /// the one surface every launch time condition reaches Dan through
    /// (ovation#59), and this view REPLACES it, so without the status block at
    /// the foot of the rail a foreign store, a failed backup or a stale export
    /// would be raised, recorded, and seen by nobody (L242, L98).
    ///
    /// NOT OPTIONAL AND WITH NO DEFAULT, deliberately. A default would let a
    /// future call site forget the wiring and still compile, which is the whole
    /// shape of this failure (L168).
    @Bindable var problems: ProblemsStore

    /// The invoice list, or nil where it could not be read out of the store.
    /// NOT OPTIONAL BECAUSE IT IS OPTIONAL TO PASS: the nil means one thing only,
    /// that the read failed and a problem was raised for it.
    var invoices: InvoiceListPresenter?

    /// What Ovation is holding across every client, drawn under the card (PRD 46b),
    /// and nil where it is holding nothing, because a quantity of nothing is not
    /// drawn.
    var heldMoney: String?

    /// ovation#457. How to build the screen for a row, or nil where nothing can
    /// (every hosted test written before this, and every launch with no store).
    ///
    /// A CLOSURE RATHER THAN THE SOURCE ITSELF, so this view cannot reach a
    /// `ModelContext` even by accident: the resolution lives on
    /// `InvoiceListSource`, which owns the container (PRD 51l, ovation#440).
    var openInvoice: ((PersistentIdentifier) -> InvoiceScreenPresenter?)?

    /// ovation#457. Writing a time Dan typed, which is what makes a draft sendable
    /// (PRD 3c). Nil where nothing can write. The write itself is
    /// `ShootTimesWriter`; this view only says which shoot and which end.
    var writeTime: ((PersistentIdentifier, InvoiceScreenView.Edge, ClockTime?) async -> String?)?
    /// ovation#473. What saving a due date does, and what it says when it does
    /// not. Nil where this launch has no store to write to.
    var writeDueDate: ((PersistentIdentifier, BusinessDate) async -> String?)?
    /// ovation#457, PRD 5.5. Recording the client's sales tax status, which is
    /// the one question this screen asks about the client rather than the
    /// invoice. Nil where this launch has no store to write to.
    var writeTaxStatus: ((PersistentIdentifier, TaxStatus) async -> String?)?
    /// ovation#457, PRD 5.4. Adding a line of a chosen type at a typed amount,
    /// and making a service type from inside the invoice. Nil where this launch
    /// has no store to write to.
    var writeLine: ((PersistentIdentifier, PersistentIdentifier, Money) async -> String?)?
    var writeServiceType: ((String, Money?) async -> String?)?
    /// ovation#457, PRD 5.4a. Changing this invoice's discount, or taking it off
    /// when given nothing. Nil where this launch has no store to write to.
    var writeDiscount: ((PersistentIdentifier, Discount?) async -> String?)?
    /// What the Edit menu is allowed to offer about the invoice on screen. The
    /// menu is declared on the app, outside every view, so this is how what is
    /// open reaches it (ovation#457).
    var edits: InvoiceEditCommand?

    /// Which invoice is selected. It lives here rather than inside the list
    /// because coming back from an invoice has to find the row again (ovation#125).
    @State private var selectedInvoice: PersistentIdentifier?
    /// The invoice being worked on, or nil while the list is showing (ovation#457).
    @State private var openedInvoice: InvoiceScreenPresenter?
    /// Which one, so the screen can be built again after a write changes it.
    @State private var openedInvoiceID: PersistentIdentifier?
    /// Why the last due date was not saved, or nil. Held here rather than in the
    /// screen because the screen is rebuilt after every write.
    @State private var refusedDate: String?
    /// Why the last write was refused, or nil. A refusal here is a race (the row
    /// went, or the invoice was sent from elsewhere), because the field is not
    /// offered at all on an invoice that may not be edited. It is still SAID: a
    /// write that silently does nothing leaves typing it again as the only
    /// diagnosis (L109, L148).
    @State private var refusedWrite: String?
    /// Why the last tax status was not recorded, or nil. Held here for the same
    /// reason the refused date is: the screen is rebuilt after every write.
    @State private var refusedTax: String?
    /// Why the last line or service type was not written, or nil.
    @State private var refusedLine: String?

    /// What a destination with no screen behind it says about itself. A constant
    /// because a test counts them, and because the same words appear once per
    /// unbuilt entry and must not drift between them.
    static let notBuiltMark = "not built yet"

    var body: some View {
        HStack(spacing: 0) {
            rail
            content
        }
        .frame(minWidth: 900, minHeight: 620, alignment: .topLeading)
        .ovationAppearance()
    }

    // MARK: the rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 1) {
            card
            ForEach(shell.destinations, id: \.self) { destination in
                railItem(destination)
            }
            Spacer(minLength: 14)
            status
        }
        .padding(.horizontal, 9)
        .padding(.top, 34)
        .padding(.bottom, 12)
        .frame(width: 208, alignment: .topLeading)
        .background(OvationPalette.rail)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Needs you")
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .kerning(1.3)
                .foregroundStyle(OvationPalette.railCardHeading)
            Text("Nothing waiting")
                .font(.system(size: 12.5))
                .foregroundStyle(OvationPalette.railCardLine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(OvationPalette.railCardBackground)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(OvationPalette.railCardBorder))
        .padding(.horizontal, 3)
        .padding(.bottom, 10)
    }

    private func railItem(_ destination: Destination) -> some View {
        let isHere = destination == shell.selected
        return Button {
            shell.go(to: destination)
        } label: {
            HStack(spacing: 8) {
                Text(destination.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isHere ? OvationPalette.railOnText : OvationPalette.railItem)
                Spacer()
                if !destination.isBuilt {
                    // PRESENT AND SAYING SO (PRD 44a). A destination that is
                    // present and silent is a dead control nobody can ask about,
                    // and one that is simply absent teaches nothing (L49, L109).
                    Text(Self.notBuiltMark)
                        .font(.system(size: 10.5))
                        .foregroundStyle(OvationPalette.railDim)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHere ? OvationPalette.railOnBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(!destination.isBuilt)
    }

    // MARK: what is wrong, at the foot of the rail

    /// THE ZERO RULE, for the fifth surface it now governs. A rail with nothing
    /// wrong says nothing at all, rather than saying nothing is wrong in the one
    /// place reserved for things that are.
    @ViewBuilder
    private var status: some View {
        let open = problems.open
        if let first = open.first {
            VStack(alignment: .leading, spacing: 5) {
                Text(first.sentence)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(OvationPalette.railFault)
                    .fixedSize(horizontal: false, vertical: true)
                if let others = Self.othersSentence(open.count - 1) {
                    Text(others)
                        .font(.system(size: 11.5))
                        .foregroundStyle(OvationPalette.railDim)
                }
                Text("Ovation only looks while it is open.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(OvationPalette.railDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .overlay(alignment: .top) { Divider().overlay(OvationPalette.railStatusBorder) }
            .padding(.horizontal, 3)
        }
    }

    /// What the rail says about the ones behind the first. Nothing at all when
    /// there are none, because `0 other problems` is noise. Singular and plural
    /// are separate, because `1 other problems` is the kind of sentence that
    /// makes a person stop trusting the rest of the screen.
    static func othersSentence(_ others: Int) -> String? {
        switch others {
        case ..<1: return nil
        case 1: return "1 other problem"
        default: return "\(others) other problems"
        }
    }

    // MARK: what you are standing on

    /// Hands one typed time to the writer, then builds the screen again from the
    /// store.
    ///
    /// IT RE-READS RATHER THAN EDITING WHAT IS ON SCREEN. The presenter holds
    /// values, so the derived duration, the line's amount, the totals and the
    /// Review refusal all change together or not at all, and they come from the
    /// same read (L14). Editing the screen in place would be a second derivation
    /// of the same facts.
    private func typed(_ shoot: PersistentIdentifier, _ edge: InvoiceScreenView.Edge,
                       _ time: ClockTime?) async {
        refusedWrite = await writeTime?(shoot, edge, time)
        if let openedInvoiceID { openedInvoice = openInvoice?(openedInvoiceID) }
        publishWhatIsOpen()
    }

    /// The same shape for the due date: write, then re-read, so the foot and
    /// everything derived from the date change together or not at all (L14).
    private func dated(_ due: BusinessDate) async {
        guard let openedInvoiceID else { return }
        refusedDate = await writeDueDate?(openedInvoiceID, due)
        openedInvoice = openInvoice?(openedInvoiceID)
        publishWhatIsOpen()
    }

    /// The same shape again for the tax status: write, then re-read, so the tax
    /// row, the total, the question itself and the Review refusal all change
    /// together or not at all (L14). This is the one write on this screen that
    /// changes a fact about the CLIENT, so everything derived from it moves at
    /// once and none of it is edited in place.
    private func answered(_ client: PersistentIdentifier, _ status: TaxStatus) async {
        refusedTax = await writeTaxStatus?(client, status)
        if let openedInvoiceID { openedInvoice = openInvoice?(openedInvoiceID) }
        publishWhatIsOpen()
    }

    /// The same shape again for a line: write, then re-read, so the row, the
    /// money block and the Review refusal all change together or not at all
    /// (L14).
    private func lined(_ type: PersistentIdentifier, _ amount: Money) async {
        guard let openedInvoiceID else { return }
        refusedLine = await writeLine?(openedInvoiceID, type, amount)
        openedInvoice = openInvoice?(openedInvoiceID)
        publishWhatIsOpen()
    }

    /// And for a new service type, which changes what the list offers rather
    /// than the invoice, so the screen is rebuilt for the same reason.
    private func madeType(_ name: String, _ usual: Money?) async {
        refusedLine = await writeServiceType?(name, usual)
        if let openedInvoiceID { openedInvoice = openInvoice?(openedInvoiceID) }
        publishWhatIsOpen()
    }

    /// The same shape again for the discount: write, then re-read, so the line,
    /// the taxable figure, the total and the Review refusal all change together
    /// or not at all (L14).
    /// ADDRESSED BY THE INVOICE THE DECISION WAS MADE ABOUT, never by whatever
    /// is open when the write lands. The menu presses on the invoice it was
    /// describing, and using the screen's own id instead would act on a
    /// different one if it had changed in between (L166).
    private func discounted(_ invoice: PersistentIdentifier, _ discount: Discount?) async {
        refusedLine = await writeDiscount?(invoice, discount)
        guard let openedInvoiceID, openedInvoiceID == invoice else { return }
        openedInvoice = openInvoice?(openedInvoiceID)
        publishWhatIsOpen()
    }

    /// Tells the Edit menu what it is looking at.
    ///
    /// PUBLISHED FROM THE ONE PLACE THE SCREEN IS BUILT, so the menu can never
    /// describe an invoice that is no longer on screen: every path that changes
    /// what is open goes through `openedInvoice` and then through here (L14).
    private func publishWhatIsOpen() {
        edits?.open = openedInvoice?.editMenuFacts
        // WHAT THE MENU DOES IS GIVEN HERE, because writing and then re-reading
        // the screen is the shell's job: a menu that only wrote would change the
        // store and leave the invoice on screen describing what it used to be
        // (L14).
        edits?.addDiscount = writeDiscount == nil ? nil : { invoice, discount in
            Task { await discounted(invoice, discount) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch shell.selected {
        case .roster:
            RosterPassView(presenter: roster)
        case .invoices:
            // THE SCREEN THE WINDOW OPENS ON (ovation#49). `RosterLaunch` selects
            // this whenever the roster has nothing to ask, which since ovation#298
            // is always, so this is the first thing Dan sees.
            //
            // A LIST THAT COULD NOT BE READ IS NOT AN EMPTY LIST. When the fetch
            // threw, `InvoiceListSource` raised a problem and produced nothing,
            // and the rail's status block carries it; drawing the empty state here
            // would say every invoice is paid and cleared, on no evidence (L10).
            // ovation#457. THE INVOICE TAKES THE WHOLE CONTENT AREA (round 1), so
            // the list goes away while it is open rather than sitting beside it.
            // Coming back to a list you recognise, with its scroll position and
            // the row that moved, is ovation#125.
            if let open = openedInvoice {
                InvoiceScreenView(
                    presenter: open,
                    close: {
                        openedInvoice = nil
                        openedInvoiceID = nil
                        publishWhatIsOpen()
                    },
                    setTime: writeTime == nil ? nil : { shoot, edge, time in
                        Task { await typed(shoot, edge, time) }
                    },
                    setDueDate: writeDueDate == nil ? nil : { due in
                        Task { await dated(due) }
                    },
                    refusedDate: refusedDate,
                    refused: refusedWrite,
                    answerTax: writeTaxStatus == nil ? nil : { client, status in
                        Task { await answered(client, status) }
                    },
                    refusedTax: refusedTax,
                    addLine: writeLine == nil ? nil : { type, amount in
                        Task { await lined(type, amount) }
                    },
                    createType: writeServiceType == nil ? nil : { name, usual in
                        Task { await madeType(name, usual) }
                    },
                    refusedLine: refusedLine,
                    setDiscount: writeDiscount == nil ? nil : { discount in
                        guard let openedInvoiceID else { return }
                        Task { await discounted(openedInvoiceID, discount) }
                    })
            } else if let invoices {
                InvoiceListView(presenter: invoices, heldMoney: heldMoney,
                                selected: $selectedInvoice,
                                open: openInvoice == nil ? nil : { id in
                                    openedInvoiceID = id
                                    openedInvoice = openInvoice?(id)
                                    publishWhatIsOpen()
                                })
            } else {
                couldNotBeRead
            }
        case .expenses, .clients:
            // Reachable only from a test today, because `go(to:)` refuses an
            // unbuilt destination. It is drawn rather than left blank so that
            // the state has a sentence if it is ever reached (L10).
            VStack(alignment: .leading, spacing: 6) {
                Text(shell.selected.title)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(OvationPalette.ink)
                Text("This screen has not been built yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(OvationPalette.soft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .background(OvationPalette.background)
        }
    }

    /// The state where the store opened and its invoices did not come out of it.
    /// It names what cannot be done rather than only that something failed, and it
    /// points at the rail, where the problem itself is written (L11, L111).
    private var couldNotBeRead: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The invoices could not be read")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(OvationPalette.ink)
            Text("Nothing can be sent, chased or marked paid until this is fixed. "
                 + "What went wrong is at the foot of the rail.")
                .font(.system(size: 13))
                .foregroundStyle(OvationPalette.soft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(OvationPalette.background)
    }
}
