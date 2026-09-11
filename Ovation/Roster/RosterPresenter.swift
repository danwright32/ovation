// ovation#40, PRD 5a. The roster pass as something Dan ACTS on.
//
// `RosterPass` is the reading; this is the pass being cleared. The split is not
// decoration: PRD 5a turns on the screen saying the number it BEGAN with, so the
// job reads as a one time pass rather than a standing nag, and a figure that
// counts down as you answer is the nag it was written against. So `startedWith`
// is taken once, here, and everything else is derived.
//
// THE STARTING FIGURE DOES NOT YET SURVIVE A RELAUNCH, which is ovation#203 and
// is a storage decision rather than a screen detail. It is captured in ONE place
// below, so wiring it to something durable is a change to one line rather than a
// hunt (L70). Until then, a pass opened tomorrow starts from whatever is left.
//
// A FAILED SAVE PUTS THE CLIENT BACK AND SAYS SO (L415). The chip changes the
// moment it is pressed, before the write lands, so a save that throws must
// revert it and leave a sentence behind. Without that a failed write looks
// exactly like a slow one, and the row quietly leaves the list while the store
// still refuses to invoice that client.
//
// THE FAILURE SENTENCE NAMES THE CLIENT, and that is a correction rather than an
// oversight. It carried the client's ID and deliberately not its name, applying
// docs/PRIVACY-FLOOR.md to it. That floor exists to keep real names out of a
// PUBLIC repository and out of terminal output, and it says in terms that Dan
// reads them on HIS OWN SCREEN. This is his own screen. So the rule was being
// applied to the one place it does not govern, and the cost was the sentence
// that appears at the worst possible moment naming nobody he recognises and
// quoting a programmer's error at him. Nothing here is written to a log; if a
// log is ever added, the identifier is what belongs in it.
import Foundation

@MainActor
@Observable
final class RosterPresenter {
    /// Every client the pass was opened over.
    let clients: [Client]

    /// Committing the change. Injected, so a test drives the failure path
    /// without a disk, and so this type never reaches for a store of its own.
    private let save: () throws -> Void

    /// How many were blocked WHEN THE PASS BEGAN. Taken once. This is the one
    /// place it is captured, and ovation#203 is about making it durable.
    let startedWith: Int

    /// What went wrong with the last write, or nil. Present on the screen rather
    /// than only recorded, because a refusal only a log can see is one nobody
    /// can act on.
    private(set) var lastFailure: String?

    init(clients: [Client], save: @escaping () throws -> Void) {
        self.clients = clients
        self.save = save
        self.startedWith = RosterPass(clients: clients).startedWith
    }

    /// The reading, re-taken. Everything below reads THIS rather than filtering
    /// again, so the counts and the rows they promise come from one predicate
    /// and can never disagree (L16).
    private var pass: RosterPass { RosterPass(clients: clients) }

    var remaining: Int { pass.remaining }
    var isSettled: Bool { pass.isSettled }
    var rosterSize: Int { pass.rosterSize }

    /// The clients whose address cannot be sent to. Empty since 2026-09-11, when
    /// Dan fixed the one real value in Downbeat; the section it feeds is not
    /// drawn while it is empty (PRD 5a), and it returns when one does.
    var withUnusableAddress: [Client] { pass.withUnusableAddress }

    /// The clients requirement 5 refuses to send for.
    var needingTaxStatus: [Client] { pass.needingTaxStatus }

    /// Record a client's sales tax status, the one answer this pass exists to
    /// collect. Throws what the save threw, having already put the client back.
    func answer(_ client: Client, as status: TaxStatus) throws {
        let previous = client.taxStatus
        client.taxStatus = status
        do {
            try save()
            lastFailure = nil
        } catch {
            client.taxStatus = previous
            lastFailure = "\(client.name)'s sales tax status could not be saved, so it has "
                + "been put back to what it was. Trying again is safe. "
                + "Ovation's reason: \(error)"
            throw error
        }
    }
}
