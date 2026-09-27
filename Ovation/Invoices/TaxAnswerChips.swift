// ovation#480, PRD 5a2. The one way the tax status question's answers are drawn,
// wherever the question is asked.
//
// TWO SCREENS ASKED IT AND EACH DREW ITS OWN CHIP: the roster pass from the
// Clients record's `.chip` (3 by 11 padding, a 4 point radius, the soft ink on the
// page colour) and the invoice screen from the invoice record's `.taxpick`. Dan
// chose between them by looking, on 2026-09-26, with both treatments applied to
// both screens in the real windows, the roster at its 25 row fixture day and the
// invoice's totals block. Asked "Which chip should answer the tax status question
// on both screens?", he answered "Invoice chip".
//
// SO THIS IS `docs/design/invoice.html`'s `.taxpick`, QUOTED RATHER THAN INVENTED:
// 12 point type, 2 by 9 padding, a 5 point radius, the chrome fill, a 1 point
// rule and the full ink, and its hover, the selection fill. It is a real button,
// which the roster's old chip in the design record was not, so it keeps its hover
// and its focus ring (L49). Measured in the round: each roster row is centred on
// its chip, so rows go from 41.6 to 39.6 points and a 25 row pass is 50 shorter.
//
// ONE COMPONENT AND THE GUARD THAT KEEPS IT THE ONLY ONE, in the same change
// (L613). `scripts/check-one-tax-chip.sh` refuses any other Swift file that draws
// the answers itself, and any design file whose chip is not the invoice's. The
// Clients screen's correction of a status (PRD 51j1) is the third place the
// question is asked, and it is not built yet.
import SwiftUI

struct TaxAnswerChips: View {

    /// The answers, from the caller, which takes them from `TaxStatus.answers`:
    /// never two strings written here (L611).
    let answers: [TaxStatus]
    /// What pressing one does, handed the answer it names.
    let press: (TaxStatus) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(answers, id: \.self) { answer in
                Button { press(answer) } label: { Text(answer.exportLabel) }
                    .buttonStyle(TaxAnswerChipStyle())
            }
        }
    }
}

/// `.taxpick`, at rest, pointed at and focused.
private struct TaxAnswerChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration)
    }

    private struct Chip: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .foregroundStyle(OvationPalette.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering || configuration.isPressed
                              ? OvationPalette.selection : OvationPalette.chrome)
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(OvationPalette.rule, lineWidth: 1))
                )
                // The record's focus ring: 2 points of the accent, 1 point clear
                // of the chip's own edge.
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(OvationPalette.accent, lineWidth: 2)
                        .padding(-3)
                        .opacity(focused ? 1 : 0)
                )
                .fixedSize()
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
