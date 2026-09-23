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
// screen is written against.
import SwiftData
import SwiftUI

struct AddingLineRow: View {

    /// The type chosen, or nil while it is still being chosen.
    let chosen: InvoiceScreenPresenter.ServiceChoice?
    /// The types on offer, as the one list draws them.
    let types: [PopupList.Choice]
    /// What has been typed into the amount.
    @Binding var amount: String
    /// Whether the list offers to make a new type. NIL DROPS THE ENTRY rather
    /// than offering a word that opens nothing (L109).
    var askNewType: (() -> Void)?
    let choose: (PopupList.Choice) -> Void
    let commit: () -> Void

    /// The design record's own column widths, taken from the screen so the row
    /// being filled in lines up with the rows above it (L553).
    let columns: (hours: CGFloat, rate: CGFloat, amount: CGFloat,
                  gap: CGFloat, side: CGFloat)

    @State private var listIsOpen = false
    /// Whether the amount is being typed into, so that leaving it commits.
    @FocusState private var amountIsFocused: Bool

    var body: some View {
        HStack(spacing: columns.gap) {
            if let chosen {
                Text(chosen.name)
                    .font(.system(size: 13.5))
                    .foregroundStyle(OvationPalette.ink)
            } else {
                chooser
            }
            Spacer(minLength: 0)
            // THE HOURS AND THE RATE ARE BLANK, never zero. A flat charge has
            // neither, and a quantity of nothing is not drawn (PRD 5.1b).
            Color.clear.frame(width: columns.hours, height: 1)
            Color.clear.frame(width: columns.rate, height: 1)
            // NO PLACEHOLDER READING 0.00, for the same reason: a figure the
            // screen has not been given is never drawn as one.
            TextField("", text: $amount)
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
                // shape the rest of this screen is careful about (L628).
                //
                // THE TRIGGER IS NOT COVERED BY A VIEW TREE TEST, for the same
                // reason the list in the popover above is not: focus is the
                // platform's and a view tree cannot move it. What it CALLS is the
                // same `commit` the Enter case drives, and that is covered
                // (L442).
                .onChange(of: amountIsFocused) { wasFocused, isFocused in
                    if wasFocused && !isFocused { commit() }
                }
        }
        .padding(.horizontal, columns.side)
        .padding(.vertical, 7)
        .background(OvationPalette.sunk)
        .overlay(alignment: .bottom) { Divider().overlay(OvationPalette.ruleSoft) }
    }

    /// THE TYPE IS CHOSEN IN THE ROW'S OWN DESCRIPTION CELL, and it reads as a
    /// control at rest rather than on hover only (L49). Its triangle is drawn
    /// rather than typed, so nothing between here and a render can mangle it.
    private var chooser: some View {
        Button { listIsOpen.toggle() } label: {
            HStack(spacing: 6) {
                Text("Choose a type")
                Triangle()
                    .fill(OvationPalette.faint)
                    .frame(width: 8, height: 5)
            }
            .font(.system(size: 13.5))
            .foregroundStyle(OvationPalette.soft)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(OvationPalette.chrome)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(OvationPalette.rule, lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose a type")
        .popover(isPresented: $listIsOpen, arrowEdge: .bottom) {
            PopupList(choices: types,
                      asks: askNewType == nil ? nil : "New type...",
                      ask: {
                          listIsOpen = false
                          askNewType?()
                      },
                      choose: { row in
                          listIsOpen = false
                          choose(row)
                      })
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
