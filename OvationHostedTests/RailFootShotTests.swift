// ovation#99 and ovation#566. Pictures of the rail's foot as Dan settled it, in the
// real window at its minimum height, so the lines and their Reads can be judged by
// looking rather than described (L606).
//
// THREE MOMENTS, the ones the decision round drew: two open things, three (so the
// third becomes "and 1 more"), and one. Plus what Read and "and N more" open, on
// their own, because a popover is its own window and the camera cannot see it over
// the shell.
//
// SAME CAMERA AS THE OTHER SHOT SUITES. OPT IN, AND IT SAYS WHEN IT DID NOTHING (L98).
import AppKit
import SwiftUI
import Testing
@testable import Ovation

@MainActor
struct RailFootShotTests {

    private static var outputDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        let named = environment["OVATION_SHOT_DIR"]
            ?? environment["TEST_RUNNER_OVATION_SHOT_DIR"] ?? ""
        return named.isEmpty ? nil : URL(fileURLWithPath: named)
    }

    /// The window at the height the shell refuses to go below, where the foot has
    /// least room.
    private static let size = CGSize(width: 1064, height: OvationWindow.minimumHeight)

    private static func at(_ second: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(second))
    }

    private static func shell(_ problems: ProblemsStore) -> ShellView {
        ShellView(shell: ShellPresenter(selected: .invoices, rosterHasWork: { false }),
                  roster: RosterPresenter(clients: [], write: { _, _ in }),
                  problems: problems, now: { at(99) })
    }

    @Test("the foot is captured with one, two and three open things, and what Read opens")
    func captureTheFoot() throws {
        guard let directory = Self.outputDirectory else {
            print("RAIL FOOT SHOTS: no TEST_RUNNER_OVATION_SHOT_DIR, so nothing was captured.")
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let problems = ProblemsStore(journal: InMemoryProblemsJournal())
        _ = problems.raise(kind: .backupsAreStale, subject: "store",
                           sentence: "Your work on 2026-09-23 is in no backup: the newest was "
                               + "taken on 2026-09-20.", now: Self.at(1))
        try OffscreenShot.capture(Self.shell(problems), size: Self.size, scheme: .light,
                                  to: directory.appending(path: "foot-one.png"))

        let export = problems.raise(
            kind: .exportWritten, subject: "year-end-export-2026",
            sentence: "The 2026 export is written: income.csv, expenses.csv, manifest.json in "
                + "/Users/someone/Library/Application Support/Ovation/exports. Every row was "
                + "read back off the disk and reconciled against a second reading of the store "
                + "before this was said.", now: Self.at(2))
        try OffscreenShot.capture(Self.shell(problems), size: Self.size, scheme: .light,
                                  to: directory.appending(path: "foot-two.png"))

        _ = problems.raise(kind: .storeVersionNotRecorded, subject: "store",
                           sentence: "Ovation could not record which version of itself opened "
                               + "this database.", now: Self.at(3))
        try OffscreenShot.capture(Self.shell(problems), size: Self.size, scheme: .light,
                                  to: directory.appending(path: "foot-three.png"))

        try OffscreenShot.capture(Self.shell(problems).everything(),
                                  size: CGSize(width: 320, height: 460), scheme: .light,
                                  to: directory.appending(path: "foot-more-opens.png"))

        let reading = FootReading(sentence: export.sentence, done: {})
        try OffscreenShot.capture(reading, size: CGSize(width: 300, height: 220), scheme: .light,
                                  to: directory.appending(path: "foot-read-opens.png"))

        #expect(RailFoot.lines(for: problems.open).more == 1)
        print("RAIL FOOT SHOTS: wrote five pictures into \(directory.path)")
    }

    /// ovation#609. Two broken backups open at once, each named for its archive's day,
    /// in both appearances, so the lines can be judged by looking as well as measured.
    @Test("the foot is captured with two broken backups told apart by their days")
    func captureTwoBrokenBackups() throws {
        guard let directory = Self.outputDirectory else {
            print("RAIL FOOT SHOTS: no TEST_RUNNER_OVATION_SHOT_DIR, so nothing was captured.")
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let problems = ProblemsStore(journal: InMemoryProblemsJournal())
        _ = problems.raise(kind: .archiveNoLongerVerifies,
                           subject: "Ovation-backup-2026-05-30-210000",
                           sentence: "The backup from 30 May 2026 no longer checks out.",
                           now: Self.at(1))
        _ = problems.raise(kind: .archiveNoLongerVerifies,
                           subject: "Ovation-backup-2026-09-28-210000",
                           sentence: "The backup from 28 Sep 2026 no longer checks out.",
                           now: Self.at(2))
        for scheme in [ColorScheme.light, .dark] {
            try OffscreenShot.capture(Self.shell(problems), size: Self.size, scheme: scheme,
                                      to: directory.appending(
                                        path: "foot-two-backups-\(scheme == .light ? "light" : "dark").png"))
        }
        print("RAIL FOOT SHOTS: wrote two broken backup pictures into \(directory.path)")
    }
}
