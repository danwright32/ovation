// ovation#615. The one way this app draws a button with no chrome of its own.
//
// A PLAIN STYLE BUTTON HIT TESTS ONLY WHAT ITS LABEL PAINTS. A row whose
// background is clear paints its words and nothing else, so a click to the right
// of them went nowhere and said nothing. That is what Dan met in the rail on
// 2026-09-28: the current destination paints its highlight and answered across its
// width, and every other row answered only on its title, so it was the rows he
// was reaching for that felt broken.
//
// THE FIX IS A CONTENT SHAPE ON THE LABEL, and it has to be on the label: one on
// the button outside it is not what the plain style hit tests. So this style is
// the plain one with the shape added, and the shape is the label's own frame
// unless a caller names the shape it draws, as the rail does with its rounded
// highlight.
//
// A WORD MEANT TO BE PRESSED ON THE WORD IS NOT AN EXCEPTION. Its label's frame
// IS the word, so the shape adds nothing to it but the gaps between its letters,
// which were never meant to be dead either. That was decided site by site across
// the 21 plain buttons ovation#615 listed, and every one of them is a row, a chip
// or a word, so none needs the bare plain style.
//
// WHY A STYLE AND NOT A NOTE. There were 21 plain buttons and 9 content shapes,
// and the ones that had a shape had it because whoever drew them happened to
// remember. A behaviour each call site has to opt into cannot be enforced by
// reading the call sites (L621), so the shape lives here and
// `scripts/check-whole-target.sh` refuses a plain style button anywhere else in
// the app (L613).
import SwiftUI

struct WholeTarget<Area: Shape>: PrimitiveButtonStyle {
    /// The shape a click is taken across, in the label's own frame.
    let area: Area

    init(_ area: Area) {
        self.area = area
    }

    func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) {
            configuration.label.contentShape(area)
        }
        .buttonStyle(.plain)
    }
}

extension WholeTarget where Area == Rectangle {
    /// The label's whole frame, which is right for anything drawn square or not
    /// drawn at all.
    init() {
        self.init(Rectangle())
    }
}
