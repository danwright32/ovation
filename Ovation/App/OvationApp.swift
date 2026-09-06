import SwiftUI

// The entry point, and the ONE file the pure test target cannot compile in,
// because it carries @main. Everything the tests need lives elsewhere so that
// the pure suite is not dragged behind the entry point (project.yml).
//
// Ovation is single window ON PURPOSE (PRD 41b). A flag on shared application
// state is presented once per SURFACE bound to it, so a second window would put
// up a second copy of every launch notice and dismissing one would leave the
// other standing (L238). The menu bar item and any URL handler bring THIS window
// forward rather than opening another.
@main
struct OvationApp: App {
    @State private var store: ProblemsStore
    @State private var presenter: LaunchPresenter

    init() {
        // A disposable launch gets a journal that writes nowhere, so nothing a
        // test or a throwaway run reports can reach Dan's real history
        // (plan 1.9). The refusal lives where the path is resolved, so this is
        // the only decision made here.
        let journal: ProblemsJournal = FileProblemsJournal.liveURL()
            .map { FileProblemsJournal(url: $0) } ?? InMemoryProblemsJournal()

        let store = ProblemsStore(journal: journal)
        store.load()
        let presenter = LaunchPresenter(store: store)
        presenter.refresh()

        _store = State(initialValue: store)
        _presenter = State(initialValue: presenter)
    }

    var body: some Scene {
        Window(OvationBuild.displayName, id: OvationBuild.mainWindowID) {
            RootView(presenter: presenter, store: store)
        }
    }
}
