import SwiftUI

/// A list drawn as it is while it fits, and scrolling inside its own box once it does
/// not (ovation#393).
///
/// Dan, 2026-09-30: a fixed size surface whose content includes a list that grows for
/// ever fits its FIXED part without scrolling, and the list scrolls inside its own box
/// once long. So a surface is never scrolled whole to reach its own foot, and a short
/// list sits where it always sat rather than being stretched into a box that takes
/// every point left over, which a bare ScrollView does.
///
/// ONE COMPONENT, used by the backups pane and the review sheet's recipients, so the
/// two cannot come to scroll differently (L613).
struct ScrollsWhenLong<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
    }
}
