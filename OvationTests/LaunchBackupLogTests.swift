import Foundation
import Testing

/// ovation#557. Every launch backup leaves a line saying how big it was, how long
/// it took and the deadline it was given, so the allowances in
/// LaunchBackupOutcome.swift can be re-judged from Dan's real backups rather than
/// the synthetic folder they were calibrated on (L354).
struct LaunchBackupLogTests {

    private static let launch = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: the launch backup records itself

    /// THE WHOLE LINE, from the real helper, with the clock injected so the
    /// elapsed time is a value the test chose rather than whatever the machine
    /// took (L524).
    @Test("a backup that copied records its size, how long it took, and the deadline it was given")
    func aTakenBackupRecordsItsTiming() async throws {
        let clock = SteppingClock(step: .milliseconds(1_250))
        let recorded = Recorded()
        let size = BackupSize(files: 19, bytes: 372_000)
        let taken = BackupService.Attempt.taken(URL(fileURLWithPath: "/tmp/a"))

        let attempt = try await LaunchBackupOutcome.run(
            at: Self.launch,
            measuring: { size },
            sleeping: Self.neverFires,
            clock: clock.now,
            recording: recorded.record) { taken }

        #expect(attempt == taken)
        let timing = try #require(recorded.only)
        #expect(timing == LaunchBackupTiming(
            at: Self.launch, size: size, elapsed: .milliseconds(1_250),
            deadline: LaunchBackupOutcome.deadline(for: size), outcome: .taken))
    }

    /// EACH WAY THE STEP COMES BACK IS RECORDED AS ITSELF. Only `taken` timed a
    /// whole copy, so a record that called a skip or a refusal a backup would read
    /// as more headroom than there is (L331).
    @Test("every way the backup comes back is recorded, and says which it was",
          arguments: RecordedCase.allCases)
    func everyOutcomeIsRecorded(_ recordedCase: RecordedCase) async throws {
        let recorded = Recorded()
        let firesAtOnce: @Sendable (Duration) async throws -> Void = { _ in }

        _ = try? await LaunchBackupOutcome.run(
            at: Self.launch,
            measuring: { .init(files: 1, bytes: 1) },
            sleeping: recordedCase == .gaveUp ? firesAtOnce : Self.neverFires,
            clock: SteppingClock(step: .milliseconds(10)).now,
            recording: recorded.record,
            recordedCase.work)

        #expect(recorded.only?.outcome == recordedCase.expected)
    }

    enum RecordedCase: String, CaseIterable, Sendable {
        case taken, alreadyTakenToday, folderUnreachable, refused, failed, gaveUp

        var expected: LaunchBackupTiming.Outcome {
            LaunchBackupTiming.Outcome(rawValue: rawValue)!
        }

        var work: @Sendable () throws -> BackupService.Attempt {
            switch self {
            case .taken: return { .taken(URL(fileURLWithPath: "/tmp/a")) }
            case .alreadyTakenToday: return { .alreadyTakenToday(URL(fileURLWithPath: "/tmp/a")) }
            case .folderUnreachable: return { .folderUnreachable("/Volumes/Backups: not mounted") }
            case .refused: return { throw BackupError.noFolderChosen }
            case .failed:
                struct Unexpected: Error {}
                return { throw Unexpected() }
            case .gaveUp:
                return {
                    // Held past the deadline, which fires at once, and then let
                    // go so no thread is left parked after the test.
                    Thread.sleep(forTimeInterval: 0.2)
                    return .taken(URL(fileURLWithPath: "/tmp/a"))
                }
            }
        }
    }

    /// A SIZE THAT COULD NOT BE READ IS RECORDED AS UNREAD, and with the floor it
    /// was actually given, never as an empty folder: a zero there would read as a
    /// measurement (L90).
    @Test("a size that could not be read records no size and the floor")
    func anUnreadSizeRecordsNoSize() async throws {
        struct Unreadable: Error {}
        let recorded = Recorded()

        _ = try await LaunchBackupOutcome.run(
            at: Self.launch,
            measuring: { throw Unreadable() },
            sleeping: Self.neverFires,
            clock: SteppingClock(step: .milliseconds(10)).now,
            recording: recorded.record) { .taken(URL(fileURLWithPath: "/tmp/a")) }

        let timing = try #require(recorded.only)
        #expect(timing.files == nil)
        #expect(timing.bytes == nil)
        #expect(Duration.milliseconds(timing.deadlineMilliseconds)
                    == LaunchBackupOutcome.deadlineFloor)
    }

    // MARK: the record itself

    @Test("the record keeps every timing it was given, oldest first")
    func theRecordRoundTrips() throws {
        let world = try World()
        let first = LaunchBackupTiming(at: Self.launch, size: .init(files: 19, bytes: 372_000),
                                       elapsed: .milliseconds(80), deadline: .seconds(5),
                                       outcome: .taken)
        let second = LaunchBackupTiming(at: Self.launch.addingTimeInterval(86_400), size: nil,
                                        elapsed: .seconds(5), deadline: .seconds(5),
                                        outcome: .gaveUp)

        try world.log.append(first)
        try world.log.append(second)

        let loaded = try world.log.load()
        #expect(loaded.timings == [first, second])
        #expect(loaded.skipped == 0)
    }

    /// A DAMAGED LINE COSTS THAT LINE, and is counted (L215).
    @Test("a line that does not decode costs that line and is counted, never the record")
    func aDamagedLineIsCounted() throws {
        let world = try World()
        let timing = LaunchBackupTiming(at: Self.launch, size: .init(files: 1, bytes: 1),
                                        elapsed: .milliseconds(1), deadline: .seconds(5),
                                        outcome: .taken)
        try world.log.append(timing)
        let handle = try FileHandle(forWritingTo: world.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{not a timing\n".utf8))
        try handle.close()
        try world.log.append(timing)

        let loaded = try world.log.load()
        #expect(loaded.timings == [timing, timing])
        #expect(loaded.skipped == 1)
    }

    /// WHAT A LAUNCH DOES WITH ITS TIMING, both ways: written where there is a
    /// record, and a failure handed back rather than thrown into the launch or
    /// swallowed (L632, L98).
    @Test("a launch's timing is appended to the record it is given")
    func aLaunchRecordsItsTiming() throws {
        let world = try World()
        let timing = LaunchBackupTiming(at: Self.launch, size: .init(files: 2, bytes: 3),
                                        elapsed: .milliseconds(4), deadline: .seconds(5),
                                        outcome: .taken)

        #expect(LaunchBackupLog.record(timing, to: world.url) == nil)
        #expect(try world.log.load().timings == [timing])
    }

    @Test("a record that cannot be written is handed back as a write failure, and the launch goes on")
    func anUnwritableRecordIsHandedBack() throws {
        let world = try World()
        // A DIRECTORY where the file should be: the append cannot open it, which
        // is a real failure reached without damaging anything.
        try FileManager.default.createDirectory(at: world.url, withIntermediateDirectories: true)
        let timing = LaunchBackupTiming(at: Self.launch, size: nil, elapsed: .zero,
                                        deadline: .seconds(5), outcome: .gaveUp)

        let failure = LaunchBackupLog.record(timing, to: world.url)

        guard case .couldNotWrite = failure else {
            Issue.record("an unwritable record came back as \(String(describing: failure))")
            return
        }
    }

    @Test("a disposable launch has no record, and writing to none is not a failure")
    func noRecordIsNotAFailure() {
        let timing = LaunchBackupTiming(at: Self.launch, size: nil, elapsed: .zero,
                                        deadline: .seconds(5), outcome: .taken)
        #expect(LaunchBackupLog.record(timing, to: nil) == nil)
    }

    /// THE SAMPLE THE REPORT SCRIPT IS TESTED ON IS THE FORMAT SWIFT WRITES. The
    /// reader is Python and the writer is Swift, so one committed file is what both
    /// are held to, and each line here must decode AND re-encode to itself, or the
    /// script's suite is measuring a format nothing writes (L26, L52).
    @Test("the committed sample the report is tested on is exactly what the record writes")
    func theCommittedSampleIsTheWrittenFormat() throws {
        let sample = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "integration/launch-backups-sample.jsonl")
        let lines = try String(contentsOf: sample, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        try #require(lines.count >= 4, "the sample holds \(lines.count) lines")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var outcomes = Set<LaunchBackupTiming.Outcome>()
        for line in lines {
            let timing = try decoder.decode(LaunchBackupTiming.self, from: Data(line.utf8))
            #expect(try LaunchBackupLog.line(for: timing) == line)
            outcomes.insert(timing.outcome)
        }
        // The sample has to carry what the report must tell apart, or its suite
        // cannot see the report counting a skip as a backup.
        #expect(outcomes.isSuperset(of: [.taken, .alreadyTakenToday, .gaveUp]))
    }

    // MARK: where it lives

    @Test("a disposable launch is refused the live record, and a real one is given the data folder")
    func theLiveRecordRefusesADisposableLaunch() {
        let root = URL(fileURLWithPath: "/tmp/appsupport")
        #expect(LaunchBackupLog.liveLaunchBackupRecord(
            appSupport: root, isDebugBuild: false, isDisposableLaunch: true) == nil)
        #expect(LaunchBackupLog.liveLaunchBackupRecord(
            appSupport: root, isDebugBuild: false, isDisposableLaunch: false)?.path
                == "/tmp/appsupport/Ovation/launch-backups.jsonl")
    }

    /// THE FLOOR NAMES IT AS BUILT, so the register that notices a live resolver
    /// with no refusal measures the world that ships (L96).
    @Test("the isolation floor names the record as built")
    func theFloorNamesTheRecord() {
        let entry = LiveDataFloor.entries.first { $0.name == "liveLaunchBackupRecord" }
        #expect(entry?.resolve != nil)
        #expect(entry?.issue == nil)
    }

    /// CARRIED BY EVERY BACKUP, and not required: a data folder that has never
    /// been backed up at launch legitimately has no record yet.
    @Test("an archive carries the record whenever it is there, and does not require it")
    func theBackupCarriesTheRecord() throws {
        let member = try #require(BackupPlan.members.first { $0.path == LaunchBackupLog.filename })
        #expect(member.kind == .file)
        guard case .presentSometimes = member.expectation else {
            Issue.record("the record is \(member.expectation), not presentSometimes")
            return
        }
    }

    // MARK: fixtures

    private static let neverFires: @Sendable (Duration) async throws -> Void = { _ in
        try await Task.sleep(for: .seconds(3_600))
    }

    /// Answers a later instant each time it is asked, `step` apart.
    private final class SteppingClock: @unchecked Sendable {
        private let lock = NSLock()
        private var current = ContinuousClock.now
        private let step: Duration

        init(step: Duration) { self.step = step }

        var now: @Sendable () -> ContinuousClock.Instant {
            { [self] in
                lock.withLock {
                    defer { current = current.advanced(by: step) }
                    return current
                }
            }
        }
    }

    private final class Recorded: @unchecked Sendable {
        private let lock = NSLock()
        private var timings: [LaunchBackupTiming] = []

        var record: @Sendable (LaunchBackupTiming) -> Void {
            { [self] timing in lock.withLock { timings.append(timing) } }
        }

        /// The one timing recorded, or nil when there was not exactly one: a
        /// launch that recorded twice would count one backup as two (L467).
        var only: LaunchBackupTiming? {
            lock.withLock { timings.count == 1 ? timings[0] : nil }
        }
    }

    private struct World {
        let url: URL
        let log: LaunchBackupLog

        init() throws {
            let directory = URL.temporaryDirectory
                .appending(path: "ovation-launch-backups-\(UUID().uuidString)",
                           directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            url = directory.appending(path: LaunchBackupLog.filename)
            log = LaunchBackupLog(url: url)
        }
    }
}
