// ovation#450, PRD 46a, 47. The product's one word that is a control, and the
// one way it is drawn when there is nothing behind it yet.
//
// THE IDIOM IS THE DESIGN RECORD'S. A control here is a WORD carrying an
// underline at rest rather than a button with a border, and it carries that
// underline at rest rather than on hover, because a control must look like a
// control before anybody points at it (L49).
//
// AND THE HONEST STATE IS QUIET, NOT DISABLED. ovation#450's subject is eight
// words on the invoice list, every one of them drawn semibold and underlined,
// and none of them doing what the word says. That is worse than a greyed
// control, because it does not look disabled: it looks exactly like the live
// control it will become, and a control that is dead with no reason beside it is
// one somebody presses repeatedly and then works around (L109, L148).
//
// So a word with nowhere to go is drawn in the ordinary weight and the faint
// colour, reading as what the row still needs rather than as an offer, and its
// screen reader label says NOT YET and why. The row still says the same word,
// which matters: PRD 46a counts the list's rows BY their action word, so what
// the word IS may not change, only how it is drawn and what pressing it does.
//
// ONE COMPONENT AND THE GUARD THAT KEEPS IT THE ONLY ONE, in the same change.
// There were two hand rolled copies of this treatment when it was written, the
// invoice screen's Review and the list's action, and a shared thing that
// converts the site in front of whoever built it and leaves the rest is not
// consolidation (L613). `scripts/check-one-action-word.sh` refuses an underline
// anywhere else in the app's Swift, which is the shape a third copy would have
// to declare in order to look the same.
import SwiftUI

struct ActionWord: View {

    let word: String
    /// The design record gives the list's action 12.5 and the invoice screen's
    /// Review 14, so the size is the caller's and everything else is not.
    let size: CGFloat
    /// What pressing it does, or nil where nothing does that yet.
    var press: (() -> Void)?
    /// Why it cannot be pressed, said after the word to a screen reader. A
    /// refusal that only sighted readers can see is not a refusal (PRD 47).
    var notYet: String?

    var body: some View {
        if let press {
            Button(word, action: press)
                .buttonStyle(.plain)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(OvationPalette.ink)
                .underline()
        } else {
            Text(word)
                .font(.system(size: size))
                .foregroundStyle(OvationPalette.faint)
                .accessibilityLabel(notYet.map { "\(word), not yet: \($0)" } ?? word)
        }
    }
}
