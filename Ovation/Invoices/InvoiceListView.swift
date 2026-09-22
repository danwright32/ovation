// ovation#49, PRD section 6, 46, 46a, 46d, 46f, 47. The one list, drawn.
//
// TRANSLATED FROM `docs/design/invoice-list.html`, NOT COPIED, on the same terms
// as `RosterPassView`: an action is a word rather than a button, the window chrome
// is the system's, and the type is the system's.
//
// IT DECIDES NOTHING. Every row, every word and every count comes from
// `InvoiceListPresenter`. A decision made inside a view body can only be checked
// by rendering it, and the states that matter on this screen are the ones no
// ordinary fixture produces.
//
// NO BAND HEADINGS (PRD 46, Dan 2026-09-06). The bands decide the ORDER and are
// not drawn: a heading reading "Send it today" over a row whose action word reads
// Send labelled one fact three times, and with one to three invoices per band
// nearly every other line on screen was a heading. What separates them is air and
// a rule, which is what the design record settled instead.
//
// NO RED ANYWHERE (PRD 45, Dan 2026-09-06: red "feels like something is wrong").
// An overdue invoice is not an error. Nothing failed and the money has not
// arrived, so lateness is an age in tabular figures, a duration rather than an
// alarm. Red belongs to the Problems store alone, and if this screen borrows that
// vocabulary the one surface that should alarm him has nothing left to say with.
import SwiftData
import SwiftUI

struct InvoiceListView: View {

    @Bindable var presenter: InvoiceListPresenter

    /// What Ovation is holding across every client, drawn above the waiting band.
    /// PRD 46d: the band exists because that money could settle more than one of
    /// these invoices and Ovation will not choose.
    var heldMoney: String?

    /// Which row is selected, owned by the caller because coming back to the list
    /// has to find it again (ovation#125).
    @Binding var selected: PersistentIdentifier?

    /// ovation#457. Opening the invoice, which is what a row IS for: ovation#111
    /// designed "the one you open when you click a row on the invoice list". Nil
    /// where nothing can open one, and then a row only selects, which is what it
    /// did before there was anywhere to go.
    ///
    /// IT IS NOT THE ACTION WORD. The eight words at the end of a row are
    /// ovation#450's question and are still unpressable; this is the row itself.
    var open: ((PersistentIdentifier) -> Void)?

    /// The column widths, from the design record's own `--cols`. Named here once
    /// so the header and every row are laid out by one declaration and cannot
    /// drift apart (L553).
    private enum Column {
        static let shootDate: CGFloat = 152
        static let number: CGFloat = 44
        static let amount: CGFloat = 88
        static let action: CGFloat = 84
        static let gap: CGFloat = 14
        static let sideMargin: CGFloat = 24
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnHeader
            if let said = presenter.returning(to: selected).sentence { rowHasGone(said) }
            if presenter.bands.isEmpty {
                empty
            } else {
                rows
            }
        }
        .background(OvationPalette.background)
        .ovationAppearance()
    }

    // MARK: the heads

    /// LAID OUT ON THE SAME WIDTHS AS THE ROWS, so a label cannot sit over the
    /// wrong column. A header aligned separately from its cells is two declarations
    /// of one fact, and they diverge while each site reads as correct (L553).
    private var columnHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Column.gap) {
            Text("Shoot").frame(maxWidth: .infinity, alignment: .leading)
            Text("Shoot date").frame(width: Column.shootDate, alignment: .leading)
            Text("Invoice").frame(width: Column.number, alignment: .leading)
            Text("Amount").frame(width: Column.amount, alignment: .trailing)
            Text("Action").frame(width: Column.action, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(OvationPalette.quiet)
        .padding(.horizontal, Column.sideMargin)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) { Divider().overlay(OvationPalette.rule) }
        .accessibilityHidden(true)
    }

    /// ovation#125. THE ROW YOU CAME BACK FOR IS NOT HERE, said rather than left
    /// to be worked out. An item that leaves must not simply vanish from under the
    /// eye: landing silently at the top of a rearranged list is indistinguishable
    /// from having never been anywhere (L426, L10).
    ///
    /// NEVER RED, and it carries no control. Nothing went wrong, and the list
    /// cannot offer a way back to a row that is not on it: the remedy is
    /// whichever action took it off, and that action says its own piece (L80,
    /// L112). It clears the moment another row is selected, because the notice is
    /// about the row you were on rather than a condition of the list.
    private func rowHasGone(_ said: String) -> some View {
        Text(said)
            .font(.system(size: 12.5))
            .foregroundStyle(OvationPalette.quiet)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Column.sideMargin)
            .padding(.vertical, 9)
            .background(OvationPalette.selection)
            .overlay(alignment: .bottom) { Divider().overlay(OvationPalette.ruleSoft) }
    }

    /// A POSITIVE STATEMENT ON THE HEALTHY DAY (L610). An empty list is the good
    /// outcome here, not a screen that failed to load, so it says which.
    private var empty: some View {
        Text("Nothing is waiting. Every invoice is sent, paid and cleared.")
            .font(.system(size: 13))
            .foregroundStyle(OvationPalette.soft)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Column.sideMargin)
    }

    // MARK: the list

    /// ovation#125. THE LIST COMES BACK TO THE ROW YOU OPENED, wherever it now
    /// is, rather than to the top. The invoice takes the whole screen (round 1 of
    /// ovation#111), so this list is BUILT AGAIN every time one is closed, and a
    /// scroll view built again starts at the top. At 24 invoices that already
    /// costs something, and working down a run of drafts gets worse the further
    /// down it goes, which is when a short fixture stops showing it.
    ///
    /// IT ANCHORS ON THE ROW RATHER THAN ON AN OFFSET, because acting inside the
    /// invoice can move it: an offset would come back to whatever has since taken
    /// that place, which reads as the list having reordered itself (L426).
    private var rows: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    bandsAndRows
                }
            }
            .onAppear {
                guard case .showing(let row) = presenter.returning(to: selected) else { return }
                scroll.scrollTo(row, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private var bandsAndRows: some View {
                ForEach(Array(presenter.bands.enumerated()), id: \.element.band) { index, band in
                    if band.band == .toPlace, let heldMoney {
                        waitingHead(heldMoney)
                    }
                    ForEach(band.rows) { row in
                        line(row, idle: Self.isIdle(band.band))
                            .id(row.invoiceID)
                    }
                    // THE WAITING BAND HAS TO END. It sits at the TOP, so without
                    // something closing it the whole list beneath reads as its
                    // contents, which is the fault the design record records being
                    // caught on 2026-09-10: a band saying 2 above a list that did
                    // not hold 2.
                    if band.band == .toPlace && index < presenter.bands.count - 1 {
                        Divider()
                            .overlay(OvationPalette.rule)
                            .padding(.top, 16)
                    }
                }
    }

    /// PRD 46d. What is held, above the invoices it could settle.
    private func waitingHead(_ held: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Column.gap) {
            Text("Money is waiting on a decision")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(held) held")
                .monospacedDigit()
        }
        .font(.system(size: 13))
        .foregroundStyle(OvationPalette.quiet)
        .padding(.horizontal, Column.sideMargin)
        .padding(.vertical, 9)
        .background(OvationPalette.chrome)
        .overlay(alignment: .bottom) { Divider().overlay(OvationPalette.ruleSoft) }
    }

    private func line(_ row: InvoiceListPresenter.Row, idle: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Column.gap) {
            who(row, idle: idle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.shootDate)
                .font(.system(size: 12.5, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(OvationPalette.soft)
                .frame(width: Column.shootDate, alignment: .leading)

            Text(row.number)
                .font(.system(size: 12.5, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(OvationPalette.soft)
                .frame(width: Column.number, alignment: .leading)

            // MONEY IS ALWAYS IN TABULAR FIGURES WITH ALIGNED DECIMALS (PRD 47),
            // because an amount that can be misread is the one thing this app
            // cannot afford. A word in this column is drawn quieter so it is not
            // read as a figure.
            Text(row.amount)
                .font(.system(size: 13.5, weight: Self.isWord(row.amount) ? .regular : .medium,
                              design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(idle || Self.isWord(row.amount)
                                 ? OvationPalette.quiet : OvationPalette.ink)
                .frame(width: Column.amount, alignment: .trailing)

            end(row)
                .frame(width: Column.action, alignment: .trailing)
        }
        .padding(.horizontal, Column.sideMargin)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // A SELECTED ROW IS MARKED BY A TINT ALONE AND NEVER A LEFT BAR (PRD 47),
        // which is both the macOS convention and a practical necessity once the
        // sidebar is dark.
        .background(selected == row.invoiceID ? OvationPalette.selection : Color.clear)
        .overlay(alignment: .bottom) { Divider().overlay(OvationPalette.ruleSoft) }
        // SELECTING AND OPENING ARE ONE GESTURE ON THIS ROW, because the design
        // record's list opens the invoice on a click and the selection is what
        // ovation#125 comes back to. A second gesture to open would leave the
        // first doing nothing a person can see (L49).
        .onTapGesture {
            selected = row.invoiceID
            open?(row.invoiceID)
        }
        // READ AS ONE LINE, because that is what it is (PRD 47). Five separate
        // labels would be read out as five unrelated fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(row))
        .accessibilityAddTraits(selected == row.invoiceID ? [.isButton, .isSelected] : .isButton)
    }

    /// THE SHOOT CARRIES THE WEIGHT, NOT THE CLIENT (Dan, 2026-09-09, settled
    /// against three alternatives and shown to him on a client holding three
    /// separate invoices for three shoots).
    private func who(_ row: InvoiceListPresenter.Row, idle: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(row.client)
                .font(.system(size: 13))
                .foregroundStyle(idle ? OvationPalette.quiet : OvationPalette.soft)
            Text(row.shoot)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(idle ? OvationPalette.quiet : OvationPalette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            if row.otherShoots > 0 {
                Text(Self.moreShoots(row.otherShoots))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(OvationPalette.faint)
            }
        }
    }

    /// The age and the action, at the end of the line.
    private func end(_ row: InvoiceListPresenter.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            if let age = row.age {
                Text(age)
                    .font(.system(size: 11.5, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(OvationPalette.faint)
            }
            if let action = row.action {
                // A CONTROL LOOKS LIKE A CONTROL AT REST, not only on hover and not
                // only in a tooltip (L49). It is a word rather than a button, which
                // is the design record's own idiom, and it carries the underline at
                // rest so it reads as pressable without one.
                //
                // AND A WORD WITH NOWHERE TO GO IS DRAWN QUIET (ovation#450). All
                // eight of these were drawn as controls and none of them did what
                // the word said, which is worse than a greyed control because it
                // looks exactly like the live one it will become (L109, L148).
                // Which words have somewhere to go is `Action.destination`, in one
                // place, beside the words themselves.
                //
                // THE ROW STILL OPENS ON A TAP, including a tap that lands on a
                // quiet word, and that is deliberate: opening the invoice is what
                // this ROW does everywhere along its length. What the quiet
                // treatment withdraws is the OFFER that the word itself will do
                // what it says.
                ActionWord(word: action, size: 12.5,
                           press: Self.press(action, on: row, open: open),
                           notYet: Self.notYet(action))
            }
        }
    }

    /// What pressing the action word does, or nil where nothing does what the
    /// word says yet.
    ///
    /// THE PREDICATE IS `Action.destination` READ ONCE, so whether the word is
    /// drawn as a control and what pressing it does are ONE answer rather than
    /// two that can disagree (L70).
    private static func press(_ action: String, on row: InvoiceListPresenter.Row,
                              open: ((PersistentIdentifier) -> Void)?)
        -> (() -> Void)? {
        guard let open, InvoiceListPresenter.Action.destination(of: action)
                == .theInvoiceScreen else { return nil }
        return { open(row.invoiceID) }
    }

    /// What a screen reader hears after a word that cannot be pressed. It names
    /// what is missing rather than saying "not available", because a refusal has
    /// to say what would change it (L111).
    private static func notYet(_ action: String) -> String? {
        guard InvoiceListPresenter.Action.destination(of: action) == nil else { return nil }
        return "there is no screen for this yet"
    }

    // MARK: what the words are

    /// The idle bands, drawn quieter. PRD section 6 gives them air rather than a
    /// label: there is nothing to do about any of them today.
    static func isIdle(_ band: InvoiceBand) -> Bool {
        switch band {
        case .draftShootAhead, .paidOrCleared, .cancelled: return true
        case .toPlace, .draftShootToday, .overdue, .draftNeedsSending,
             .checkNotCleared, .sayWhetherItWasSent, .sentAwaitingPayment: return false
        }
    }

    /// Whether the amount column is holding a word rather than a figure.
    private static func isWord(_ amount: String) -> Bool {
        amount.first.map { !$0.isNumber } ?? true
    }

    /// "+1 shoot", "+2 shoots". Singular and plural are separate, because
    /// "+1 shoots" is the kind of line that makes a person stop trusting the rest
    /// of the screen.
    static func moreShoots(_ count: Int) -> String {
        "+\(count) " + (count == 1 ? "shoot" : "shoots")
    }

    /// One sentence per row for a screen reader, in the order the line reads.
    static func spoken(_ row: InvoiceListPresenter.Row) -> String {
        var said = [row.client, row.shoot]
        if row.otherShoots > 0 { said.append(moreShoots(row.otherShoots)) }
        said.append(row.shootDate)
        said.append(row.number == "draft" ? "draft" : "invoice \(row.number)")
        said.append(row.amount)
        if let age = row.age { said.append("\(age) past due") }
        if let action = row.action { said.append(action) }
        return said.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
