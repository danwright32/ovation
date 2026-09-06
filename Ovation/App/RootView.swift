import SwiftUI

/// Plan 1.13, ovation#59. The one window, showing the one launch notice and the
/// durable list behind it.
///
/// EVERY DECISION IS THE PRESENTER'S. This view chooses nothing: which condition
/// is showing, how many are waiting, and what dismissing does all come from
/// `LaunchPresenter`. What lives here is the binding, and the binding is what
/// the hosted tests exist to check, because the precedent this design comes from
/// (postroll#846, #855) was a defect no model level test could see.
///
/// THE NOTICE IS KEYED ON THE PROBLEM'S IDENTITY. A surface driven by a boolean
/// cannot notice that WHICH thing is showing has changed, so replacing one
/// notice with another leaves the previous content on screen (L243). `.id()`
/// makes a change of condition a change of view.
struct RootView: View {
    @Bindable var presenter: LaunchPresenter
    @Bindable var store: ProblemsStore
    /// Injected so a test can drive dismissal without reading the clock. The app
    /// passes the real one.
    var now: () -> Date = Date.init

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let problem = presenter.showing {
                LaunchNoticeView(problem: problem,
                                 waiting: presenter.waiting,
                                 dismiss: { presenter.dismiss(now: now()) })
                    .id(problem.id)
            }

            ProblemsListView(problems: store.open)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360, alignment: .topLeading)
    }
}

/// One condition, said in the sentence whatever measured it wrote.
struct LaunchNoticeView: View {
    let problem: Problem
    let waiting: Int
    let dismiss: () -> Void

    /// What the notice says about the ones behind it. Nothing at all when there
    /// are none, because "0 more" is noise.
    static func waitingSentence(_ waiting: Int) -> String? {
        switch waiting {
        case ..<1: return nil
        case 1: return "1 more to read"
        default: return "\(waiting) more to read"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(problem.sentence)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("I have read this", action: dismiss)
                if let waiting = Self.waitingSentence(waiting) {
                    Text(waiting).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The durable list. A condition that persists in the data must not be reachable
/// only from a notice that clears (L126), so everything open is here whether or
/// not it is the one being presented.
struct ProblemsListView: View {
    let problems: [Problem]

    /// The empty state is its own sentence, and it is not an error (L10).
    static let nothingWrong = "Nothing has gone wrong."

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Problems").font(.title3)

            if problems.isEmpty {
                Text(Self.nothingWrong).foregroundStyle(.secondary)
            } else {
                ForEach(problems) { problem in
                    Text(problem.sentence)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
