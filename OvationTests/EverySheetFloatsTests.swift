import Foundation
import Testing

/// ovation#547, PRD 48a. Every sheet floats, centred, every corner rounded, and never
/// hangs from the title bar (Dan, 2026-09-25). A macOS system sheet always hangs, so
/// the app presents none: every sheet is drawn by `FloatingSheet`.
///
/// THE COMPONENT AND THE GUARD SHIP TOGETHER (L613). The payment sheet floated while
/// the review sheet and two panels beside it went on hanging, because nothing said a
/// fourth sheet written the easy way was wrong. This refuses the next `.sheet(` in the
/// app's code, and names the file and line.
///
/// NO EXEMPTIONS: none was found legitimate when it was written. One added later
/// carries its reason, never only a file name (L362).
struct EverySheetFloatsTests {

    private static func repositoryRoot(_ file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // OvationTests
            .deletingLastPathComponent()   // the repository
    }

    /// A system sheet presented in code: `.sheet(` with or without space, on a line
    /// that is not a comment.
    static func systemSheets(in text: String) -> [Int] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .filter { _, line in
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { return false }
                let before = code.components(separatedBy: "//").first ?? code
                return before.range(of: #"\.sheet\s*\("#, options: .regularExpression) != nil
            }
            .map { $0.offset + 1 }
    }

    /// Every Swift file the app is built from, with its text.
    private static func appSources() throws -> [(name: String, text: String)] {
        let root = repositoryRoot().appending(path: "Ovation")
        var found: [(String, String)] = []
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let name = String(url.path.dropFirst(root.path.count + 1))
            found.append((name, try String(contentsOf: url, encoding: .utf8)))
        }
        return found
    }

    @Test("the scan reads the app's sources, so an empty answer cannot pass")
    func theScanReadsTheSources() throws {
        // The control (L98): a scan that read nothing would pass the test below.
        let sources = try Self.appSources()
        #expect(sources.count > 50)
        #expect(sources.contains { $0.name == "Roster/FloatingSheet.swift" })
    }

    @Test("the scan finds a system sheet written either way, and not one in a comment")
    func theScanFindsASheet() {
        // Seen to fail (L1): each spelling the guard exists to refuse, and the
        // comment it must not.
        #expect(Self.systemSheets(in: "a\n  .sheet(isPresented: $open) { panel }") == [2])
        #expect(Self.systemSheets(in: ".sheet (item: $x) { _ in }") == [1])
        #expect(Self.systemSheets(in: "    // a .sheet(isPresented:) hangs") == [])
        #expect(Self.systemSheets(in: "view // not a .sheet( call") == [])
        #expect(Self.systemSheets(in: "FloatingSheet(below: 0) { card }") == [])
    }

    @Test("no sheet in the app is a system sheet hanging from the title bar")
    func noSystemSheets() throws {
        var hanging: [String] = []
        for source in try Self.appSources() {
            hanging += Self.systemSheets(in: source.text).map { "\(source.name):\($0)" }
        }
        #expect(hanging.isEmpty,
                "a system sheet hangs from the title bar (PRD 48a); draw it with FloatingSheet: \(hanging)")
    }
}
