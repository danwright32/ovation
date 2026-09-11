// ovation#40. The step between an opened store and the window, kept OUT of the
// entry point so that a test can reach it.
//
// `OvationApp.swift` is the one file the pure suite cannot compile, because it
// carries `@main`. Anything decided in there is decided where nothing can check
// it, so what is left in the app is the call and nothing else.
//
// A FETCH THAT FAILED IS NOT AN EMPTY ROSTER (L215). Answering with an empty
// list when the read threw would make a store Ovation cannot see its clients in
// look exactly like a healthy new install with none, and those need opposite
// responses. So a failure raises a problem, through the same presenter as every
// other launch time condition (L242), and hands back nothing.
import Foundation

extension ProblemKind {
    /// Ovation opened its store and could not read the client list out of it.
    static let rosterUnreadable = ProblemKind("roster.unreadable")
}

@MainActor
enum RosterLaunch {

    /// The roster pass and the rail around it, or nothing where the clients
    /// could not be read.
    ///
    /// WHERE IT STARTS YOU IS PART OF THE RULE, not a default. The roster stays
    /// in the rail while you are standing on it (PRD 5a), so starting there
    /// unconditionally would pin it open for ever and the rule that it leaves
    /// when empty could never fire. So it starts you on the pass only when the
    /// pass has something in it.
    static func presenters(
        fetchClients: () throws -> [Client],
        save: @escaping () throws -> Void,
        problems: ProblemsStore,
        now: Date
    ) -> (roster: RosterPresenter, shell: ShellPresenter)? {
        let clients: [Client]
        do {
            clients = try fetchClients()
        } catch {
            _ = problems.raise(
                kind: .rosterUnreadable,
                subject: nil,
                sentence: "Ovation opened its database but could not read the client list out "
                    + "of it: \(error). Until it can, it cannot tell you which clients are "
                    + "missing a sales tax status, and an invoice for one of them will still "
                    + "refuse to send.",
                now: now)
            return nil
        }

        let roster = RosterPresenter(clients: clients, save: save)
        let shell = ShellPresenter(
            selected: roster.isSettled ? .invoices : .roster,
            // Re-read every time the rail is drawn, never copied in here, or it
            // would be true at launch and never again (L175).
            rosterHasWork: { [weak roster] in !(roster?.isSettled ?? true) })
        return (roster, shell)
    }
}
