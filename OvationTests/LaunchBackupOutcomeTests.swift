import Foundation
import Testing

/// ovation#246. Turning what `BlockingWork` came back with into what the launch
/// does, which is a decision each way and used to live in the one file no test
/// here can compile.
struct LaunchBackupOutcomeTests {

    @Test("a backup that answered is the answer")
    func answeredPassesThrough() throws {
        let taken = BackupService.Attempt.taken(URL(fileURLWithPath: "/tmp/a"))

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
        let taken = BackupService.Attempt.taken(URL(fileURLWithPath: "/tmp/a"))
        let size = BackupSize(files: 4_000, bytes: 1_000_000_000)

        let attempt = try await LaunchBackupOutcome.run(
            measuring: { size },
            sleeping: waits.sleep) { taken }

        #expect(attempt == taken)
        #expect(waits.durations.last == LaunchBackupOutcome.deadline(for: size),
                "\(waits.durations)")
    }

    /// A MEASUREMENT THAT FAILS DOES NOT STOP THE BACKUP. Whatever stopped the size
    /// being read will stop the backup too, and the backup is what names it; here
    /// the launch simply waits the floor, which is what it did before (L93).
    @Test("a size that could not be measured leaves the backup the floor, and the backup still runs")
    func anUnmeasuredSizeWaitsTheFloor() async throws {
        struct Unreadable: Error {}
        let waits = RecordedWaits()
        let taken = BackupService.Attempt.taken(URL(fileURLWithPath: "/tmp/a"))

        let attempt = try await LaunchBackupOutcome.run(
            measuring: { throw Unreadable() },
            sleeping: waits.sleep) { taken }

        #expect(attempt == taken)
        #expect(waits.durations.last == LaunchBackupOutcome.deadlineFloor, "\(waits.durations)")
    }

    /// AND A BACKUP STILL RUNNING AT THAT DEADLINE COMES OUT AS STILL RUNNING,
    /// through the real helper rather than a hand built outcome.
    @Test("a backup still running at its deadline reaches the launch as still running")
    func aSlowBackupIsStillRunning() async {
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }

        await #expect(throws: BackupError.stillRunning(after: LaunchBackupOutcome.deadlineFloor)) {
            try await LaunchBackupOutcome.run(
                measuring: { .init(files: 0, bytes: 0) },
                sleeping: { _ in }) {
                    release.wait()
                    return .taken(URL(fileURLWithPath: "/tmp/a"))
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
        #expect(waits.durations.last == LaunchBackupOutcome.deadline(for: size),
                "\(waits.durations)")
    }

    /// Records every deadline a wait was given, then waits far longer than any
    /// test, so the work always answers first and the timer is cancelled.
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
            try await LaunchBackupOutcome.run(measuring: { .init(files: 0, bytes: 0) }) { throw error }
        }
    }

    @Test("an error from the work that is not a backup error is a write failure carrying its text")
    func anyOtherErrorIsAWriteFailure() async {
        struct Unexpected: Error, CustomStringConvertible {
            var description: String { "the volume went away" }
        }
        await #expect(throws: BackupError.couldNotWrite("the volume went away")) {
            try await LaunchBackupOutcome.run(measuring: { .init(files: 0, bytes: 0) }) { throw Unexpected() }
        }
    }

    @Test("work that answers is the answer, through the real helper")
    func workThatAnswersPassesThrough() async throws {
        let taken = BackupService.Attempt.taken(URL(fileURLWithPath: "/tmp/a"))

        #expect(try await LaunchBackupOutcome.run(measuring: { .init(files: 0, bytes: 0) }) { taken } == taken)
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
