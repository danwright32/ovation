import Foundation
import Testing

/// ovation#225. WHERE THE BACKUPS GO, REMEMBERED ACROSS LAUNCHES.
///
/// `BackupService` takes a folder it is HANDED, and until now nothing decided
/// which one: `OvationApp` injected a closure that always threw "no backup folder
/// has been chosen yet". This is the thing that chooses.
///
/// ONE CORRECTION TO ovation#87's FRAMING, measured rather than argued. It asks
/// for the choice to be remembered "as a security scoped bookmark so the grant
/// survives a relaunch". Ovation is not sandboxed (`project.yml:
/// ENABLE_APP_SANDBOX: NO`). Measured 2026-09-11 with a standalone program: such
/// a bookmark does still resolve outside the sandbox and
/// `startAccessingSecurityScopedResource()` returns true, so the mechanism works.
/// It is not what grants access. Outside the sandbox the grant is given by the
/// system to the code identity, which is why ovation#9 made the signing identity
/// stable. The bookmark's real job is remembering WHERE the folder is when it
/// moves or is renamed, which a stored path cannot do.
@MainActor
struct BackupFolderSettingTests {

    @Test("a folder that was chosen is the folder that comes back")
    func remembersTheChosenFolder() throws {
        let world = try World()

        try world.setting.remember(world.folder)

        #expect(world.setting.resolve() == .chosen(world.folder.standardizedFileURL))
    }

    /// NOTHING CHOSEN IS ITS OWN ANSWER, not an error and not a guess. It is the
    /// state every installation starts in, and ovation#229 gives it a standing
    /// condition of its own rather than a failure.
    @Test("a folder that was never chosen answers so, and names no folder")
    func nothingChosenIsItsOwnAnswer() throws {
        let world = try World()

        #expect(world.setting.resolve() == .notChosen)
    }

    /// A BOOKMARK THAT CANNOT BE RESOLVED IS A NAMED REFUSAL, never a fall back
    /// to some default folder. A tool handed a target it cannot use must not
    /// quietly write somewhere else (L320, L75): the whole point of the folder is
    /// that Dan chose where his records are copied.
    @Test("a folder that has gone is refused by name, and no other folder is used")
    func aFolderThatHasGoneIsRefused() throws {
        let world = try World()
        try world.setting.remember(world.folder)
        try FileManager.default.removeItem(at: world.folder)

        let resolution = world.setting.resolve()

        guard case .unresolvable(let detail) = resolution else {
            Issue.record("expected a named refusal, got \(resolution)")
            return
        }
        #expect(!detail.isEmpty)
    }

    /// IT RESOLVES WITHOUT MOUNTING ANYTHING, and that is what makes it safe to
    /// ask on the launch path. `URL(resolvingBookmarkData:)` against an unmounted
    /// share asks the system to mount it, which can block for as long as the
    /// network takes, and the launch sequence runs inside `OvationApp.init()`
    /// before any window exists: a blocked resolve is a launch that hangs with
    /// nothing on screen and no way to cancel (L236, L241, L110).
    ///
    /// Choosing not to mount turns that into a fast, named refusal, which is
    /// stronger than moving the same blocking call to another thread.
    @Test("resolving never asks the system to mount anything")
    func resolvingDoesNotMount() throws {
        let world = try World()
        try world.setting.remember(world.folder)

        #expect(world.setting.resolvesWithoutMounting)
    }

    // MARK: the isolation floor, on the way out as well as in

    /// A SEAM THAT KEEPS A TEST OFF LIVE DATA ON THE WAY IN DOES NOT COVER THE
    /// WAY OUT (L201). The read side refusing is not enough: `remember` writes,
    /// and a test that rendered a settings pane would write Dan's real choice.
    @Test("a disposable launch cannot WRITE a folder choice")
    func aDisposableLaunchCannotWrite() throws {
        let world = try World(disposable: true)

        #expect(throws: BackupFolderSetting.Refusal.self) {
            try world.setting.remember(world.folder)
        }
    }

    @Test("a disposable launch cannot READ one either")
    func aDisposableLaunchCannotRead() throws {
        let world = try World()
        try world.setting.remember(world.folder)
        let disposable = BackupFolderSetting(defaults: world.defaults,
                                             isDisposableLaunch: { true })

        #expect(disposable.resolve() == .refusedUnderADisposableLaunch)
    }

    /// AND THE REFUSAL IS NOT THE SAME AS HAVING NOTHING. A test run that reads
    /// "no folder chosen" would raise the standing condition and look exactly
    /// like Dan's own machine before he has chosen one (L98, L11).
    @Test("the disposable refusal is distinct from nothing having been chosen")
    func theRefusalIsNotTheSameAsNotChosen() throws {
        let world = try World(disposable: true)

        #expect(world.setting.resolve() != .notChosen)
    }

    /// THE LIVE RESOLVER REFUSES HERE, and this suite is the proof: every test
    /// run IS a disposable launch, so asking for the live folder must answer
    /// nothing. Without this the floor entry would be a declaration nothing
    /// exercises, which is the state ovation#58 exists to end (L3).
    @Test("the live backups directory answers nothing under a test run")
    func theLiveResolverRefusesUnderATestRun() {
        #expect(AppEnvironment.isDisposableLaunch())
        #expect(BackupFolderSetting.liveBackupsDirectory == nil)
    }

    // MARK: which build may back up at all (ovation#228)

    /// THE DEBUG BUILD NEVER BACKS UP (Dan, 2026-09-11). Its store is throwaway,
    /// so backing it up protects nothing, and nothing stops the same folder being
    /// chosen in both builds while `archives()` filters on the name prefix alone:
    /// a Debug rotation would delete the Release build's archives of real
    /// invoices (L8, L369).
    ///
    /// TAKEN AS A PARAMETER rather than read from the build, so BOTH branches are
    /// testable from a bundle that is always Debug. `StoreLocation` factors its
    /// own Debug decision the same way and for the same reason.
    @Test("a development build is given no folder to back up into, even when one is chosen")
    func aDebugBuildNeverBacksUp() throws {
        let folder = URL(fileURLWithPath: "/tmp/somewhere")

        #expect(BackupFolderSetting.folderToBackUpInto(
            isDebugBuild: true, resolution: .chosen(folder)) == nil)
    }

    /// THE CONTROL. Without it the rule above is satisfied by a function that
    /// always answers nothing, which would stop backups entirely (L159).
    @Test("the shipping build is given the folder that was chosen")
    func theShippingBuildGetsTheFolder() throws {
        let folder = URL(fileURLWithPath: "/tmp/somewhere")

        #expect(BackupFolderSetting.folderToBackUpInto(
            isDebugBuild: false, resolution: .chosen(folder)) == folder)
    }

    @Test("a shipping build with nothing chosen is given nothing")
    func nothingChosenGivesNothing() throws {
        #expect(BackupFolderSetting.folderToBackUpInto(
            isDebugBuild: false, resolution: .notChosen) == nil)
    }

    // MARK: the volume it was chosen on

    /// WHEN A SHARE DETACHES, ITS MOUNT POINT OFTEN SURVIVES as an empty local
    /// directory, or is recreated by the first writer. Everything then succeeds
    /// against the boot disk: the archive is written, it verifies, the trigger
    /// and the staleness rule read that local shadow and report health, and the
    /// Synology receives nothing. That is L98 in its purest form and no check
    /// downstream can see it, because every one of them is looking at the wrong
    /// disk.
    ///
    /// So the volume is recorded when the folder is chosen and checked when it
    /// resolves.
    @Test("the volume the folder was chosen on is recorded")
    func theVolumeIsRecorded() throws {
        let world = try World()

        try world.setting.remember(world.folder)

        #expect(world.setting.recordedVolume != nil)
    }

    /// A DIFFERENT VOLUME IS ITS OWN REFUSAL, with its own sentence, because the
    /// remedy is to plug the drive in or mount the share rather than to choose
    /// again (L11).
    @Test("a folder that is now on a different volume is refused by name")
    func aDifferentVolumeIsRefused() throws {
        let world = try World()
        try world.setting.remember(world.folder)
        world.overwriteRecordedVolume(with: "a-volume-that-is-not-this-one")

        let resolution = world.setting.resolve()

        guard case .onADifferentVolume = resolution else {
            Issue.record("expected a volume refusal, got \(resolution)")
            return
        }
    }

    // MARK: the fixture

    private struct World {
        let root: URL
        let folder: URL
        let defaults: UserDefaults
        let setting: BackupFolderSetting
        private let suiteName: String

        init(disposable: Bool = false) throws {
            root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("ovation-folder-\(UUID().uuidString)", isDirectory: true)
            folder = root.appendingPathComponent("Backups", isDirectory: true)
            try FileManager.default.createDirectory(at: folder,
                                                    withIntermediateDirectories: true)
            // A SUITE OF ITS OWN, never `.standard`. The setting takes its
            // defaults as a dependency with no default that resolves to the real
            // one, so a test cannot reach Dan's actual choice even by omission
            // (L196, L2).
            suiteName = "ovation.tests.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                throw FixtureFailure.couldNotMakeDefaults
            }
            self.defaults = defaults
            setting = BackupFolderSetting(defaults: defaults,
                                          isDisposableLaunch: { disposable })
        }

        func overwriteRecordedVolume(with identifier: String) {
            defaults.set(identifier, forKey: BackupFolderSetting.volumeKey)
        }
    }

    enum FixtureFailure: Error {
        case couldNotMakeDefaults
    }
}
