// ovation#457, PRD 5.4a. The discount's own line on the invoice.
//
// IT SITS ON ITS OWN LINE BENEATH THE ROW, and that is measured rather than
// chosen. `docs/design/invoice.html` records that every totals row keeps ONE
// WIDTH so that every figure keeps one right edge, that these controls do not
// fit that row's 208px label column, and that two earlier attempts widened the
// row and put the discount's figure off the shared edge, once 24px left and once
// 24px right, both measured.
//
// THE RECORD SAYS THIS LINE'S OWN DESIGN WAS NEVER PUT TO DAN. It was chosen to
// solve that layout problem and no alternative was drawn beside it, so it is one
// of the things ovation#111 still holds open. What is built here is what is
// drawn there, and changing it is a design round rather than a fix.
//
// ITS STATE IS THE SCREEN'S, so it takes values and hands back intentions, the
// same arrangement `AddingLineRow` and `PopupList` use: a view tree test cannot
// press a control and then see what a screen's `@State` did with it, so a line
// drawn from that state is a line nothing can check (L442).
//
// REMOVING IS OFFERED HERE AND NOWHERE ELSE. Round 5 put the rare actions in the
// menu and settled that the menu ADDS a discount and never removes one, because
// by then the discount is on screen carrying its own controls and the menu copy
// would be the same action twice, further from the thing it acts on (L605).
import SwiftUI

struct DiscountLine: View {

    /// Which unit is in force. A percentage of the PRE TAX subtotal, or an
    /// amount off it (PRD 5.4a).
    let isPercent: Bool
    @Binding var value: String
    /// The width every totals row keeps, so this line's right edge is the one
    /// every figure above it already uses (L553).
    let width: CGFloat
    let setUnit: (Bool) -> Void
    let commit: () -> Void
    let remove: () -> Void

    @FocusState private var valueIsFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Spacer(minLength: 0)
            Text("Discount")
                .font(.system(size: 12))
                .foregroundStyle(OvationPalette.quiet)
            unit("%", wanted: true)
            unit("$", wanted: false)
            TextField("", text: $value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                .accessibilityLabel("Discount value")
                .focused($valueIsFocused)
                .onSubmit(commit)
                // LEAVING THE FIELD COMMITS IT, the same as every other typed
                // figure on this screen: without it, typing a value and clicking
                // anywhere else loses it and says nothing (L628). Focus is the
                // platform's and a view tree cannot move it, so what is covered
                // is the `commit` this calls (L442).
                .onChange(of: valueIsFocused) { wasFocused, isFocused in
                    if wasFocused && !isFocused { commit() }
                }
            Button("Remove", action: remove)
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(OvationPalette.faint)
        }
        .frame(width: width, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 2)
    }

    /// One of the two units, drawn as a control at rest and marked when it is the
    /// one in force.
    ///
    /// THE MARK IS SAID AS WELL AS DRAWN. A state carried only by a colour is a
    /// state some readers never get (PRD 47, L20).
    private func unit(_ word: String, wanted: Bool) -> some View {
        let inForce = isPercent == wanted
        return Button { setUnit(wanted) } label: {
            Text(word)
                .font(.system(size: 12))
                .foregroundStyle(inForce ? OvationPalette.background : OvationPalette.quiet)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(inForce ? OvationPalette.accent : OvationPalette.chrome)
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(inForce ? OvationPalette.accent : OvationPalette.rule,
                                    lineWidth: 1))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // SAID TWICE AND DERIVED ONCE. The trait is what VoiceOver reads as a
        // selection and the value is what it announces, and both come from the
        // one `inForce` above, so they cannot disagree (L544). The value is also
        // the only one of the two a view tree test can read, which is why the
        // case asserts on it.
        .accessibilityAddTraits(inForce ? [.isButton, .isSelected] : [.isButton])
        .accessibilityValue(inForce ? "in force" : "not in force")
    }
}
