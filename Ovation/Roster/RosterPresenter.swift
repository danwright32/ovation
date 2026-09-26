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
// ONE WRITER FOR THE FACT (ovation#481). The answer is recorded by
// `ClientTaxStatusWriter`, the actor the invoice screen already records it with,
// so a rule about writing a tax status (it refuses `neverRecorded` today) is
// written once and holds on both screens. Before this the roster set the field on
// its own object and saved its own context, and the refusal held here only as a
// side effect of the screen not offering that value (L281).
//
// THE OBJECT THE ROSTER HOLDS IS NEVER WRITTEN TO (L443, PRD 51l). The writer
// saves in a context of its own; an object from the roster's context changed
// alongside it would leave that context dirty, able to put its older values back
// over the writer's. So the answer given is carried HERE, keyed by the client,
// and the pass reads it through `status(of:)`. What the writer confirmed is kept
// apart from what is shown, so a failure knows what the store really holds.
//
// A FAILED WRITE PUTS THE CLIENT BACK AND SAYS SO (L415). The chip changes the
// moment it is pressed, before the write lands, so a write that throws must
// revert it and leave a sentence behind. Without that a failed write looks
// exactly like a slow one, and the row quietly leaves the list while the store
// still refuses to invoice that client. It is put back to the last answer the
// writer CONFIRMED, or to the status the pass was opened with if none was.
//
// WRITES LAND IN THE ORDER THEY WERE PRESSED. Each write is a fresh actor and two
// actors are not ordered with each other, so the presenter queues them: a press
// waits for the one before it. A failure rolls back only if nothing was pressed
// for that client since, because the later press is what Dan now means and its
// own write decides what is shown.
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
import SwiftData

@MainActor
@Observable
final class RosterPresenter {
    /// Recording one client's answer. `writer(over:)` is the real one; tests
    /// hand in a double so the failure paths run without a disk.
    typealias TaxStatusWrite = @MainActor (Client, TaxStatus) async throws -> Void

    /// Every client the pass was opened over.
    let clients: [Client]

    /// Committing an answer. Injected, so this type never reaches for a store of
    /// its own.
    private let write: TaxStatusWrite

    /// How many were blocked WHEN THE PASS BEGAN. Taken once. This is the one
    /// place it is captured, and ovation#203 is about making it durable.
    let startedWith: Int

    /// What went wrong with the last write, or nil. Present on the screen rather
    /// than only recorded, because a refusal only a log can see is one nobody
    /// can act on.
    private(set) var lastFailure: String?

    /// Which client `lastFailure` is about. The sentence explains why that row
    /// came back, so only that client's next success takes it away.
    private var failedClient: UUID?

    /// The answer shown for each client pressed, landed or not.
    private var shown: [UUID: TaxStatus] = [:]

    /// The answer the writer confirmed for each client, which is what the store
    /// holds and so what a later failure puts back.
    private var confirmed: [UUID: TaxStatus] = [:]

    /// How many times each client has been pressed, so a write that finishes
    /// after a later press knows it no longer decides what is shown.
    private var presses: [UUID: Int] = [:]

    /// The write in flight, which the next one waits for.
    private var tail: Task<Void, Never>?

    init(clients: [Client], write: @escaping TaxStatusWrite) {
        self.clients = clients
        self.write = write
        self.startedWith = RosterPass(clients: clients).startedWith
    }

    /// The real write: the one actor that records a client's tax status, the
    /// same one the invoice screen records it with.
    static func writer(over container: ModelContainer) -> TaxStatusWrite {
        { client, status in
            let id = client.persistentModelID
            try await ClientTaxStatusWriter(modelContainer: container).setTaxStatus(status, on: id)
        }
    }

    /// A client's sales tax status as this pass shows it: the answer given here,
    /// otherwise what the client held when the pass was read.
    func status(of client: Client) -> TaxStatus {
        shown[client.id] ?? client.taxStatus
    }

    /// The reading, re-taken. Everything below reads THIS rather than filtering
    /// again, so the counts and the rows they promise come from one predicate
    /// and can never disagree (L16).
    private var pass: RosterPass {
        RosterPass(clients: clients, taxStatus: { [shown] in shown[$0.id] ?? $0.taxStatus })
    }

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
    /// collect. Shown at once, written after any write already queued, and put
    /// back with a sentence if the write fails. Returns once this answer's own
    /// write has finished.
    func answer(_ client: Client, as status: TaxStatus) async {
        let key = client.id
        let press = (presses[key] ?? 0) + 1
        presses[key] = press
        shown[key] = status

        let before = tail
        let write = self.write
        let landing = Task { @MainActor [weak self] in
            await before?.value
            do {
                try await write(client, status)
                guard let self else { return }
                self.confirmed[key] = status
                if self.failedClient == key {
                    self.lastFailure = nil
                    self.failedClient = nil
                }
            } catch {
                guard let self, self.presses[key] == press else { return }
                self.shown[key] = self.confirmed[key]
                self.lastFailure = Self.failureSentence(naming: client.name, error)
                self.failedClient = key
            }
        }
        tail = landing
        await landing.value
    }

    /// What the screen says when a write did not land. It names the client and
    /// says the value was put back either way (L415). A refusal is said in the
    /// writer's own sentence, the one the invoice screen shows; anything else is
    /// quoted, since it is the only diagnosis there is.
    private static func failureSentence(naming name: String, _ error: any Error) -> String {
        if let refusal = error as? ClientTaxStatusRefusal {
            return "\(name)'s sales tax status has been put back to what it was. "
                + refusal.sentence
        }
        return "\(name)'s sales tax status could not be saved, so it has "
            + "been put back to what it was. Trying again is safe. "
            + "Ovation's reason: \(error)"
    }
}
