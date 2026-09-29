import Foundation
import Testing

/// ovation#246. Turning what `BlockingWork` came back with into what the launch
/// does, which is a decision each way and used to live in the one file no test
/// here can compile.
struct LaunchBackupOutcomeTests {

    private static let launch = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a backup that answered is the answer")
    func answeredPassesThrough() throws {
        let taken = BackupService.Attempt.taken(URL(fileURLWithPath: "/tmp/a"), retention: .ran(.init()))

        #expect(try LaunchBackupOutcome.attempt(from: .answered(taken)) == taken)
    }

    /// A SKIP IS STILL A SKIP. The commonest case travels through untouched, and
    /// a translation that turned it into a failure would raise a notice on every
    /// second launch of the day (L36).
    @Test("a backup already taken today passes through as itself")
    func aSkipPassesThrough() throws {
        let already = BackupService.Attempt.alreadyTakenToday(URL(fileURLWithPath: "/tmp/a"))

        #expect(try LaunchBackupOutcome.attempt(from: .answered(already)) == already)
    }

    @Test("a backup that failed throws, carrying what it said")
    func failedThrows() {
        #expect(throws: BackupError.couldNotWrite("/Volumes/Backups is gone")) {
            try LaunchBackupOutcome.attempt(from: .failed("/Volumes/Backups is gone"))
        }
    }

    /// AN ABANDONED WAIT IS NOT A FAILURE, and it is not a write failure either
    /// (ovation#507). The work may still be running: a blocking file copy reads no
    /// cancellation flag, so the deadline abandons the wait rather than stopping
    /// it, and claiming the backup could not be written would claim something
    /// nobody measured (L11).
    @Test("a backup abandoned at the deadline throws still running, carrying how long it waited")
    func gaveUpIsStillRunning() {
        #expect(throws: BackupError.stillRunning(after: .seconds(5))) {
            try LaunchBackupOutcome.attempt(from: .gaveUp(after: .seconds(5)))
        }
    }

    // MARK: the deadline is sized for what the backup copies (ovation#507)

    /// THE FLOOR IS THE OLD DEADLINE. Today's data folder is 19 files and 372KB,
    /// and a launch backing that up must wait no less than it did before.
    @Test("an empty data folder is given the floor, and today's data folder hardly more")
    func theFloorIsTheOldDeadline() {
        #expect(LaunchBackupOutcome.deadline(for: .init(files: 0, bytes: 0))
                == LaunchBackupOutcome.deadlineFloor)
        #expect(LaunchBackupOutcome.deadlineFloor == BlockingWork.defaultDeadline)

        let today = LaunchBackupOutcome.deadline(for: .init(files: 19, bytes: 372_000))
        #expect(today > LaunchBackupOutcome.deadlineFloor)
        #expect(today < LaunchBackupOutcome.deadlineFloor + .seconds(1))
    }

    /// TWO THINGS COST TIME, and each is allowed for on its own. Measured on this
    /// Mac, a backup of small files is paid per file and one of large files per
    /// byte, so a deadline scaled by either alone is short for the other (L391).
    @Test("the deadline grows with the number of files and, separately, with the bytes")
    func theDeadlineGrowsWithBoth() {
        let base = LaunchBackupOutcome.deadline(for: .init(files: 100, bytes: 1_000_000))
        let moreFiles = LaunchBackupOutcome.deadline(for: .init(files: 10_000, bytes: 1_000_000))
        let moreBytes = LaunchBackupOutcome.deadline(for: .init(files: 100, bytes: 5_000_000_000))

        #expect(moreFiles > base + .seconds(10))
        #expect(moreBytes > base + .seconds(10))
    }

    /// SEVEN YEARS OF RECEIPTS, the size BackupCostTests measures at (4,000
    /// documents), at a generous 250KB each, must be given at least ten times what
    /// that measurement took on this Mac, so a slower disk or a busy launch is
    /// still inside it.
    @Test("seven years of documents is given at least ten times its measured cost")
    func sevenYearsHasHeadroom() {
        let sevenYears = LaunchBackupOutcome.deadline(for: .init(files: 4_000, bytes: 1_000_000_000))
        // Measured on this Mac: 1,000 files of 300KB copied, hashed and re-read in
        // 0.75s (2026-09-26), and 4,000 of 40KB backed up in 3.07s (2026-09-08,
        // BackupCostTests). About 5.5s for this.
        #expect(sevenYears >= .seconds(55))
    }

    /// THE LAUNCH MEASURES FIRST AND WAITS FOR WHAT IT MEASURED. Driven through
    /// the real helper, with the clock injected so the deadline each wait was
    /// given can be read back rather than paid (L524, L718).
    @Test("the launch waits on the backup for the deadline its size calls for")
    func theLaunchWaitsForTheMeasuredDeadline() async throws {
        let waits = RecordedWaits()
        let taken = BackupService.Attempt.taken(URL(fileURLWithPath: "/tmp/a"), retention: .ran(.init()))
        let size = BackupSize(files: 4_000, bytes: 1_000_000_000)

        let attempt = try await LaunchBackupOutcome.run(
            at: Self.launch,
            measuring: { size },
            sleeping: waits.sleep,
            recording: { _ in }) { taken }

        #expect(attempt == taken)
        // THE WHOLE SEQUENCE, the size walk's floor and then the backup's own
        // deadline, read as a value: `BlockingWork.run` settles its timer before it
        // returns (ovation#572), so nothing here is still to be recorded.
        #expect(waits.durations == [LaunchBackupOutcome.deadlineFloor,
                                    LaunchBackupOutcome.deadline(for: size)])
    }

    /// A MEASUREMENT THAT FAILS DOES NOT STOP THE BACKUP. Whatever stopped the size
    /// being read will stop the backup too, and the backup is what names it; here
    /// the launch simply waits the floor, which is what it did before (L93).
    @Test("a size that could not be measured leaves the backup the floor, and the backup still runs")
    func anUnmeasuredSizeWaitsTheFloor() async throws {
        struct Unreadable: Error {}
        let waits = RecordedWaits()
        let taken = BackupService.Attempt.taken(URL(fileURLWithPath: "/tmp/a"), retention: .ran(.init()))

        let attempt = try await LaunchBackupOutcome.run(
            at: Self.launch,
            measuring: { throw Unreadable() },
            sleeping: waits.sleep,
            recording: { _ in }) { taken }

        #expect(attempt == taken)
        #expect(waits.durations == [LaunchBackupOutcome.deadlineFloor,
                                    LaunchBackupOutcome.deadlineFloor])
    }

    /// AND A BACKUP STILL RUNNING AT THAT DEADLINE COMES OUT AS STILL RUNNING,
    /// through the real helper rather than a hand built outcome.
    @Test("a backup still running at its deadline reaches the launch as still running")
    func aSlowBackupIsStillRunning() async {
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }

        await #expect(throws: BackupError.stillRunning(after: LaunchBackupOutcome.deadlineFloor)) {
            try await LaunchBackupOutcome.run(
                at: Self.launch,
                measuring: { .init(files: 0, bytes: 0) },
                sleeping: { _ in },
                recording: { _ in }) {
                    release.wait()
                    return .taken(URL(fileURLWithPath: "/tmp/a"), retention: .ran(.init()))
                }
        }
    }

    /// THE RE-CHECK OF AN OLD ARCHIVE IS SIZED THE SAME WAY. It reads and hashes
    /// every file in one archive, which is a copy of the data folder, and it gives
    /// up SILENTLY by design, so on a floor the archives had outgrown it would stop
    /// checking anything, for ever, with nothing said (L30, L98).
    @Test("the re-check of an old archive waits for the deadline the data folder's size calls for")
    func theRecheckWaitsForTheMeasuredDeadline() async {
        let waits = RecordedWaits()
        let size = BackupSize(files: 4_000, bytes: 1_000_000_000)

        let checked = await LaunchBackupOutcome.reverify(
            measuring: { size },
            sleeping: waits.sleep) { .nothingToCheck }

        #expect(checked == .nothingToCheck)
        #expect(waits.durations == [LaunchBackupOutcome.deadlineFloor,
                                    LaunchBackupOutcome.deadline(for: size)])
    }

    /// ovation#613. Every named archive gets an answer, the size is measured
    /// once, and the launch waits ONE deadline for all of them.
    @Test("each archive checked by name gets an answer, under one wait for them all")
    func eachNamedArchiveIsCheckedUnderOneDeadline() async {
        let waits = RecordedWaits()
        let size = BackupSize(files: 4_000, bytes: 1_000_000_000)

        let checked = await LaunchBackupOutcome.recheck(
            ["a", "b"], now: Self.dayStartingAtTheFirst(of: 2),
            measuring: { size }, sleeping: waits.sleep) { .gone($0) }

        #expect(checked == [.gone("a"), .gone("b")])
        #expect(waits.durations == [LaunchBackupOutcome.deadlineFloor,
                                    LaunchBackupOutcome.deadline(for: size)])
    }

    /// N STUCK ARCHIVES COST ONE DEADLINE, NOT N. The re-check runs on the launch
    /// path before the store opens, so a wait per archive, one after another,
    /// held the launch for as many deadlines as there were broken archives on a
    /// share that had gone quiet (L110, L704). What finished before the deadline is
    /// kept; what did not comes round at a later launch.
    @Test("archives that never answer cost the launch one deadline between them")
    func stuckArchivesCostOneDeadline() async {
        let stuck = Stuck()
        let waits = DeadlineOnceOneIsStuck(stuck)
        let size = BackupSize(files: 4_000, bytes: 1_000_000_000)

        let checked = await LaunchBackupOutcome.recheck(
            ["a", "s1", "s2", "s3"], now: Self.dayStartingAtTheFirst(of: 4),
            measuring: { size }, sleeping: waits.sleep) { name in
                if name == "a" { return .verified(name) }
                stuck.block()
                return .verified(name)
            }
        stuck.release()

        #expect(checked == [.verified("a")])
        #expect(waits.deadlines == [LaunchBackupOutcome.deadline(for: size)])
    }

    /// WHERE THE NAMES START MOVES WITH THE DAY, like the rotation, so one archive
    /// that never answers cannot stand in front of the others on every launch.
    @Test("the first archive asked moves with the day")
    func theFirstAskedMovesWithTheDay() async {
        let asked = Asked()
        let first = Self.dayStartingAtTheFirst(of: 2)
        for day in 0..<2 {
            _ = await LaunchBackupOutcome.recheck(
                ["a", "b"], now: first.addingTimeInterval(Double(day) * 86_400),
                measuring: { BackupSize(files: 1, bytes: 1) }) { name in
                    asked.note(name)
                    return .verified(name)
                }
        }

        #expect(asked.names == ["a", "b", "b", "a"])
    }

    /// A day whose number is a multiple of `count`, so the names are asked in the
    /// order given.
    private static func dayStartingAtTheFirst(of count: Int) -> Date {
        var instant = Date(timeIntervalSinceReferenceDate: 800_000_000)
        while BusinessCalendar.dayNumber(for: instant) % count != 0 {
            instant = instant.addingTimeInterval(86_400)
        }
        return instant
    }

    private final class Asked: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [String] = []
        var names: [String] { lock.withLock { recorded } }
        func note(_ name: String) { lock.withLock { recorded.append(name) } }
    }

    /// Work that never answers until the test lets it go, and a record of whether
    /// any has started waiting.
    ///
    /// STARTED WAITING IS THE SIGNAL, not "a" returning. The names are asked one
    /// after another and each answer is kept before the next is asked, so the
    /// first stuck one starting means "a"'s answer is already kept. Signalling
    /// when "a" returned ended the wait before its answer was kept, a race.
    private final class Stuck: @unchecked Sendable {
        private let gate = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var reached = false
        var isWaiting: Bool { lock.withLock { reached } }
        func block() {
            lock.withLock { reached = true }
            gate.wait()
            gate.signal()
        }
        func release() { gate.signal() }
    }

    /// The measurement's wait never ends (it always answers first). Every other
    /// wait is recorded and ends as soon as a stuck archive has started, which is
    /// the deadline passing with the rest still stuck: no real time is
    /// paid, and nothing depends on how busy the machine is (L290).
    private final class DeadlineOnceOneIsStuck: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [Duration] = []
        private let stuck: Stuck
        init(_ stuck: Stuck) { self.stuck = stuck }
        var deadlines: [Duration] { lock.withLock { recorded } }

        var sleep: @Sendable (Duration) async throws -> Void {
            { [self] duration in
                if duration == LaunchBackupOutcome.deadlineFloor {
                    try await Task.sleep(for: .seconds(3_600))
                    return
                }
                lock.withLock { recorded.append(duration) }
                var polls = 0
                while !stuck.isWaiting, polls < 2_000 {
                    polls += 1
                    try await Task.sleep(for: .milliseconds(5))
                }
            }
        }
    }

    /// One that throws says nothing, as the rotation's does, and the rest are
    /// still asked.
    @Test("a named re-check that fails says nothing and the rest are still asked")
    func aFailingNamedRecheckSaysNothing() async {
        struct Refused: Error {}
        let checked = await LaunchBackupOutcome.recheck(
            ["a", "b"], now: Self.dayStartingAtTheFirst(of: 2),
            measuring: { BackupSize(files: 1, bytes: 1) }) { name in
                if name == "a" { throw Refused() }
                return .verified(name)
            }

        #expect(checked == [.nothingToCheck, .verified("b")])
    }

    @Test("no names asks nothing, not even the size")
    func noNamesAsksNothing() async {
        let waits = RecordedWaits()

        let checked = await LaunchBackupOutcome.recheck(
            [], now: Date(), measuring: { BackupSize(files: 1, bytes: 1) },
            sleeping: waits.sleep) {
                .verified($0)
            }

        #expect(checked.isEmpty)
        #expect(waits.durations.isEmpty)
    }

    /// Records every deadline a wait was given, then waits far longer than any
    /// test, so the work always answers first and the timer is cancelled.
    ///
    /// Read straight after `run` returns, and that is only sound because
    /// `BlockingWork.run` settles its timer first (ovation#572): these three cases
    /// read `.last` of a list the timer task had not always written yet, and one
    /// failed a pre-push run on 2026-09-26 with 5.0 seconds where 95.0 was due.
    private final class RecordedWaits: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [Duration] = []

        var durations: [Duration] {
            lock.withLock { recorded }
        }

        var sleep: @Sendable (Duration) async throws -> Void {
            { [self] duration in
                lock.withLock { recorded.append(duration) }
                try await Task.sleep(for: .seconds(3_600))
            }
        }
    }

    // MARK: the error the work threw is the error the launch sees (ovation#505)

    /// THROUGH THE REAL HELPER, not a hand built outcome. `BlockingWork` turns
    /// whatever the work throws into text, so a `noFolderChosen` thrown inside it
    /// reached the launch as a write failure "to noFolderChosen": a kind nothing
    /// resolves, under a sentence naming a folder that does not exist, while the
    /// notice built to clear itself was never raised at all (L11, L199). Every case
    /// above hands `attempt(from:)` an outcome, which is exactly why none of them
    /// could see it.
    @Test("a backup error thrown by the work reaches the launch as itself",
          arguments: [BackupError.noFolderChosen,
                      .requiredMemberMissing("Ovation.store.version"),
                      .verificationFailed([]),
                      .couldNotWrite("/Volumes/Backups: the disk is full")])
    func aBackupErrorArrivesIntact(error: BackupError) async {
        await #expect(throws: error) {
            try await LaunchBackupOutcome.run(at: Self.launch, measuring: { .init(files: 0, bytes: 0) },
                                              recording: { _ in }) { throw error }
        }
    }

    @Test("an error from the work that is not a backup error is a write failure carrying its text")
    func anyOtherErrorIsAWriteFailure() async {
        struct Unexpected: Error, CustomStringConvertible {
            var description: String { "the volume went away" }
        }
        await #expect(throws: BackupError.couldNotWrite("the volume went away")) {
            try await LaunchBackupOutcome.run(at: Self.launch, measuring: { .init(files: 0, bytes: 0) },
                                              recording: { _ in }) { throw Unexpected() }
        }
    }

    @Test("work that answers is the answer, through the real helper")
    func workThatAnswersPassesThrough() async throws {
        let taken = BackupService.Attempt.taken(URL(fileURLWithPath: "/tmp/a"), retention: .ran(.init()))

        #expect(try await LaunchBackupOutcome.run(at: Self.launch, measuring: { .init(files: 0, bytes: 0) },
                                              recording: { _ in }) { taken } == taken)
    }

    @Test("a re-check that answered is the answer")
    func reverificationPassesThrough() {
        let failed = BackupService.Reverification.failed("Ovation-backup-2026-03-02-090000", [])

        #expect(LaunchBackupOutcome.reverification(from: .answered(failed)) == failed)
    }

    /// AND ONE THAT COULD NOT FINISH SAYS NOTHING, deliberately: it is a sweep
    /// over OLD archives, what it missed comes round on a later launch, and
    /// today's backup is unaffected either way (L36).
    @Test("a re-check that failed or was abandoned says nothing rather than alarming")
    func reverificationStaysQuiet() {
        #expect(LaunchBackupOutcome.reverification(from: .failed("a disk")) == .nothingToCheck)
        #expect(LaunchBackupOutcome.reverification(
            from: .gaveUp(after: .seconds(5))) == .nothingToCheck)
    }
}
