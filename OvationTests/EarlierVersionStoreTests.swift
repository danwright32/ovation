import Foundation
import SwiftData
import Testing

/// ovation#632. What `EarlierVersionStore` promises, each one measured, because the
/// crash it exists to prevent is intermittent and a green run of the migration
/// suite says nothing about whether the window is closed.
struct EarlierVersionStoreTests {

    private static func scratchStore() throws -> URL {
        let directory = URL.temporaryDirectory
            .appending(path: "ovation-earlier-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Ovation.store")
    }

    @Test("an earlier version is written on the main thread, where no main run loop timer can run beside it")
    func theWriteRunsOnTheMainThread() async throws {
        let url = try Self.scratchStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var ranOnMain: Bool?
        try await EarlierVersionStore.write(OvationSchemaV1.self, at: url) { _ in
            ranOnMain = Thread.isMainThread
        }
        #expect(ranOnMain == true)
    }

    @Test("the fixture's own context never autosaves, so it arms no timer of its own")
    func theFixtureContextDoesNotAutosave() async throws {
        let url = try Self.scratchStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var autosaved: Bool?
        try await EarlierVersionStore.write(OvationSchemaV1.self, at: url) { context in
            autosaved = context.autosaveEnabled
        }
        #expect(autosaved == false)
    }

    /// THE CI CRASH, as a sequence rather than a timing. A current version
    /// container opened BEFORE the earlier one, holding an unsaved row, is the
    /// shape another suite's context leaves in the process. Saving through it
    /// while a version 1 container is alive throws `NSUnknownKeyException` for
    /// `noteToClient` and kills the test process, measured on 2026-09-29. So the
    /// save below passes only because the earlier container is gone by then.
    @Test("a container opened before the earlier version still saves once the write returns")
    func anEarlierOpenedContainerStillSaves() async throws {
        let url = try Self.scratchStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
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

    @Test("an earlier version's container that outlives the call is refused by name")
    @MainActor
    func asurvivingContainerIsRefused() throws {
        let url = try Self.scratchStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var kept: ModelContainer?
        #expect(throws: EarlierVersionStore.StillOpen.self) {
            try EarlierVersionStore.open(OvationSchemaV1.self, at: url) { kept = $0 }
        }
        #expect(kept != nil, "the fixture really did keep it, so the refusal is about that")
        kept = nil
    }

    // MARK: every earlier version goes through it

    /// ONE WAY IN (L613). A fixture that builds its own earlier version container
    /// reopens the window this closes, and would pass until the timer next lands
    /// in it. Probe schemas are exempt for a stated reason: their one entity is
    /// called `Probe`, which no context outside their own tests ever holds, and
    /// SwiftData collides versions by entity name.
    @Test("no test opens an earlier Ovation version except through EarlierVersionStore")
    func everyEarlierVersionGoesThroughTheStore() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let marker = "Schema(" + "versionedSchema:"
        var scanned = 0
        var sawTheStoreItself = false
        var handRolled: [String] = []
        for folder in ["OvationTests", "OvationHostedTests"] {
            let directory = root.appending(path: folder, directoryHint: .isDirectory)
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                                                                    includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "swift" {
                scanned += 1
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                for (index, line) in lines.enumerated() where line.contains(marker) {
                    if file.lastPathComponent == "EarlierVersionStore.swift" {
                        sawTheStoreItself = true
                    } else if !line.contains("ProbeSchema") {
                        handRolled.append("\(folder)/\(file.lastPathComponent):\(index + 1)")
                    }
                }
            }
        }
        #expect(scanned > 100, "the scan read the test sources, not an empty folder")
        #expect(sawTheStoreItself, "the marker matches real source, so an empty result means something")
        #expect(handRolled.isEmpty, "open these through EarlierVersionStore: \(handRolled)")
    }
}
