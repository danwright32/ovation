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
    /// ovation#162. Nil where there is no export control at all, which is every
    /// hosted test that was written before there was one.
    var exportCommand: YearEndExportCommand?

    /// ovation#40, PRD 44a. The roster pass and the rail around it. Both nil
    /// where there is no store to read clients from, which is every launch that
    /// refused to open one, and every hosted test written before this existed.
    var roster: RosterPresenter?
    var shell: ShellPresenter?

    /// WHICH WINDOW DAN GETS, decided in ONE place.
    ///
    /// The shell owns the window exactly while the roster is in the rail, and it
    /// asks the RAIL rather than computing a second predicate beside it, so the
    /// two can never disagree about whether there is anywhere to stand (L70).
    ///
    /// WHEN IT IS NOT SHOWING, THE WINDOW IS WHAT IT HAS ALWAYS BEEN. That is
    /// deliberate rather than a fallback: the launch notices and the durable
    /// problems list are the only surface several refusals have (ovation#59), so
    /// they are never replaced by a screen with nothing on it. Inside the shell
    /// they are carried at the foot of the rail instead.
    private var shellOwnsTheWindow: Bool {
        guard let shell, roster != nil else { return false }
        return shell.destinations.contains(.roster)
    }

    var body: some View {
        if shellOwnsTheWindow, let shell, let roster {
            ShellView(shell: shell, roster: roster, problems: store)
        } else {
            problemsWindow
        }
    }

    private var problemsWindow: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let command = exportCommand, case .running = command.progress {
                RunningExportView(command: command)
            }

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


/// ovation#162. An export in flight, said in a way that separates working, still
/// alive, and failed.
///
/// THIS IS A STANDING RULE RATHER THAN A DETAIL OF THIS FEATURE. Any action that
/// does not return at once has to let the reader tell, at a glance, that it
/// started, that it is still going, and that it ended. A spinner that looks the
/// same whether the work is progressing, hung or dead is a defect, so this counts
/// seconds: a number that stops moving is a run that has stopped.
///
/// THE OUTCOME IS NOT SHOWN HERE. It arrives as a problem in the list below,
/// through the same presenter every other condition uses (L242), which is also
/// why this surface disappears the moment the run ends rather than becoming a
/// second place the result is stated (L605).
struct RunningExportView: View {
    let command: YearEndExportCommand

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(sentence(at: context.date))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(sentence(at: context.date))
        }
    }

    func sentence(at instant: Date) -> String {
        guard let seconds = command.elapsed(now: instant) else {
            return "\(YearEndExportCommand.title) has finished."
        }
        return "Exporting the year. \(Int(seconds.rounded()))s so far."
    }
}
