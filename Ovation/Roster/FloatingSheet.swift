// ovation#547, PRD 48a. Every sheet in Ovation, drawn by one component.
//
// A SHEET FLOATS, CENTRED, EVERY CORNER ROUNDED, and never hangs from the title
// bar (Dan, 2026-09-25: a hanging sheet "makes the top flat and it's ugly"). A
// macOS system sheet always hangs, so no sheet is presented as one: each is drawn
// over the window it belongs to, by this. The payment sheet was the first built to
// the rule (ovation#510) and drew its own dim, card and shadow; the review sheet,
// the due date's panel and the new service type's panel followed, and all four
// share this rather than a copy of the shape each. `EverySheetFloatsTests` refuses
// a system sheet anywhere in the app's code.
//
// THE DIM TAKES EVERY CLICK OUTSIDE THE CARD, so nothing under a sheet can be
// pressed while it is open, and closes the sheet only where the sheet asks
// (`outside`). A sheet decides that for itself: the payment sheet closes on a
// click away when nothing was changed; the others never, as the system sheets
// they replace never did.
//
// ESCAPE IS `escape`, or nothing when it is nil, which is how a send in flight is
// held open (ReviewSendState.holdsTheSheetOpen).
import SwiftUI

struct FloatingSheet<Content: View>: View {

    /// What the card keeps clear of the title bar and of the window's foot. At the
    /// smallest window, 620 high with a 38 point title bar, the review sheet gives up
    /// height to keep it rather than touch either edge, as the design record draws.
    static var margin: CGFloat { 18 }
    /// Every corner, the payment sheet's and the design records' 10.
    static var cornerRadius: CGFloat { 10 }

    /// How far down the window the dim starts: the title bar's height where the
    /// sheet covers the whole window, whose title bar stays live, or 0 where it
    /// covers only the content below it.
    let below: CGFloat
    /// How dark the window behind goes. The design records draw the payment sheet's
    /// dim at .18 and the review sheet's at .26, the larger sheet over more of the
    /// window, both in the ink's warm brown. Two named depths rather than a number,
    /// so a sheet picks one the records drew.
    enum Dim {
        case light, deep

        var colour: Color {
            switch self {
            case .light: OvationPalette.ink.opacity(0.18)
            case .deep: OvationPalette.ink.opacity(0.26)
            }
        }
    }

    var dim: Dim
    var outside: (() -> Void)?
    var escape: (() -> Void)?
    let content: () -> Content

    init(below: CGFloat, dim: Dim = .light, outside: (() -> Void)? = nil,
         escape: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.below = below
        self.dim = dim
        self.outside = outside
        self.escape = escape
        self.content = content
    }

    var body: some View {
        ZStack {
            dim.colour
                .contentShape(Rectangle())
                .onTapGesture { outside?() }
                .accessibilityHidden(true)
                .padding(.top, below)
            content()
                .background(OvationPalette.background)
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
                .shadow(color: .black.opacity(0.28), radius: 17, y: 14)
                .accessibilityAddTraits(.isModal)
                .padding(Self.margin)
                .padding(.top, below)
        }
        .onExitCommand { escape?() }
    }
}
