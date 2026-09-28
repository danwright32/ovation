// ovation#568 and ovation#482. The Clients screen, drawn: the names on the left,
// one client's page on the right (shape C of ovation#98).
//
// TRANSLATED FROM docs/design/clients.html, NOT COPIED, the way the roster pass
// is: type is the system's, an action is `ActionWord`, and the two values that
// are controls (Sales tax and Payment terms) take round D's treatment, a quiet
// ruled box, so they read as one kind of thing (PRD 51j, 51j1).
//
// THE SCREEN IS READ, NOT ACTED ON, apart from the facts that belong to the
// client rather than to any invoice: the standing payment terms (PRD 51j), the
// tax status (PRD 51j1) and a shared address said to be correct (PRD 38c).
// Applying held money lives on the invoice (PRD 14g).
//
// IT HOLDS NO STORE. Every write is a closure the shell hands it, which reaches an
// actor, and the page is re-derived from the store after the write lands (PRD
// 51l, L14). What it holds itself is what is open on the page and whether a write
// is in flight.
//
// IT NAMES CLIENTS ON SCREEN AND NOWHERE ELSE (docs/PRIVACY-FLOOR.md).
import SwiftData
import SwiftUI

struct ClientsView: View {
    let presenter: ClientsPresenter
    @Binding var selected: UUID?

    /// Recording a tax status, the same write the roster pass and the invoice
    /// screen use (`ClientTaxStatusWriter`). Nil where nothing can write, and then
    /// the value is drawn as a value with nothing to press.
    var writeTax: ((PersistentIdentifier, TaxStatus) async -> String?)?
    /// Recording the standing payment terms.
    var writeTerm: ((PersistentIdentifier, PaymentTerm) async -> String?)?
    /// Saying a shared address is correct.
    var acknowledgeShared: ((PersistentIdentifier) async -> String?)?

    /// What is open on the page. Starts from the caller's value so a test and the
    /// shot suite can draw the question state; the app starts it closed.
    @State var interaction = ClientPageInteraction()
    /// Which write is in flight, said beside the thing it changes (L608).
    @State private var saving: Saving?
    /// Why the last write did not land, said where it was pressed (L109).
    @State private var refused: String?
    /// How wide the page is drawn, read back from layout, because an invoice row
    /// changes shape with the window (PRD 47c). Zero is unknown, not narrow.
    @State private var pageWidth: CGFloat = 0

    enum Saving: Equatable { case tax, term, shared }

    /// The names column, the design record's fixed 240.
    static let namesWidth = OvationWindow.clientNamesWidth

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                names
                Divider().overlay(OvationPalette.rule)
                ScrollView {
                    if let page = presenter.page(for: selected) {
                        pageView(page)
                            .id(page.clientID)
                    }
                }
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { pageWidth = $0 }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OvationPalette.background)
        // A FRESH PAGE, FRESH STATE: a question asked about one client can never be
        // answered on another.
        .onChange(of: presenter.page(for: selected)?.clientID) { _, _ in
            interaction = ClientPageInteraction()
            refused = nil
        }
        // SAID TO VOICEOVER AS IT APPEARS (L20): the question, a write in flight, and
        // a refusal, none of which move the focus on their own.
        .onChange(of: interaction.asking?.sentence) { _, said in
            if let said { AccessibilityNotification.Announcement(said).post() }
        }
        .onChange(of: saving) { _, now in
            if now != nil { AccessibilityNotification.Announcement("Saving").post() }
        }
        .onChange(of: refused) { _, said in
            if let said { AccessibilityNotification.Announcement(said).post() }
        }
        .ovationAppearance()
    }

    // MARK: the bar across the top

    private var toolbar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Destination.clients.title)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(OvationPalette.ink)
            Spacer()
            Text(presenter.count == 1 ? "1 client" : "\(presenter.count) clients")
                .font(.system(size: 12))
                .foregroundStyle(OvationPalette.quiet)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(OvationPalette.rule).frame(height: 1) }
    }

    // MARK: the names

    private var names: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(presenter.rows) { row in
                    nameRow(row)
                }
            }
        }
        .frame(width: Self.namesWidth)
    }

    private func nameRow(_ row: ClientsPresenter.NameRow) -> some View {
        let isHere = row.clientID == presenter.page(for: selected)?.clientID
        let held = presenter.heldFigure(on: row, selected: selected)
        return Button {
            selected = row.clientID
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.name)
                    .font(.system(size: 14, weight: isHere ? .semibold : .regular))
                    .foregroundStyle(OvationPalette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if let held {
                    Text(held)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(OvationPalette.soft)
                        .fixedSize()
                }
            }
            .padding(.leading, 24)
            .padding(.trailing, 16)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHere ? OvationPalette.selection : Color.clear)
            // A RULE DRAWN AS A RECTANGLE, never a Divider: a Divider takes its
            // direction from the stack it lands in, and in this row's HStack it drew
            // a vertical line through every name (seen in the first capture).
            .overlay(alignment: .bottom) {
                Rectangle().fill(OvationPalette.ruleSoft).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(held.map { "\(row.name), holding \($0)" } ?? row.name)
        .accessibilityAddTraits(isHere ? [.isButton, .isSelected] : [.isButton])
    }

    // MARK: one client

    private func pageView(_ page: ClientsPresenter.Page) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(page.name)
                .font(.system(size: 25, weight: .regular, design: .serif))
                .foregroundStyle(OvationPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                fact("Invoices go to") { goesTo(page) }
                if page.addressProblem != nil || page.recipients != nil {
                    fact("") {
                        Text(page.addressProblem ?? page.recipients ?? "")
                            .foregroundStyle(OvationPalette.faint)
                    }
                }
                if let bookedBy = page.bookedBy {
                    fact("Booked by") { Text(bookedBy).foregroundStyle(OvationPalette.ink) }
                }
                fact("Sales tax") { taxValue(page) }
                fact("Payment terms") { termValue(page) }
            }

            if let refused {
                Text(refused)
                    .font(.system(size: 12.5))
                    .foregroundStyle(OvationPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let question = interaction.asking {
                taxQuestion(question, on: page)
            }

            if page.sharedAddressAsks {
                sharedAddress(page)
            }

            if page.held != nil || page.referral != nil {
                money(page)
            }

            if !page.invoices.isEmpty {
                invoices(page)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func fact(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(OvationPalette.faint)
                .frame(width: 128, alignment: .leading)
            value()
            Spacer(minLength: 0)
        }
        .font(.system(size: 13.5))
    }

    @ViewBuilder
    private func goesTo(_ page: ClientsPresenter.Page) -> some View {
        if let value = page.goesTo {
            if page.addressProblem != nil {
                // The record's `.field.bad`: the value as it is, boxed, quiet.
                Text(value)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(OvationPalette.quiet)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(OvationPalette.quiet))
            } else {
                Text(value)
                    .foregroundStyle(OvationPalette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        } else {
            Text("Nothing recorded").foregroundStyle(OvationPalette.faint)
        }
    }

    // MARK: the sales tax, corrected here (ovation#482, PRD 51j1)

    /// THE VALUE IS THE CONTROL (Dan, 2026-09-26, "Follow the terms precedent"):
    /// pressing it opens the tax chip pair beside it, the invoice's chip (PRD 5a2).
    @ViewBuilder
    private func taxValue(_ page: ClientsPresenter.Page) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ValueButton(says: page.taxSaid, isAbsent: page.taxStatus == .neverRecorded,
                        isOpen: interaction.taxIsOpen, openSaid: "Answers showing",
                        press: writeTax == nil || saving != nil ? nil : {
                            interaction.pressTaxValue()
                            refused = nil
                        },
                        spoken: "Sales tax, \(page.taxSaid)")
            if interaction.taxIsOpen {
                TaxAnswerChips(answers: TaxStatus.answers) { answer in
                    if let now = interaction.pressAnswer(answer, on: page) {
                        record(now, on: page)
                    }
                }
            }
            if saving == .tax { savingWord }
        }
    }

    /// Before a recorded status changes, Ovation says how many sent invoices were
    /// charged under it. The sentence and its two words are the design record's
    /// drafting, approved by Dan on 2026-09-27 (ovation#600).
    private func taxQuestion(_ question: ClientsPresenter.TaxQuestion,
                             on page: ClientsPresenter.Page) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.sentence)
                .font(.system(size: 13))
                .foregroundStyle(OvationPalette.soft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                ActionWord(word: question.change, size: 12.5, press: {
                    if let status = interaction.change() { record(status, on: page) }
                })
                ActionWord(word: question.keep, size: 12.5, press: { interaction.keep() })
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OvationPalette.sunk)
        .overlay(Rectangle().stroke(OvationPalette.rule))
    }

    private func record(_ status: TaxStatus, on page: ClientsPresenter.Page) {
        guard let writeTax else { return }
        saving = .tax
        refused = nil
        Task {
            refused = await writeTax(page.storeID, status)
            saving = nil
        }
    }

    // MARK: the standing payment terms (PRD 51j)

    @ViewBuilder
    private func termValue(_ page: ClientsPresenter.Page) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            ValueButton(says: page.paymentTerm.says, isAbsent: false,
                        isOpen: interaction.termsAreOpen, openSaid: "Terms showing",
                        press: writeTerm == nil || saving != nil ? nil : {
                            interaction.termsAreOpen.toggle()
                            refused = nil
                        },
                        spoken: "Payment terms, \(page.paymentTerm.says)")
                .popover(isPresented: $interaction.termsAreOpen, arrowEdge: .bottom) {
                    PopupList(choices: PaymentTerms.all.map {
                        PopupList.Choice(id: $0.says, says: $0.says,
                                         isCurrent: $0 == page.paymentTerm)
                    }, choose: { choice in
                        interaction.termsAreOpen = false
                        // Found back by the term's own words, never by position (L237).
                        guard let term = PaymentTerms.all.first(where: { $0.says == choice.id }),
                              term != page.paymentTerm, let writeTerm else { return }
                        saving = .term
                        Task {
                            refused = await writeTerm(page.storeID, term)
                            saving = nil
                        }
                    })
                }
            if saving == .term { savingWord }
        }
    }

    private var savingWord: some View {
        Text("Saving")
            .font(.system(size: 12))
            .foregroundStyle(OvationPalette.quiet)
    }

    // MARK: a shared address (PRD 38c)

    private func sharedAddress(_ page: ClientsPresenter.Page) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Another client uses this address too.")
                .font(.system(size: 13))
                .foregroundStyle(OvationPalette.soft)
            Spacer(minLength: 0)
            if saving == .shared {
                savingWord
            } else {
                ActionWord(word: "That is correct", size: 12.5,
                           press: acknowledgeShared == nil || saving != nil ? nil : {
                               guard let acknowledgeShared else { return }
                               saving = .shared
                               refused = nil
                               Task {
                                   refused = await acknowledgeShared(page.storeID)
                                   saving = nil
                               }
                           })
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(OvationPalette.sunk)
        .overlay(Rectangle().stroke(OvationPalette.rule))
    }

    // MARK: the two balances (PRD 14f, 14l)

    /// TWO BOXES, TOLD APART BY THEIR FIGURES: the money face for dollars and the
    /// body face for hours (round A). A row holding one box keeps the two box
    /// geometry, so the row does not change shape with its contents.
    private func money(_ page: ClientsPresenter.Page) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let held = page.held {
                box(label: "Money held") {
                    Text(held)
                        .font(.system(size: 19, weight: .medium, design: .monospaced))
                        .foregroundStyle(OvationPalette.ink)
                    if let said = page.heldSaid { note(said) }
                    ForEach(Array(page.arrivals.enumerated()), id: \.offset) { _, arrival in
                        HStack(alignment: .firstTextBaseline) {
                            note(arrival.words)
                            Spacer(minLength: 10)
                            Text(arrival.amount)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(OvationPalette.faint)
                        }
                    }
                }
            }
            if let referral = page.referral {
                box(label: "Referral credit") {
                    Text(referral)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(OvationPalette.ink)
                    note("Earned by referring. Comes off an invoice in its own block above the subtotal")
                }
            }
            if page.held == nil || page.referral == nil {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
    }

    private func box(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10.5, weight: .bold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(OvationPalette.faint)
            content()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OvationPalette.sunk)
        .overlay(Rectangle().stroke(OvationPalette.rule))
    }

    private func note(_ said: String) -> some View {
        Text(said)
            .font(.system(size: 11.5))
            .foregroundStyle(OvationPalette.faint)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: the invoices

    /// BELOW A 1020 POINT WINDOW THE SHOOT TAKES A LINE OF ITS OWN (Dan,
    /// 2026-09-26, ovation#110 round 2, PRD 47c), at this list's own width.
    private var shootUnderneath: Bool {
        pageWidth > 0 && OvationWindow.putsClientShootUnderneath(pageWidth: pageWidth)
    }

    private enum Column {
        static let number: CGFloat = 44
        static let date: CGFloat = 120
        static let amount: CGFloat = 92
        static let status: CGFloat = 108
        static let gap: CGFloat = 12
    }

    private func invoices(_ page: ClientsPresenter.Page) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Invoices")
                .font(.system(size: 10.5, weight: .bold))
                .textCase(.uppercase)
                .kerning(1.3)
                .foregroundStyle(OvationPalette.faint)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(OvationPalette.rule).frame(height: 1) }
            ForEach(page.invoices) { line in
                invoiceRow(line)
            }
        }
    }

    private func invoiceRow(_ line: ClientsPresenter.InvoiceLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if shootUnderneath {
                shoot(line)
                narrowFigures(line)
            } else {
                wideFigures(line)
            }
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(OvationPalette.ruleSoft).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    /// Under the shoot, at the half screen: the date at its own width and the room
    /// after it, so no date is ever cut (the fixed columns cut "14 Nov 2026" at 860
    /// in the second capture).
    private func narrowFigures(_ line: ClientsPresenter.InvoiceLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Column.gap) {
            figure(line.number).frame(width: Column.number, alignment: .leading)
            figure(line.date).fixedSize()
            Spacer(minLength: 0)
            // FIXED ON THE RIGHT, so the amounts still stand in one column down the
            // list; a little narrower than the wide row's, which is what makes room.
            amount(line).frame(width: 84, alignment: .trailing)
            status(line).frame(width: 100, alignment: .trailing)
        }
    }

    private func amount(_ line: ClientsPresenter.InvoiceLine) -> some View {
        Text(line.amount)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(OvationPalette.ink)
    }

    private func status(_ line: ClientsPresenter.InvoiceLine) -> some View {
        Text(line.status)
            .font(.system(size: 12.5))
            .foregroundStyle(OvationPalette.faint)
            .lineLimit(1)
    }

    private func wideFigures(_ line: ClientsPresenter.InvoiceLine) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: Column.gap) {
                figure(line.number).frame(width: Column.number, alignment: .leading)
                shoot(line).frame(maxWidth: .infinity, alignment: .leading)
                figure(line.date).frame(width: Column.date, alignment: .leading)
                amount(line).frame(width: Column.amount, alignment: .trailing)
                status(line).frame(width: Column.status, alignment: .trailing)
            }
    }

    private func shoot(_ line: ClientsPresenter.InvoiceLine) -> some View {
        Text(line.shoot)
            .font(.system(size: 13.5))
            .foregroundStyle(OvationPalette.ink)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func figure(_ said: String) -> some View {
        Text(said)
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(OvationPalette.soft)
            .lineLimit(1)
    }
}

/// Round D's treatment for a value that is a control: the value itself, in a
/// quiet ruled box, drawn the same for the Sales tax and the Payment terms so the
/// two read as one kind of thing (docs/design/clients.html `.termbtn, .taxval`).
/// With nothing to press it is drawn as the value alone.
private struct ValueButton: View {
    let says: String
    let isAbsent: Bool
    let isOpen: Bool
    /// What VoiceOver hears as the value's state while what it opens is showing.
    let openSaid: String
    let press: (() -> Void)?
    let spoken: String

    var body: some View {
        if let press {
            Button(action: press) {
                Text(says)
                    .font(.system(size: 13.5))
                    .foregroundStyle(isAbsent ? OvationPalette.faint : OvationPalette.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(OvationPalette.sunk))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(isOpen ? OvationPalette.accent : OvationPalette.rule))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spoken)
            // WHETHER IT IS OPEN, said (review of ovation#600, L20): the answers or
            // terms appearing beside it are otherwise silent to a screen reader.
            .accessibilityValue(isOpen ? openSaid : "Closed")
            .accessibilityAddTraits(.isButton)
        } else {
            Text(says)
                .font(.system(size: 13.5))
                .foregroundStyle(isAbsent ? OvationPalette.faint : OvationPalette.ink)
        }
    }
}
