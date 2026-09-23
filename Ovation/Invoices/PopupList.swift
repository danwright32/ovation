// ovation#457. The one popup list, used twice.
//
// THE DESIGN RECORD SAYS IT IS ONE OBJECT AND SAYS WHY. `docs/design/invoice.html`
// builds the service types that hang off a line's description cell and the
// payment terms that hang off the foot from a single `popList`, and records that
// they were built as two, `.typelist` and `.duelist`, and merged in the same
// change rather than left as a cleanup, "because the second copy is what makes
// the first stop being the single site" (L370, L613).
//
// IT IS A SHORT LIST OF CHOICES WITH AN OPTIONAL TRAILING ENTRY THAT ASKS A
// QUESTION. That shape is the whole of what the two share, and the three dots on
// that entry say a question is coming, which is the macOS convention and is true
// at both sites: each one opens a panel rather than doing anything.
//
// IT SETS ITS OWN FACE RATHER THAN INHERITING. Both call sites sit inside
// something with a face of its own, the foot being monospace, and the design
// record records the consequence of inheriting: the terms were silently drawn in
// the wrong one. This screen's rule is words in Archivo and figures in the mono
// face, and a list carries both.
//
// AND IT SETS ITS OWN APPEARANCE. Each site presents it in a popover, which is
// its own window and does not inherit the screen's, so `AppearanceParityTests`
// cannot capture it (PRD 43, ovation#474).
import SwiftUI

struct PopupList: View {

    /// One row: the words, and the quiet figure beside them where the choice is
    /// only meaningful as something it produces.
    struct Choice: Identifiable, Equatable {
        let id: String
        let says: String
        /// Empty where the choice is only its name, which is every service type.
        /// A row with nothing to put here draws no second column rather than an
        /// empty one holding the space open (L626).
        var beside: String = ""
        /// Whether this is the one already in force.
        var isCurrent: Bool = false
    }

    let choices: [Choice]
    /// The trailing entry's words, or nil where this list asks nothing.
    var asks: String?
    /// What that entry does. Both call sites open a panel.
    var ask: (() -> Void)?
    let choose: (Choice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(choices) { choice in
                Button { choose(choice) } label: { row(choice) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(spoken(choice))
                    .accessibilityAddTraits(choice.isCurrent ? [.isButton, .isSelected]
                                                             : [.isButton])
            }
            if let asks, let ask {
                Divider().overlay(OvationPalette.rule).padding(.vertical, 4)
                Button(asks, action: ask)
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(OvationPalette.soft)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 5)
            }
        }
        .padding(.vertical, 5)
        .frame(minWidth: 186, alignment: .leading)
        .background(OvationPalette.chrome)
        .ovationAppearance()
    }

    /// THE WORDS AND THE FIGURE KEEP THEIR OWN FACES, which is this screen's rule
    /// rather than a choice made here.
    private func row(_ choice: Choice) -> some View {
        HStack(spacing: 18) {
            Text(choice.says)
                .font(.system(size: 13))
                .foregroundStyle(OvationPalette.ink)
            if !choice.beside.isEmpty {
                Spacer(minLength: 12)
                Text(choice.beside)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(OvationPalette.faint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// One utterance for a row that draws as two, so a screen reader is not read
    /// the words and the figure as separate things (PRD 47).
    private func spoken(_ choice: Choice) -> String {
        choice.beside.isEmpty ? choice.says : "\(choice.says), \(choice.beside)"
    }
}
