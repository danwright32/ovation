// Plan 1.13, ovation#59. The durable home for every failure the app has
// reported, and the thing the launch presenter reads.
//
// THE STORE NEVER COMPOSES A SENTENCE. Only whatever measured the condition
// knows what it measured, and a message may claim only that (L11). The store's
// job is identity, counting, ordering and durability.
//
// IT NEVER RETRACTS. A problem leaves the open list in exactly one way: somebody
// resolves it and says why. A later success is not a resolution.
import Foundation

@MainActor
@Observable
final class ProblemsStore {
    private let journal: ProblemsJournal
    private var problems: [String: Problem] = [:]
    private var order: [String] = []
    private var journalHasFailed = false

    init(journal: ProblemsJournal) {
        self.journal = journal
    }

    /// Every problem ever recorded, oldest first.
    var all: [Problem] { order.compactMap { problems[$0] } }

    /// Everything still open, oldest first.
    var open: [Problem] { all.filter(\.isOpen) }

    /// What the launch presenter has to show: open, and not yet seen.
    var needingPresentation: [Problem] { all.filter(\.needsPresenting) }

    /// Report a failure. The same kind about the same subject is ONE problem that
    /// has happened more than once, so a check running on every launch cannot
    /// fill the panel with copies of one condition.
    ///
    /// Raising a resolved condition REOPENS it: resolution is a statement about a
    /// moment, not a promise about the future.
    @discardableResult
    func raise(kind: ProblemKind, subject: String?, sentence: String, now: Date) -> Problem {
        let id = Problem.identity(kind: kind, subject: subject)

        var problem: Problem
        if var existing = problems[id] {
            existing.occurrences += 1
            existing.lastRaised = now
            existing.sentence = sentence
            existing.resolvedAt = nil
            existing.resolutionReason = nil
            existing.acknowledgedAt = nil
            problem = existing
        } else {
            problem = Problem(id: id, kind: kind, subject: subject, sentence: sentence,
                              firstRaised: now, lastRaised: now, occurrences: 1,
                              acknowledgedAt: nil, resolvedAt: nil, resolutionReason: nil)
            order.append(id)
        }

        problems[id] = problem
        record(.raised, problem, now: now)
        return problem
    }

    /// Dan has seen it. It stops being presented and stays in the list.
    @discardableResult
    func acknowledge(_ id: Problem.ID, now: Date) -> Bool {
        guard var problem = problems[id] else { return false }
        problem.acknowledgedAt = now
        problems[id] = problem
        record(.acknowledged, problem, now: now)
        return true
    }

    /// The condition is gone, and here is why. The reason is required: a problem
    /// that vanished without one is indistinguishable from one that was tidied
    /// away to clear the panel.
    @discardableResult
    func resolve(_ id: Problem.ID, because reason: String, now: Date) -> Bool {
        guard var problem = problems[id] else { return false }
        problem.resolvedAt = now
        problem.resolutionReason = reason
        problems[id] = problem
        record(.resolved, problem, now: now)
        return true
    }

    /// Rebuild from the journal. Replays in order, so the last record about a
    /// problem is the state it is in.
    func load() {
        let records: [ProblemJournalRecord]
        do {
            records = try journal.load()
        } catch {
            // Nothing to do about it here beyond saying so. An empty store and a
            // store that could not be read are different facts (L215), and the
            // second one is itself a problem.
            noteJournalFailure(now: Date(timeIntervalSinceReferenceDate: 0))
            return
        }

        problems = [:]
        order = []
        for record in records {
            if problems[record.problem.id] == nil { order.append(record.problem.id) }
            problems[record.problem.id] = record.problem
        }

        // A journal that returned FEWER records than it holds has the same shape
        // as one that returned none, so the loss is said out loud rather than
        // being a number nobody reads (L46, L215). The count is the whole of what
        // can honestly be claimed: what those records said is gone.
        let skipped = journal.skippedOnLastLoad
        if skipped > 0 {
            let id = Problem.identity(kind: .problemsJournalDamaged, subject: nil)
            let sentence = "\(skipped) record(s) in Ovation's problem history could not be read "
                + "and have been left out. Everything else in the list loaded normally."
            let now = records.last?.problem.lastRaised ?? Date(timeIntervalSinceReferenceDate: 0)
            problems[id] = Problem(id: id, kind: .problemsJournalDamaged, subject: nil,
                                   sentence: sentence, firstRaised: now, lastRaised: now,
                                   occurrences: 1, acknowledgedAt: nil,
                                   resolvedAt: nil, resolutionReason: nil)
            order.append(id)
        }
    }

    private func record(_ action: ProblemJournalAction, _ problem: Problem, now: Date) {
        do {
            try journal.append(ProblemJournalRecord(action: action, problem: problem))
        } catch {
            noteJournalFailure(now: now)
        }
    }

    /// The journal's own failure is a problem, raised ONCE rather than once per
    /// write, or a broken journal buries every real condition under copies of
    /// itself.
    private func noteJournalFailure(now: Date) {
        guard !journalHasFailed else { return }
        journalHasFailed = true

        let id = Problem.identity(kind: .problemsJournalUnwritable, subject: nil)
        guard problems[id] == nil else { return }
        problems[id] = Problem(
            id: id,
            kind: .problemsJournalUnwritable,
            subject: nil,
            sentence: "Ovation could not write its record of problems, so anything reported "
                + "in this session will be gone when it next opens. Everything below is still "
                + "true right now.",
            firstRaised: now, lastRaised: now, occurrences: 1,
            acknowledgedAt: nil, resolvedAt: nil, resolutionReason: nil)
        order.append(id)
    }
}
