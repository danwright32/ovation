// ovation#225. WHERE THE BACKUPS GO, REMEMBERED ACROSS LAUNCHES.
//
// `BackupService` takes a folder it is HANDED, and nothing decided which one:
// `OvationApp` injected a closure that always threw "no backup folder has been
// chosen yet". This chooses.
//
// ONE CORRECTION TO ovation#87's FRAMING, measured rather than argued. It asks
// for the choice to be kept "as a security scoped bookmark so the grant survives
// a relaunch". Ovation is NOT sandboxed (`project.yml: ENABLE_APP_SANDBOX: NO`).
// Measured 2026-09-11 with a standalone program: such a bookmark does still
// resolve outside the sandbox and `startAccessingSecurityScopedResource()`
// returns true, so the mechanism works. It is not what grants access. Outside
// the sandbox the grant is given by the system to the CODE IDENTITY, which is
// exactly why ovation#9 made the signing identity stable. The bookmark's real
// job is remembering WHERE the folder is when it moves or is renamed, which a
// stored path cannot do. So an ordinary bookmark is what is stored, and the
// entry in `LiveDataFloor` says what actually protects the grant.
//
// IT RESOLVES WITHOUT MOUNTING, and that is the load bearing decision here.
// `URL(resolvingBookmarkData:)` against an unmounted share asks the system to
// mount it, which can block for as long as the network takes. The launch
// sequence runs inside `OvationApp.init()`, before any window exists, so a
// blocked resolve is a launch that hangs with nothing on screen and nothing to
// cancel (L236, L241, L110). Refusing to mount turns that into a fast, named
// refusal, which is a better answer than moving the same blocking call to
// another thread.
//
// EVERY REFUSAL IS NAMED AND NOTHING FALLS BACK. A tool handed a target it
// cannot use must never quietly write somewhere else (L320, L75): the point of
// the folder is that Dan chose where his records are copied to.
import Foundation

struct BackupFolderSetting {

    /// What asking produced. Five outcomes, kept apart because each needs a
    /// different thing from Dan and none may be reported as another (L11).
    enum Resolution: Equatable {
        /// The folder, resolved and reachable.
        case chosen(URL)
        /// Nothing has ever been chosen. The state every installation starts in,
        /// and a standing condition rather than a failure (ovation#229).
        case notChosen
        /// Something was chosen and cannot be reached now, with the reason.
        case unresolvable(String)
        /// It resolved, and the volume it sits on is not the one it was chosen
        /// on. Its own outcome because the remedy is to mount the drive rather
        /// than to choose again.
        case onADifferentVolume(String)
        /// A disposable launch asked. Deliberately NOT `notChosen`: a test run
        /// that read "nothing chosen" would look exactly like Dan's machine
        /// before he has chosen one (L98, L11).
        case refusedUnderADisposableLaunch
    }

    enum Refusal: Error, Equatable {
        case disposableLaunch
        case couldNotMakeABookmark(String)
    }

    static let bookmarkKey = "backups.folder.bookmark"
    static let volumeKey = "backups.folder.volume"

    /// INJECTED WITH NO DEFAULT RESOLVING TO `.standard`. A seam that keeps a
    /// test off live data on the way IN does not cover the way OUT (L201), and
    /// `remember` writes: a rendered settings pane would otherwise overwrite
    /// Dan's real choice from a test.
    private let defaults: UserDefaults
    private let isDisposableLaunch: @Sendable () -> Bool

    init(defaults: UserDefaults, isDisposableLaunch: @escaping @Sendable () -> Bool) {
        self.defaults = defaults
        self.isDisposableLaunch = isDisposableLaunch
    }

    /// States, rather than performs, that resolution never mounts. Read by a test
    /// so the decision is asserted rather than left in a comment (L407).
    var resolvesWithoutMounting: Bool { true }

    var recordedVolume: String? { defaults.string(forKey: Self.volumeKey) }

    /// Remember the folder Dan chose.
    ///
    /// THE VOLUME IS RECORDED WITH IT. When a share detaches, its mount point
    /// often survives as an empty local directory, so every write afterwards
    /// succeeds against the boot disk, verifies clean, and the share receives
    /// nothing while the trigger and the staleness rule read the local shadow and
    /// report health (L98). Nothing downstream can see that, because all of it is
    /// looking at the wrong disk.
    func remember(_ folder: URL) throws {
        guard !isDisposableLaunch() else { throw Refusal.disposableLaunch }
        let standardized = folder.standardizedFileURL
        let bookmark: Data
        do {
            bookmark = try standardized.bookmarkData(options: [],
                                                     includingResourceValuesForKeys: nil,
                                                     relativeTo: nil)
        } catch {
            throw Refusal.couldNotMakeABookmark(error.localizedDescription)
        }
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        defaults.set(Self.volumeIdentifier(of: standardized), forKey: Self.volumeKey)
    }

    func resolve() -> Resolution {
        guard !isDisposableLaunch() else { return .refusedUnderADisposableLaunch }
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else { return .notChosen }

        var stale = false
        let folder: URL
        do {
            folder = try URL(resolvingBookmarkData: bookmark,
                             options: [.withoutMounting],
                             relativeTo: nil,
                             bookmarkDataIsStale: &stale)
        } catch {
            return .unresolvable(error.localizedDescription)
        }

        // THE FOLDER HAS TO BE THERE, not merely nameable. A bookmark can resolve
        // to a path whose directory has since been removed, and `chosen` promises
        // a folder something can write into.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .unresolvable("\(folder.path) is not there any more")
        }

        if let recorded = recordedVolume, recorded != Self.volumeIdentifier(of: folder) {
            return .onADifferentVolume(
                "\(folder.path) is on a different volume from the one it was chosen on")
        }

        // A STALE BOOKMARK IS REWRITTEN, not merely used. The folder moved or was
        // renamed, which is exactly what a bookmark exists to survive, and leaving
        // the old data means resolving through the same indirection every launch
        // until it eventually fails.
        if stale { try? remember(folder) }

        return .chosen(folder.standardizedFileURL)
    }

    /// The folder to back up into, or nil when this build must not.
    ///
    /// A PURE FUNCTION TAKING THE BUILD FLAG, so both branches are testable from
    /// the always-Debug test bundle. `StoreLocation` already factors its own
    /// Debug and Release decision this way for exactly that reason, and the
    /// alternative is a rule living only in `OvationApp`, which is the one file
    /// no test here can compile (ovation#88).
    ///
    /// THE DEBUG BUILD NEVER BACKS UP (Dan, 2026-09-11). Its store is throwaway,
    /// so backing it up protects nothing, and nothing stops the same folder being
    /// chosen in both builds while `archives()` filters on the name prefix alone:
    /// a Debug rotation would enumerate and DELETE the Release build's archives of
    /// real invoices (L8, L369). Refusing outright removes that hazard rather than
    /// managing it.
    static func folderToBackUpInto(isDebugBuild: Bool, resolution: Resolution) -> URL? {
        guard !isDebugBuild else { return nil }
        if case .chosen(let folder) = resolution { return folder }
        return nil
    }

    /// THE LIVE ONE, and the only place `.standard` is named (plan 1.9,
    /// ovation#58). `LiveDataFloor` reads this, `scripts/check-isolation-floor.sh`
    /// requires every `live...` resolver to be declared there, and the name has
    /// to begin with `live` for that scan to see it at all.
    ///
    /// It refuses under a disposable launch, so a test can never reach the folder
    /// Dan chose. The refusal is nil rather than a throw because the floor asks
    /// for a location, and "there is not one for you" is the whole answer.
    static var liveBackupsDirectory: URL? {
        guard !AppEnvironment.isDisposableLaunch() else { return nil }
        let setting = BackupFolderSetting(
            defaults: .standard,
            isDisposableLaunch: { AppEnvironment.isDisposableLaunch() })
        return folderToBackUpInto(isDebugBuild: StoreLocation.isDebugBuild,
                                  resolution: setting.resolve())
    }

    /// What identifies the volume a folder sits on, or nil when the system does
    /// not offer one.
    ///
    /// NIL IS A REAL ANSWER and it is not treated as a mismatch: some volumes
    /// carry no UUID, and refusing those would refuse a folder Dan legitimately
    /// chose (L11). The check applies where an identity exists on both sides.
    private static func volumeIdentifier(of url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    }
}
