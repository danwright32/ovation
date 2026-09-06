import SwiftUI

// The entry point, and the ONE file the pure test target cannot compile in,
// because it carries @main. Everything the tests need lives elsewhere so that
// the pure suite is not dragged behind the entry point (project.yml).
//
// Ovation is single window ON PURPOSE (PRD 41b). A flag on shared application
// state is presented once per SURFACE bound to it, so a second window would put
// up a second copy of every launch notice and dismissing one would leave the
// other standing. Plan 1.13 builds the single launch presenter on top of this,
// and the menu bar item and any URL handler bring THIS window forward rather
// than opening another.
@main
struct OvationApp: App {
    var body: some Scene {
        Window(OvationBuild.displayName, id: OvationBuild.mainWindowID) {
            RootView()
        }
    }
}
