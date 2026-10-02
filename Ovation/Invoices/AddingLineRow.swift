// ovation#457, PRD 5.4. The row being filled in when a line is being added.
//
// IT IS ITS OWN VIEW BECAUSE ITS STATE IS THE SCREEN'S. The row exists, and the
// type may or may not be chosen yet, and both are states of this viewing rather
// than of the invoice. A view tree test cannot press a button and then see what
// `@State` did, so a row drawn from the screen's own state is a row nothing can
// check (L442). Taking its state as values makes every one of them a case, the
// same arrangement `PopupList` and `DueDateControl` use.
//
// THE TYPE FIRST, THEN THE AMOUNT, IN THE ROW ITSELF, which is the order the
// design record draws and the reason the word appends a row at all: the line is
// built where it is going to live.
//
// AND IT IS SUNK, which is what this screen already uses for a surface you are
// working on.
//
// THE AMOUNT COMMITS ON ENTER AND ON LEAVING THE FIELD, both, which the design
// record specifies. With only the first, typing an amount and clicking anywhere
// else loses it and says nothing, which is exactly the defect the rest of this
// screen is written against. Leaving it for the row's own type list is not
// leaving it (PRD 51q, `LineBeingAdded.leavingTheFieldCommits`).
//
// AND IT CAN BE LEFT WITHOUT BEING WRITTEN (ovation#489, Dan 2026-09-29). Escape
// closes the list if it is open and cancels the line if it is not (PRD 51s), and
// the Cancel word the screen draws in place of Add a line does the same for the
// mouse (PRD 51p). The type stays the chooser until the line is written, so a
// type chosen by mistake is changed rather than started again (PRD 51r, 51t).
import SwiftData
import SwiftUI

struct AddingLineRow: View {

    /// The line being added: its type, its amount and whether its list is open.
    @Binding var line: LineBeingAdded
    /// The types on offer, as the one list draws them.
    let types: [PopupList.Choice]
    /// Whether the list offers to make a new type. NIL DROPS THE ENTRY rather
    /// than offering a word that opens nothing (L109).
    var askNewType: (() -> Void)?
    let choose: (PopupList.Choice) -> Void
    let commit: () -> Void
    /// Escape, which the screen answers, because cancelling the line removes
    /// this row and the row cannot remove itself.
    let escape: () -> Void

    /// The design record's own column widths, taken from the screen so the row
    /// being filled in lines up with the rows above it (L553).
    let columns: (hours: CGFloat, rate: CGFloat, amount: CGFloat,
                  gap: CGFloat, side: CGFloat)

    /// THE INSET, 8 ON EVERY SIDE (Dan, 2026-09-29, PRD 51t). Measured in the
    /// design record before it: the chooser and the amount field sat 0 from the
    /// shaded row's edge while the row gave them 8 above and below, and Dan's
    /// screenshot showed the chooser's edge touching the column's. So the shading
    /// reaches this far past the columns on each side, and the controls stay on
    /// the column edges every other line uses.
    static let inset: CGFloat = 8

    /// Whether the amount is being typed into, so that leaving it commits.
    @FocusState private var amountIsFocused: Bool

    var body: some View {
        HStack(spacing: columns.gap) {
            chooser
            Spacer(minLength: 0)
            // THE HOURS AND THE RATE ARE BLANK, never zero. A flat charge has
            // neither, and a quantity of nothing is not drawn (PRD 5.1b).
            Color.clear.frame(width: columns.hours, height: 1)
            Color.clear.frame(width: columns.rate, height: 1)
            // NO PLACEHOLDER READING 0.00, for the same reason: a figure the
            // screen has not been given is never drawn as one.
            TextField("", text: $line.amount)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13.5, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .frame(width: columns.amount)
                .accessibilityLabel("Amount")
                .focused($amountIsFocused)
                .onSubmit(commit)
                // LEAVING THE FIELD COMMITS IT, which the design record specifies
                // alongside Enter, and without which typing an amount and
                // clicking elsewhere loses it with nothing said. That is the
                // shape the rest of this screen is careful about (L628). An
                // amount it cannot read leaves the row open, which `commit`
                // decides (PRD 51q).
                //
                // NOT WHILE THE ROW'S OWN LIST IS OPEN: the field loses focus to
                // the list, and a commit there would write the line while its
                // type was being changed (PRD 51r).
                .onChange(of: amountIsFocused) { wasFocused, isFocused in
                    if wasFocused && !isFocused && line.leavingTheFieldCommits { commit() }
                }
        }
        .padding(Self.inset)
        .background(OvationPalette.sunk)
        .padding(.horizontal, columns.side - Self.inset)
        .overlay(alignment: .bottom) { Divider().overlay(OvationPalette.ruleSoft) }
        // ESCAPE NEEDS SOMETHING IN THE ROW TO HOLD FOCUS, and the chooser is a
        // plain button, which a click does not focus on a Mac. So the field is
        // focused when the row appears and again when the list closes, which is
        // also where the next keystroke belongs: the type is chosen, and the
        // amount is what is left to type.
        .onExitCommand(perform: escape)
        .onAppear { amountIsFocused = true }
        .onChange(of: line.listIsOpen) { _, isOpen in
            if !isOpen { amountIsFocused = true }
        }
    }

    /// THE TYPE IS CHOSEN IN THE ROW'S OWN DESCRIPTION CELL, and it reads as a
    /// control at rest rather than on hover only (L49). Its triangle is drawn
    /// rather than typed, so nothing between here and a render can mangle it.
    ///
    /// A CHOSEN TYPE STAYS THE CHOOSER (Dan, 2026-09-29, PRD 51t), rejected
    /// against plain text that reopens the list, because plain text reads as a
    /// line already written and nothing at rest says it can be pressed. It is
    /// drawn SHADED WITH NO BORDER, a soft patch of the selection shade, rejected
    /// against an underlined name and a square outline: before a type is chosen
    /// the bordered button asks a question, and after it the shade says the answer
    /// can still be changed without asking it again.
    private var chooser: some View {
        Button { line.listIsOpen.toggle() } label: {
            HStack(spacing: 6) {
                Text(line.chosen?.name ?? "Choose a type")
                Triangle()
                    .fill(OvationPalette.faint)
                    .frame(width: 8, height: 5)
            }
            .font(.system(size: 13.5))
            .foregroundStyle(OvationPalette.soft)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(face)
        }
        .buttonStyle(WholeTarget(RoundedRectangle(cornerRadius: 5)))
        .accessibilityLabel(line.chosen == nil ? "Choose a type" : "Type")
        .accessibilityValue(line.chosen?.name ?? "")
        .popover(isPresented: $line.listIsOpen, arrowEdge: .bottom) {
            PopupList(choices: types,
                      asks: askNewType == nil ? nil : "New type...",
                      ask: {
                          line.listIsOpen = false
                          askNewType?()
                      },
                      choose: choose)
        }
    }

    /// The chooser's face: bordered while it asks, shaded once it is answered.
    @ViewBuilder private var face: some View {
        if line.chosen == nil {
            RoundedRectangle(cornerRadius: 5)
                .fill(OvationPalette.chrome)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(OvationPalette.rule, lineWidth: 1))
        } else {
            RoundedRectangle(cornerRadius: 5).fill(OvationPalette.selection)
        }
    }
}

/// The disclosure triangle, drawn rather than typed.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
