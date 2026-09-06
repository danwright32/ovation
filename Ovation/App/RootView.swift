import SwiftUI

/// Placeholder. Plan 1.13 replaces this with the single launch presenter, which
/// is where every launch time condition (a foreign store, a second running copy,
/// a failed backup verification, export staleness, the queue state, and every
/// Problems entry) reaches Dan through ONE surface holding the identity of what
/// is showing, rather than through independent booleans that silently drop all
/// but one.
struct RootView: View {
    var body: some View {
        Text(OvationBuild.displayName)
            .padding()
            .frame(minWidth: 480, minHeight: 320)
    }
}
