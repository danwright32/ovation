// ovation#222. THE DIRECTORIES A BACKUP REQUIRES, MADE BY SOMETHING.
//
// `BackupPlan.members` declares `documents` and `custody` as `.required`, and
// `BackupService.takeBackup` refuses before doing anything else when a required
// member is absent. Nothing in the app created either one. `DocumentStore` makes
// `documents` on the first byte written through it, and nothing writes a
// document until ovation#78; nothing creates `custody` at all.
//
// Measured 2026-09-11 on Dan's Mac: `Application Support/Ovation/` held
// `booking-queue`, `custody` and `downbeat-queued-bookings.json`. So the day
// ovation#225 supplies a real backup folder, every launch would have raised a
// failure about a directory Dan has no way to create, for months, and the
// feature would have shipped dead. Both backup fixtures build those directories
// before running, which is why the suite was green throughout (L48).
//
// WHY CREATE THEM RATHER THAN DOWNGRADE THE EXPECTATION. `documents` absent once
// receipts exist is genuinely alarming, and `presentSometimes` would make that
// state read as legitimate for ever, which is the reassuring direction (L63).
// Creating it empty keeps the requirement true and loses nothing: the safeguard
// against receipts actually going missing is the reference check ovation#104
// built into `verify`, never the directory's existence.
//
// WHY IT IS DERIVED FROM THE PLAN rather than naming the two directories known
// today. A required directory added later would otherwise be created by nothing,
// and this whole issue is what that costs (L41, L96).
//
// WHERE IT RUNS. `StoreLaunchSequence`, after identify and checkpoint and
// immediately before the backup. Not earlier: the identify step's refusal says
// "Nothing has been opened or changed", and making directories beside a store
// that turned out to be somebody else's would make that sentence false.
import Foundation

enum DataDirectory {

    /// The directories `BackupPlan` requires, in the order it declares them.
    ///
    /// Derived rather than listed, so this and the plan cannot drift.
    static var requiredDirectories: [String] {
        BackupPlan.members
            .filter { $0.kind == .directory && $0.expectation == .required }
            .map(\.path)
    }

    /// Make every required directory, if it is not already there.
    ///
    /// IT RUNS ON EVERY LAUNCH, so it must be ordinary the second time and must
    /// never empty anything: a step that cleared the documents folder would
    /// destroy exactly what the backup exists to carry (L5). `createDirectory`
    /// with `withIntermediateDirectories` is both of those.
    ///
    /// IT REFUSES IN THE BACKUP'S OWN VOCABULARY, so the sentence Dan reads is
    /// the one `StoreLaunchSequence.backupSentence(for:)` already writes for a
    /// backup that could not be written (L11). A data directory that cannot hold
    /// directories is a backup that cannot happen; calling it anything else would
    /// be a second name for one condition.
    static func prepare(_ dataDirectory: URL,
                        fileManager: FileManager = .default) throws {
        for name in requiredDirectories {
            let directory = dataDirectory.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else {
                    // A FILE standing where a required directory belongs. Neither
                    // creating nor deleting is right: one fails and the other
                    // destroys something nobody here can identify (L5).
                    throw BackupError.couldNotWrite(directory.path)
                }
                continue
            }
            do {
                try fileManager.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
            } catch {
                throw BackupError.couldNotWrite(directory.path)
            }
        }
    }
}
