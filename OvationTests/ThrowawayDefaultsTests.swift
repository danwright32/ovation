import Foundation
import Testing

/// ovation#263. A SETTINGS STORE A TEST CAN WRITE TO AND LEAVE NOTHING BEHIND.
///
/// Two fixtures made `UserDefaults(suiteName: "ovation.tests.<uuid>")` so a test
/// could never reach Dan's real settings, which is right (L2). Nothing removed
/// the domain afterwards, so every run left one more plist in
/// ~/Library/Preferences and one more entry in `defaults domains`: 426 on
/// 2026-09-13 when the issue was filed, 4656 by that evening.
///
/// REMOVING THE DOMAIN IS NOT ENOUGH, and that was measured rather than assumed
/// the same day. `removePersistentDomain(forName:)` leaves the plist behind as
/// an empty dictionary that `defaults domains` still lists, the preferences
/// daemon writes that empty file about ten seconds later, and deleting the file
/// sooner loses the race: it was written back three seconds after deletion.
///
/// SO NO DOMAIN IS CREATED AT ALL. A suite named by an ABSOLUTE PATH keeps its
/// plist at that path, never in ~/Library/Preferences, and `defaults domains`
/// never lists it. Measured: a value written reads back from a second instance,
/// and after the domain is removed and its folder deleted, nothing reappeared
/// thirteen seconds later. The folder is this helper's own, so releasing the
/// helper removes everything it made (L114).
final class ThrowawayDefaults {
    let defaults: UserDefaults
    /// The folder the suite lives in, and nothing else does.
    let folder: URL
    /// The suite's name as UserDefaults knows it.
    let suiteName: String

    init() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ovation-defaults-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // AN ABSOLUTE PATH, never a bare name. A bare name is a domain in
        // ~/Library/Preferences, which is the leftover this exists to stop.
        suiteName = folder.appendingPathComponent("ovation.tests.\(UUID().uuidString)").path
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw Failure.couldNotMakeDefaults(suiteName)
        }
        self.defaults = defaults
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: folder)
    }

    enum Failure: Error {
        case couldNotMakeDefaults(String)
    }
}

struct ThrowawayDefaultsTests {

    /// Where a NAMED domain's plist would land, which is the leftover this
    /// helper exists to stop making.
    private static func preferencesFile(named name: String) -> String {
        NSHomeDirectory() + "/Library/Preferences/\(name).plist"
    }

    @Test("a value written reads back, from the same suite opened again")
    func aValueReadsBack() throws {
        let throwaway = try ThrowawayDefaults()

        throwaway.defaults.set("a chosen folder", forKey: "probe")

        #expect(UserDefaults(suiteName: throwaway.suiteName)?.string(forKey: "probe")
                == "a chosen folder")
    }

    /// THE QUANTITY THE ISSUE IS ABOUT, measured on the disk (L63). The write is
    /// flushed first, and a named domain's plist is on disk the moment it is
    /// (measured 2026-09-13), so its absence here is not a flush still pending.
    @Test("writing to it creates no preferences domain on the Mac")
    func itCreatesNoPreferencesDomain() throws {
        let throwaway = try ThrowawayDefaults()

        throwaway.defaults.set("a chosen folder", forKey: "probe")
        throwaway.defaults.synchronize()

        let leaf = URL(fileURLWithPath: throwaway.suiteName).lastPathComponent
        #expect(!FileManager.default.fileExists(atPath: Self.preferencesFile(named: leaf)),
                "a domain was created in ~/Library/Preferences: \(leaf)")
        // THE POSITIVE CONTROL. Without it a write that went nowhere would pass
        // the line above just as well (L159).
        let inFolder = (try? FileManager.default.contentsOfDirectory(atPath: throwaway.folder.path)) ?? []
        #expect(inFolder.contains { $0.hasSuffix(".plist") },
                "the value was not written anywhere this test can see")
    }

    @Test("releasing it removes the folder it made")
    func releasingItRemovesItsFolder() throws {
        var throwaway: ThrowawayDefaults? = try ThrowawayDefaults()
        let folder = try #require(throwaway?.folder)
        throwaway?.defaults.set("a chosen folder", forKey: "probe")
        throwaway?.defaults.synchronize()
        #expect(FileManager.default.fileExists(atPath: folder.path))

        throwaway = nil

        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
