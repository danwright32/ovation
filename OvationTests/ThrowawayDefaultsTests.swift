import Foundation
import Testing

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
