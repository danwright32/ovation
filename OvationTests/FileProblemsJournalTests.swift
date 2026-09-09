import Foundation
import Testing

/// Plan 1.13, ovation#59. The half that makes a problem survive a relaunch.
struct FileProblemsJournalTests {

    @Test("a record written is a record read back")
    func recordsRoundTrip() throws {
        let scratch = try Scratch()
        let journal = FileProblemsJournal(url: scratch.url("problems.jsonl"))

        try journal.append(record(.raised, "one"))
        try journal.append(record(.acknowledged, "one"))

        let loaded = try journal.load()
        #expect(loaded.count == 2)
        #expect(loaded.map(\.action) == [.raised, .acknowledged])
        #expect(journal.skippedOnLastLoad == 0)
    }

    @Test("appending adds to what is there rather than replacing it")
    func appendingIsAppending() throws {
        // The failure this rules out is a read, modify, write cycle whose read
        // answers empty when it fails, erasing the whole record at the moment it
        // is worth having (L105).
        let scratch = try Scratch()
        let url = scratch.url("problems.jsonl")

        try FileProblemsJournal(url: url).append(record(.raised, "one"))
        try FileProblemsJournal(url: url).append(record(.raised, "two"))

        #expect(try FileProblemsJournal(url: url).load().count == 2)
    }

    @Test("a journal that has never been written is empty, not an error")
    func anAbsentJournalIsEmpty() throws {
        let scratch = try Scratch()
        let journal = FileProblemsJournal(url: scratch.url("nothing-here.jsonl"))

        #expect(try journal.load().isEmpty)
    }

    @Test("a corrupt line costs that line and is COUNTED, never the whole file")
    func oneBadLineDoesNotLoseTheJournal() throws {
        let scratch = try Scratch()
        let url = scratch.url("problems.jsonl")
        let journal = FileProblemsJournal(url: url)
        try journal.append(record(.raised, "one"))

        // A truncated write, which is what a crash mid append leaves.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"action\":\"rai".utf8))
        try handle.close()
        try journal.append(record(.raised, "two"))

        let loaded = try journal.load()
        #expect(loaded.count == 2)
        #expect(journal.skippedOnLastLoad == 1)
    }

    @Test("a directory that does not exist yet is made rather than refused")
    func theDirectoryIsCreated() throws {
        let scratch = try Scratch()
        let url = scratch.url("not-made-yet").appendingPathComponent("problems.jsonl")

        try FileProblemsJournal(url: url).append(record(.raised, "one"))

        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("a write that cannot happen is a named refusal, never a silent nothing")
    func aRefusedWriteSaysSo() throws {
        let scratch = try Scratch()
        // A path whose parent is a FILE cannot hold a directory, so neither the
        // directory nor the write can be made.
        let blocker = scratch.url("blocker")
        try Data("not a directory".utf8).write(to: blocker)
        let journal = FileProblemsJournal(url: blocker.appendingPathComponent("problems.jsonl"))

        #expect(throws: ProblemsJournalError.self) {
            try journal.append(record(.raised, "one"))
        }
    }

    @Test("a disposable launch gets no journal path at all, and a real one does")
    func theLivePathIsRefusedUnderTests() {
        let root = URL(fileURLWithPath: "/tmp/ovation-journal-fixture", isDirectory: true)

        #expect(FileProblemsJournal.liveURL(appSupport: root, isDebugBuild: false,
                                            isDisposableLaunch: true) == nil)
        #expect(FileProblemsJournal.liveURL(appSupport: root, isDebugBuild: false,
                                            isDisposableLaunch: false)?.path
                == "/tmp/ovation-journal-fixture/Ovation/problems.jsonl")
        // And the defaults read this process, so a caller that passes nothing is
        // refused (plan 1.9).
        #expect(FileProblemsJournal.liveURL() == nil)
    }

    // MARK: fixtures

    private func record(_ action: ProblemJournalAction, _ subject: String) -> ProblemJournalRecord {
        ProblemJournalRecord(
            action: action,
            problem: Problem(id: "store.foreign:\(subject)", kind: .foreignStore,
                             subject: subject, sentence: "a sentence",
                             firstRaised: Date(timeIntervalSinceReferenceDate: 0),
                             lastRaised: Date(timeIntervalSinceReferenceDate: 0),
                             occurrences: 1, acknowledgedAt: nil,
                             resolvedAt: nil, resolutionReason: nil))
    }
}

private final class Scratch {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ovation-journal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    deinit { try? FileManager.default.removeItem(at: root) }
}
