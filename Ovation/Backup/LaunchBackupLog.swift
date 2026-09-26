// ovation#557. A durable record of how big each launch backup was, how long it
// took, and how long the launch was prepared to wait for it.
//
// WHY IT EXISTS. The launch backup's deadline (ovation#507) grows with what it
// copies, from allowances calibrated on a synthetic 300MB folder and on
// BackupCostTests, never on Dan's real backups. Past that deadline a launch that
// would upgrade the store REFUSES to open (ovation#505), so headroom shrinking as
// receipts accumulate, or a folder that has become slow, would first be seen as a
// refusal nobody can explain. A calibration measured once under represents the
// data as it grows, and it fails green (L354). This is the measurement taken on
// every real launch instead, so the allowances in LaunchBackupOutcome.swift can be
// re-judged from what actually happened.
//
// EVERY OUTCOME IS RECORDED, and each says which it was. A backup that was
// already taken today did almost nothing, and one that refused or gave up did not
// finish the copy, so a reader that timed them all alike would read a skip as a
// fast backup and understate how tight the real ones are (L331). The reader,
// `scripts/report-launch-backups.sh`, judges headroom from `taken` alone and
// counts the rest beside it.
//
// APPEND ONLY, one JSON object per line, through the same file mechanics as the
// problems journal and the export run record, for the same reason: a file holding
// a summary would be a read, modify, write cycle that erases itself the first time
// its read fails (L105).
//
// INSIDE THE ISOLATION FLOOR (ovation#58). The resolver refuses a disposable
// launch, so a test's timing can never land in the record and pass for Dan's.
import Foundation
import os

/// One launch backup, as the record keeps it.
struct LaunchBackupTiming: Codable, Equatable, Sendable {
    /// What the backup step came back with. Kept apart because only `taken`
    /// timed a whole copy (L331).
    enum Outcome: String, Codable, Sendable, CaseIterable {
        /// A backup was written and verified: the one outcome that times the work.
        case taken
        /// Today's backup already existed, so almost nothing was done.
        case alreadyTakenToday
        /// The folder could not be read, so nothing was copied.
        case folderUnreachable
        /// The backup threw one of its own refusals.
        case refused
        /// Something that is not a backup refusal stopped it.
        case failed
        /// The launch stopped waiting at the deadline. The copy may still be
        /// running, so its elapsed time is a lower bound, never a measurement.
        case gaveUp
    }

    /// The launch's own instant, the same one every other step was given.
    let at: Date
    /// What was measured before the wait was sized. Nil when the size could not
    /// be read, which is also the one case given the floor rather than a size.
    let files: Int?
    let bytes: Int?
    /// From the moment the wait began until it ended, in milliseconds.
    let elapsedMilliseconds: Int
    /// The deadline the wait was given, in milliseconds.
    let deadlineMilliseconds: Int
    let outcome: Outcome

    init(at: Date, size: BackupSize?, elapsed: Duration, deadline: Duration, outcome: Outcome) {
        self.at = at
        self.files = size?.files
        self.bytes = size?.bytes
        self.elapsedMilliseconds = Self.milliseconds(elapsed)
        self.deadlineMilliseconds = Self.milliseconds(deadline)
        self.outcome = outcome
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds) * 1_000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}

enum LaunchBackupLogError: Error, Equatable {
    case couldNotWrite(String)
    case couldNotRead(String)
}

/// The append only record of every launch backup.
struct LaunchBackupLog {
    /// The filename `BackupPlan` declares, so an archive carries it, and the one
    /// `scripts/report-launch-backups.sh` reads.
    static let filename = "launch-backups.jsonl"

    private let file: AppendOnlyLineFile

    init(url: URL, fileManager: FileManager = .default) {
        file = AppendOnlyLineFile(url: url, fileManager: fileManager)
    }

    /// Where a real launch keeps it, or nil when this launch may not touch
    /// anything real (plan 1.9, the isolation floor). The default arguments read
    /// THIS process, so a caller that passes nothing is refused rather than
    /// handed the real path.
    static func liveLaunchBackupRecord(
        appSupport: URL = StoreLocation.appSupport,
        isDebugBuild: Bool = StoreLocation.isDebugBuild,
        isDisposableLaunch: Bool = AppEnvironment.isDisposableLaunch()
    ) -> URL? {
        guard !isDisposableLaunch else { return nil }
        return StoreLocation.dataDirectory(appSupport: appSupport, isDebugBuild: isDebugBuild)
            .appendingPathComponent(filename)
    }

    /// One line, exactly as `append` writes it. Keys sorted and dates in ISO
    /// 8601, so the line is the same on every run and readable without Swift.
    static func line(for timing: LaunchBackupTiming) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let line = String(data: try encoder.encode(timing), encoding: .utf8) else {
            throw LaunchBackupLogError.couldNotWrite("the timing did not encode as text")
        }
        return line
    }

    /// What a launch does with its timing: appends it to the record at `url`, and
    /// does nothing at all when there is none, which is a disposable launch.
    ///
    /// A RECORD THAT COULD NOT BE WRITTEN NEVER STOPS THE LAUNCH. Its only job is
    /// to report, and a report that could not be delivered says nothing about the
    /// backup being unsafe (L632). It is not swallowed either: it goes to the
    /// unified log as a fault and is handed back, so a caller can see it and a
    /// test can drive it, rather than a quiet gap in the record reading as a
    /// launch that never backed up (L98). No notice is raised: a missing timing is
    /// nothing Dan can act on, and a notice about it would teach him to skip the
    /// list (L36).
    @discardableResult
    static func record(_ timing: LaunchBackupTiming,
                       to url: URL? = liveLaunchBackupRecord()) -> LaunchBackupLogError? {
        guard let url else { return nil }
        do {
            try LaunchBackupLog(url: url).append(timing)
            return nil
        } catch {
            let failure = (error as? LaunchBackupLogError)
                ?? .couldNotWrite(String(describing: error))
            logger.fault("The launch backup timing was not recorded: \(String(describing: failure), privacy: .public)")
            return failure
        }
    }

    private static let logger = Logger(subsystem: "com.danwright.ovation", category: "launch-backup")

    func append(_ timing: LaunchBackupTiming) throws {
        let line = try Self.line(for: timing)
        do {
            try file.append(line)
        } catch let error as AppendOnlyLineFileError {
            switch error {
            case .couldNotWrite(let detail), .couldNotRead(let detail):
                throw LaunchBackupLogError.couldNotWrite(detail)
            }
        }
    }

    /// Every timing, oldest first. A line that does not decode costs that line,
    /// never the file, and it is COUNTED, because a record quietly returning fewer
    /// entries than it holds has the same shape as one returning none (L215).
    func load() throws -> (timings: [LaunchBackupTiming], skipped: Int) {
        let lines: [String]
        do {
            lines = try file.lines()
        } catch let error as AppendOnlyLineFileError {
            switch error {
            case .couldNotRead(let detail), .couldNotWrite(let detail):
                throw LaunchBackupLogError.couldNotRead(detail)
            }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var timings: [LaunchBackupTiming] = []
        var skipped = 0
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let timing = try? decoder.decode(LaunchBackupTiming.self, from: data) else {
                skipped += 1
                continue
            }
            timings.append(timing)
        }
        return (timings, skipped)
    }
}
