import Foundation
import SwiftData
import Testing

/// ovation#632. What `EarlierVersionStore` promises, each one measured, because the
/// crash it exists to prevent is intermittent and a green run of the migration
/// suite says nothing about whether the window is closed.
struct EarlierVersionStoreTests {

    @Test("an earlier version is written on the main thread, where no main run loop timer can run beside it")
    func theWriteRunsOnTheMainThread() async throws {
        try await ScratchStore.with("earlier") { url in
            var ranOnMain: Bool?
            try await EarlierVersionStore.write(OvationSchemaV1.self, at: url) { _ in
                ranOnMain = Thread.isMainThread
            }
            #expect(ranOnMain == true)
        }
    }

    @Test("the fixture's own context never autosaves, so it arms no timer of its own")
    func theFixtureContextDoesNotAutosave() async throws {
        try await ScratchStore.with("earlier") { url in
            var autosaved: Bool?
            try await EarlierVersionStore.write(OvationSchemaV1.self, at: url) { context in
                autosaved = context.autosaveEnabled
            }
            #expect(autosaved == false)
        }
    }

    /// THE CI CRASH, as a sequence rather than a timing. A current version
    /// container opened BEFORE the earlier one, holding an unsaved row, is the
    /// shape another suite's context leaves in the process. Saving through it
    /// while a version 1 container is alive throws `NSUnknownKeyException` for
    /// `noteToClient` and kills the test process, measured on 2026-09-29. So the
    /// save below passes only because the earlier container is gone by then.
    @Test("a container opened before the earlier version still saves once the write returns")
    func anEarlierOpenedContainerStillSaves() async throws {
        try await ScratchStore.with("earlier") { url in
            let current = try OvationSchema.container(inMemory: true)
            let context = ModelContext(current)
            // AN INVOICE, NOT ONLY A CLIENT. Version 1's client has no key the current
            // one lacks, so the collision encodes it silently; its invoice carries
            // `noteToClient`, which later versions dropped, and that is what throws.
            let client = Client(name: "Ashgrove Chamber Players", taxStatus: .notExempt)
            context.insert(client)
            context.insert(Invoice(client: client, kind: .photography, invoiceDate: nil,
                                   hourlyRate: Money(dollars: 250), taxRate: .newYorkCity,
                                   createdOn: nil))

            try await EarlierVersionStore.write(OvationSchemaV1.self, at: url) { earlier in
                let invoice = OvationSchemaV1.Invoice()
                invoice.noteToClient = "a note version 2 does not have"
                earlier.insert(invoice)
            }

            try context.save()
            #expect(try ModelContext(current).fetchCount(FetchDescriptor<Invoice>()) == 1)
        }
    }

    @Test("an earlier version's container that outlives the call is refused by name")
    @MainActor
    func asurvivingContainerIsRefused() throws {
        try ScratchStore.with("earlier") { url in
            var kept: ModelContainer?
            // THE REFUSAL NAMES WHICH OF THE TWO WAS HELD (L11): a container
            // still alive and store files still open are different faults, and
            // a message covering both leaves the reader to guess.
            do {
                try EarlierVersionStore.open(OvationSchemaV1.self, at: url,
                                              release: ReleaseWait(deadline: .milliseconds(200))) { kept = $0 }
                Issue.record("a kept container was not refused")
            } catch let refused as EarlierVersionStore.StillOpen {
                #expect(refused.containerAlive)
                #expect(String(describing: refused).contains("container was still alive"))
            }
            #expect(kept != nil, "the fixture really did keep it, so the refusal is about that")
            kept = nil
        }
    }

    /// BOTH CAN BE HELD AT ONCE, and then the refusal names both, with the files
    /// it saw: naming only the container would claim one fault where two were
    /// measured (L11, L440).
    @Test("a refusal holding the container and open files names both")
    func aRefusalNamesBothWhenBothAreHeld() {
        let refused = EarlierVersionStore.StillOpen(
            version: Schema.Version(1, 0, 0), waited: .milliseconds(200),
            containerAlive: true, openFiles: ["/tmp/x/store-wal"])
        let said = String(describing: refused)
        #expect(said.contains("container was still alive"))
        #expect(said.contains("store still had 1 file(s) open (/tmp/x/store-wal)"))
    }

    // MARK: every earlier version goes through it

    /// ONE WAY IN (L613). A fixture that builds an earlier version's schema, or a
    /// container over its models, any other way reopens the window this closes and
    /// passes until the timer next lands in it.
    ///
    /// IT READS CALLS, NOT LINES. The first version matched the text
    /// `Schema(versionedSchema:` on one line, so a call split across lines, a
    /// `Schema` built from an earlier version's `models`, and a container built
    /// straight over its classes all went unseen (review of ovation#648). Each of
    /// those is a fixture below that the scan must find.
    ///
    /// WHAT IT REFUSES, outside `EarlierVersionStore.swift`:
    /// - a `Schema(versionedSchema:)` of anything but a probe schema, written as
    ///   `ProbeSchemaVn.self` and nothing else. Probe schemas are exempt because
    ///   their one entity is `Probe`, which no context outside their own tests
    ///   holds, and SwiftData collides versions by entity name.
    /// - a `Schema(...)` or `ModelContainer(...)` whose arguments name an earlier
    ///   version, `OvationSchemaVn` below the one in force.
    @Test("no test opens an earlier Ovation version except through EarlierVersionStore")
    func everyEarlierVersionGoesThroughTheStore() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var scanned = 0
        var sawTheStoreItself = false
        var handRolled: [String] = []
        for folder in ["OvationTests", "OvationHostedTests"] {
            let directory = root.appending(path: folder, directoryHint: .isDirectory)
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                                                                    includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "swift" {
                scanned += 1
                let source = try String(contentsOf: file, encoding: .utf8)
                let found = Self.earlierVersionCalls(in: source)
                if file.lastPathComponent == "EarlierVersionStore.swift" {
                    sawTheStoreItself = !found.isEmpty
                } else {
                    handRolled += found.map { "\(folder)/\(file.lastPathComponent):\($0)" }
                }
            }
        }
        #expect(scanned > 100, "the scan read the test sources, not an empty folder")
        #expect(sawTheStoreItself, "the scan finds the one call it allows, so an empty result means something")
        #expect(handRolled.isEmpty, "open these through EarlierVersionStore: \(handRolled)")
    }

    /// Every spelling the scan must catch, and the ones it must leave alone.
    /// Written with `«` for an opening parenthesis so this file's own source holds
    /// none of them for the scan above to find.
    @Test("the scan catches every way an earlier version can be built, and nothing else",
          arguments: [
            ("one line", "let s = Schema«versionedSchema: OvationSchemaV1.self)", 1),
            ("split across lines", "let s = Schema«\n    versionedSchema:\n        OvationSchemaV3.self\n)", 1),
            ("an earlier version's models", "let s = Schema«OvationSchemaV1.models)", 1),
            ("an earlier version's classes", "let s = Schema«[OvationSchemaV2.Invoice.self,\n OvationSchemaV2.Client.self])", 1),
            ("a container over its classes", "_ = try ModelContainer«\n    for: OvationSchemaV4.Invoice.self,\n    configurations: c)", 1),
            ("a version held in a variable", "_ = try ModelContainer«for: Schema«versionedSchema: version),\n configurations: c)", 1),
            ("the current version by the back door", "let s = Schema«versionedSchema: OvationSchemaV8.self)", 1),
            ("a probe dressed up", "let s = Schema«versionedSchema: flag ? ProbeSchemaV1.self : OvationSchemaV1.self)", 1),
            ("a probe schema", "let s = Schema«versionedSchema: ProbeSchemaV1.self)", 0),
            ("the current models", "let s = Schema«[Client.self])\n_ = try ModelContainer«for: s, configurations: c)", 0),
            ("reading an earlier version's list", "#expect«OvationSchemaV6.models.contains { $0 == SentMessage.self })", 0),
            ("a comment about one", "// Schema«OvationSchemaV1.models) is what the old code did", 0),
            ("another type that ends in Schema", "let s = MySchema«OvationSchemaV1.models)", 0),
          ])
    func theScanReadsCalls(label: String, source: String, expected: Int) {
        let found = Self.earlierVersionCalls(in: source.replacingOccurrences(of: "«", with: "("))
        #expect(found.count == expected, "\(label): \(found)")
    }

    /// The major version in force, read from the app rather than written here, so
    /// "earlier" moves when a version is added.
    private static var currentMajor: Int { OvationSchema.versionedSchema.versionIdentifier.major }

    /// Every `Schema(...)` or `ModelContainer(...)` call in `source` that builds an
    /// earlier version, as "line: call".
    static func earlierVersionCalls(in source: String) -> [String] {
        // Whole line comments go first, since a comment may quote such a call.
        let code = source.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : $0 }
        let text = Array(code.joined(separator: "\n"))
        var found: [String] = []
        var index = 0
        while index < text.count {
            guard let (name, open) = Self.call(in: text, at: index) else { index += 1; continue }
            var depth = 0
            var close = open
            while close < text.count {
                if text[close] == "(" { depth += 1 }
                if text[close] == ")" { depth -= 1; if depth == 0 { break } }
                close += 1
            }
            let arguments = String(text[(open + 1)..<min(close, text.count)])
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if Self.buildsAnEarlierVersion(name: name, arguments: arguments) {
                let line = text[..<index].filter { $0 == "\n" }.count + 1
                found.append("\(line): \(name)(\(arguments))")
            }
            index = open + 1
        }
        return found
    }

    /// `Schema(` or `ModelContainer(` starting at `index`, not as the tail of a
    /// longer name or a member, with the position of its parenthesis.
    private static func call(in text: [Character], at index: Int) -> (String, Int)? {
        if index > 0, text[index - 1].isLetter || text[index - 1].isNumber
            || text[index - 1] == "_" || text[index - 1] == "." { return nil }
        for name in ["Schema", "ModelContainer"] {
            let end = index + name.count
            if end < text.count, String(text[index..<end]) == name, text[end] == "(" {
                return (name, end)
            }
        }
        return nil
    }

    private static func buildsAnEarlierVersion(name: String, arguments: String) -> Bool {
        if name == "Schema", arguments.hasPrefix("versionedSchema:"),
           arguments.wholeMatch(of: /versionedSchema: ProbeSchemaV\d+\.self/) == nil {
            return true
        }
        return arguments.matches(of: /OvationSchemaV(\d+)\b/).contains {
            (Int($0.output.1) ?? Int.max) < currentMajor
        }
    }
}
