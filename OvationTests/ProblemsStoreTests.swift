import Foundation
import Testing

/// Plan 1.13, ovation#59. Every failure path in the app lands here, loudly, with
/// a distinct sentence per cause, and nothing here ever retracts on its own.
@MainActor
struct ProblemsStoreTests {

    // MARK: raising

    @Test("a raised problem keeps the sentence its cause gave it")
    func aProblemKeepsItsSentence() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        store.raise(kind: .foreignStore,
                    subject: "/tmp/Ovation/Ovation.store",
                    sentence: "The database at /tmp/Ovation/Ovation.store belongs to another app.",
                    now: at(10))

        #expect(store.open.count == 1)
        #expect(store.open.first?.kind == .foreignStore)
        #expect(store.open.first?.sentence.hasPrefix("The database at") == true)
    }

    @Test("the same condition raised twice is one problem that has happened twice")
    func raisingTwiceCountsRatherThanDuplicating() {
        // A launch check that runs on every launch would otherwise fill the panel
        // with copies of one condition, and a panel nobody can read is a panel
        // nobody reads.
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        store.raise(kind: .foreignStore, subject: "same", sentence: "first", now: at(10))
        store.raise(kind: .foreignStore, subject: "same", sentence: "first", now: at(20))

        #expect(store.open.count == 1)
        #expect(store.open.first?.occurrences == 2)
        #expect(store.open.first?.firstRaised == at(10))
        #expect(store.open.first?.lastRaised == at(20))
    }

    @Test("the same kind about a different subject is a different problem")
    func theSubjectIsPartOfTheIdentity() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        store.raise(kind: .backupFailed, subject: "backup-1", sentence: "one", now: at(10))
        store.raise(kind: .backupFailed, subject: "backup-2", sentence: "two", now: at(11))

        #expect(store.open.count == 2)
    }

    @Test("a later success does not retract anything")
    func nothingRetractsOnItsOwn() {
        // The whole point of the ported pattern. A later success says nothing
        // about the earlier failure, and a notice that clears while the condition
        // persists is worse than one that never clears at all.
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        store.raise(kind: .backupFailed, subject: "b", sentence: "the backup could not be read",
                    now: at(10))

        store.raise(kind: .exportStale, subject: "2026", sentence: "no export for 40 days",
                    now: at(20))

        #expect(store.open.count == 2)
    }

    // MARK: acknowledging and resolving are different things

    @Test("acknowledging stops a problem being presented, and leaves it in the list")
    func acknowledgingIsNotResolving() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        store.raise(kind: .foreignStore, subject: "s", sentence: "one", now: at(10))
        let id = try! #require(store.open.first?.id)

        store.acknowledge(id, now: at(11))

        #expect(store.open.count == 1)
        #expect(store.needingPresentation.isEmpty)
        #expect(store.open.first?.acknowledgedAt == at(11))
    }

    @Test("resolving records WHY, because a problem that vanished without a reason is not resolved")
    func resolvingCarriesItsReason() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        store.raise(kind: .foreignStore, subject: "s", sentence: "one", now: at(10))
        let id = try! #require(store.open.first?.id)

        store.resolve(id, because: "Dan moved the foreign file aside", now: at(12))

        #expect(store.open.isEmpty)
        #expect(store.all.count == 1)
        #expect(store.all.first?.resolvedAt == at(12))
        #expect(store.all.first?.resolutionReason == "Dan moved the foreign file aside")
    }

    @Test("raising a resolved condition again reopens it rather than staying quietly closed")
    func aResolvedConditionCanComeBack() {
        // Resolution is a statement about a moment, not a promise about the
        // future. If the condition happens again it is open again, and the record
        // says it has happened twice.
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        store.raise(kind: .foreignStore, subject: "s", sentence: "one", now: at(10))
        let id = try! #require(store.open.first?.id)
        store.resolve(id, because: "moved aside", now: at(12))

        store.raise(kind: .foreignStore, subject: "s", sentence: "one", now: at(20))

        #expect(store.open.count == 1)
        #expect(store.open.first?.occurrences == 2)
        #expect(store.open.first?.resolvedAt == nil)
    }

    @Test("acknowledging or resolving something that is not there is refused, not ignored")
    func anUnknownIdentityIsRefused() {
        let store = ProblemsStore(journal: InMemoryProblemsJournal())
        #expect(!store.acknowledge("no-such-problem", now: at(10)))
        #expect(!store.resolve("no-such-problem", because: "nothing", now: at(10)))
    }

    // MARK: durability

    @Test("everything that happens is written to the journal, in order")
    func theJournalRecordsEveryChange() {
        let journal = InMemoryProblemsJournal()
        let store = ProblemsStore(journal: journal)
        store.raise(kind: .foreignStore, subject: "s", sentence: "one", now: at(10))
        let id = try! #require(store.open.first?.id)
        store.acknowledge(id, now: at(11))
        store.resolve(id, because: "moved aside", now: at(12))

        #expect(journal.appended.count == 3)
        #expect(journal.appended.map(\.action) == [.raised, .acknowledged, .resolved])
    }

    @Test("a store reloaded from its journal is the store that was written")
    func theJournalReplays() {
        let journal = InMemoryProblemsJournal()
        let first = ProblemsStore(journal: journal)
        first.raise(kind: .foreignStore, subject: "s", sentence: "one", now: at(10))
        first.raise(kind: .backupFailed, subject: "b", sentence: "two", now: at(11))
        let id = try! #require(first.open.first?.id)
        first.acknowledge(id, now: at(12))

        let reloaded = ProblemsStore(journal: journal)
        reloaded.load(now: at(20))

        #expect(reloaded.all.count == 2)
        #expect(reloaded.needingPresentation.count == 1)
        #expect(reloaded.all.first(where: { $0.id == id })?.acknowledgedAt == at(12))
    }

    @Test("a journal that lost records on the way in says how many, rather than looking complete")
    func aDamagedJournalIsReported() {
        // A journal returning fewer records than it holds has the same shape as
        // one returning none (L215). The count is all that can honestly be
        // claimed: what those records said is gone.
        let journal = LossyProblemsJournal(skipped: 2)
        let store = ProblemsStore(journal: journal)

        store.load(now: at(30))

        #expect(store.open.contains { $0.kind == .problemsJournalDamaged })
        #expect(store.open.first(where: { $0.kind == .problemsJournalDamaged })?
            .sentence.contains("2 record(s)") == true)
    }

    @Test("a journal that lost nothing says nothing")
    func anIntactJournalIsQuiet() {
        let store = ProblemsStore(journal: LossyProblemsJournal(skipped: 0))
        store.load(now: at(30))

        #expect(!store.open.contains { $0.kind == .problemsJournalDamaged })
    }

    @Test("a journal that cannot be READ says that, not that it could not be written")
    func aFailedReadIsItsOwnSentence() {
        // Two different facts. The file being unreadable at launch means this
        // session starts with no history; the file being unwritable means
        // anything reported in this session will be gone next time. A message may
        // claim only what its check measured (L11).
        let store = ProblemsStore(journal: RefusingProblemsJournal())

        store.load(now: at(30))

        #expect(store.open.contains { $0.kind == .problemsJournalUnreadable })
        #expect(!store.open.contains { $0.kind == .problemsJournalUnwritable })
        #expect(store.open.first?.sentence.contains("could not read") == true)
    }

    @Test("a problem raised BY the load carries the time of that load, not a placeholder")
    func loadStampsItsOwnProblemsWithTheRealTime() {
        // ovation#89. Every other path takes `now` as a parameter precisely so
        // nothing reads the clock at the point of use, and `load` was the one
        // that had no clock at all: both problems it can raise about the journal
        // itself were stamped 1 January 2001. A current failure dated twenty five
        // years ago reads as a corrupt record rather than as today's problem, and
        // any later ordering or staleness question about the list gets a wrong
        // answer from it.
        let unreadable = ProblemsStore(journal: RefusingProblemsJournal())
        unreadable.load(now: at(30))
        let read = try! #require(unreadable.open.first { $0.kind == .problemsJournalUnreadable })
        #expect(read.firstRaised == at(30))
        #expect(read.lastRaised == at(30))

        let damaged = ProblemsStore(journal: LossyProblemsJournal(skipped: 2))
        damaged.load(now: at(30))
        let lost = try! #require(damaged.open.first { $0.kind == .problemsJournalDamaged })
        #expect(lost.firstRaised == at(30))
        #expect(lost.lastRaised == at(30))
    }

    @Test("the damaged notice is stamped when the damage was FOUND, not when the survivors were written")
    func theDamagedNoticeIsStampedAtTheLoad() {
        // The surviving records carry their own, older times. Stamping the notice
        // with the last of those would date the discovery to before it happened
        // and sort it among history rather than at the moment it was found.
        let journal = LossyProblemsJournal(skipped: 1)
        journal.records = [ProblemJournalRecord(
            action: .raised,
            problem: Problem(id: "x", kind: .foreignStore, subject: "s", sentence: "old",
                             firstRaised: at(10), lastRaised: at(10), occurrences: 1,
                             acknowledgedAt: nil, resolvedAt: nil, resolutionReason: nil))]
        let store = ProblemsStore(journal: journal)

        store.load(now: at(30))

        let lost = try! #require(store.open.first { $0.kind == .problemsJournalDamaged })
        #expect(lost.firstRaised == at(30))
    }

    @Test("a journal that cannot be written does not lose the problem from the screen")
    func aFailedWriteStillRaisesTheProblem() {
        // The journal is how a problem survives a relaunch. It is not how the
        // problem reaches Dan in this one, and a failure to write must not
        // swallow the condition that was being reported (L215).
        let journal = RefusingProblemsJournal()
        let store = ProblemsStore(journal: journal)

        store.raise(kind: .foreignStore, subject: "s", sentence: "one", now: at(10))

        // The condition that was being reported is still open. The store also
        // raises one about the journal, which the next case is about, so this
        // asserts the presence of the original rather than a total.
        #expect(store.open.contains { $0.kind == .foreignStore && $0.sentence == "one" })
    }

    @Test("and a journal that cannot be written raises a problem about ITSELF")
    func aFailedWriteIsItsOwnProblem() {
        // Otherwise the one failure nobody hears about is the failure of the
        // thing that exists to make failures heard.
        let store = ProblemsStore(journal: RefusingProblemsJournal())
        store.raise(kind: .foreignStore, subject: "s", sentence: "one", now: at(10))

        #expect(store.open.contains { $0.kind == .problemsJournalUnwritable })
    }

    @Test("the journal's own failure is raised once, not once per problem")
    func theJournalFailureDoesNotStorm() {
        let store = ProblemsStore(journal: RefusingProblemsJournal())
        store.raise(kind: .foreignStore, subject: "a", sentence: "one", now: at(10))
        store.raise(kind: .backupFailed, subject: "b", sentence: "two", now: at(11))

        #expect(store.open.filter { $0.kind == .problemsJournalUnwritable }.count == 1)
    }

    // MARK: fixtures

    private func at(_ second: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(second))
    }
}

/// A journal that refuses every write, so the store's own failure path is
/// exercised rather than assumed.
/// A journal that reads fine but admits it dropped records.
private final class LossyProblemsJournal: ProblemsJournal {
    let isDurable = true
    let skippedOnLastLoad: Int

    var records: [ProblemJournalRecord] = []

    init(skipped: Int) { skippedOnLastLoad = skipped }

    func append(_ record: ProblemJournalRecord) throws {}
    func load() throws -> [ProblemJournalRecord] { records }
}

private final class RefusingProblemsJournal: ProblemsJournal {
    let isDurable = true
    let skippedOnLastLoad = 0

    func append(_ record: ProblemJournalRecord) throws {
        throw ProblemsJournalError.couldNotWrite("the fixture refuses every write")
    }

    func load() throws -> [ProblemJournalRecord] {
        throw ProblemsJournalError.couldNotRead("the fixture refuses every read")
    }
}
