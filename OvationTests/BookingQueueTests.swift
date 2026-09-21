import Foundation
import Testing

/// ovation#461. Reading the booking handoff queue, and never writing to it.
///
/// IT IS READ ONLY, AND THAT IS PROVED RATHER THAN ASSERTED. The one instrument
/// that watches the disk, `scripts/check-live-data-untouched.sh`, deliberately
/// does NOT watch `booking-queue`, because Downbeat writes it and a before and
/// after comparison would accuse the suite of a change another application made.
/// So the guard is blind to exactly this directory, and reading the source for
/// the absence of a `removeItem` is the count of call sites that mistakes a
/// shared helper for safety (L201, L212, L375).
///
/// SO THE DIRECTORY IS A PARAMETER, never resolved inside. The live location is
/// supplied at the one call site in the app, and everything here runs against a
/// copy whose file set, bytes and modification times are asserted identical
/// afterwards.
///
/// AN EMPTY ANSWER IS NOT A GOOD ANSWER. Never created, created and empty, and
/// present with unreadable records are three different sentences because they
/// need three different actions, and reporting success on an empty queue is
/// indistinguishable from reporting that everything was handled (L98, L215).
struct BookingQueueTests {

    private static func fixtureData(_ file: StaticString = #filePath) throws -> Data {
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        return try Data(contentsOf: here.appending(path: "Fixtures/handoff-record-v3-2026-09-06.json"))
    }

    /// A throwaway directory, with whatever files the case needs in it.
    private static func directory(holding files: [String: Data]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ovation-queue-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, data) in files {
            try data.write(to: url.appending(path: name))
        }
        return url
    }

    /// Every file in a directory, with its bytes and the instant it was last
    /// written, which is what a read must leave exactly as it found.
    private static func census(of directory: URL) throws -> [String: [String: AnyHashable]] {
        var census: [String: [String: AnyHashable]] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            let url = directory.appending(path: name)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            census[name] = [
                "bytes": try Data(contentsOf: url),
                "modified": attributes[.modificationDate] as? Date ?? .distantPast,
            ]
        }
        return census
    }

    // MARK: what is there

    @Test("one readable record in the directory is read, and the file it came from is named")
    func onerecordIsRead() throws {
        let directory = try Self.directory(holding: [
            "5FEBD76A-2685-4967-8C39-8D40B7151D34.json": try Self.fixtureData(),
        ])

        let reading = BookingQueue.read(directory: directory)

        #expect(reading.records.count == 1)
        #expect(reading.records.first?.record.booking.shootName == "A rehearsal shoot")
        #expect(reading.records.first?.file == "5FEBD76A-2685-4967-8C39-8D40B7151D34.json")
        #expect(reading.unreadable.isEmpty)
    }

    /// THE READ LEAVES THE DIRECTORY EXACTLY AS IT FOUND IT, measured rather than
    /// claimed in a header. This is the assertion the repository's own disk guard
    /// cannot make, because it does not watch this directory at all.
    @Test("reading changes no file, no byte and no modification time")
    func thereadChangesNothing() throws {
        let directory = try Self.directory(holding: [
            "5FEBD76A-2685-4967-8C39-8D40B7151D34.json": try Self.fixtureData(),
            "not-json.json": Data("{".utf8),
            "ignored.txt": Data("nothing".utf8),
        ])
        let before = try Self.census(of: directory)

        _ = BookingQueue.read(directory: directory)

        #expect(try Self.census(of: directory) == before,
                "the read changed the queue, which nothing else in this repository would notice")
    }

    /// ONLY `.json`, because Downbeat writes one `<booking-uuid>.json` per
    /// booking and a folder on Dan's Mac collects `.DS_Store` whether anybody
    /// wants it or not. A stray file counted as unreadable would raise a problem
    /// on every run with nothing wrong.
    @Test("a file that is not a record is passed over rather than reported as damaged")
    func anonRecordFileIsPassedOver() throws {
        let directory = try Self.directory(holding: [
            "5FEBD76A-2685-4967-8C39-8D40B7151D34.json": try Self.fixtureData(),
            ".DS_Store": Data([0x00, 0x01]),
        ])

        let reading = BookingQueue.read(directory: directory)

        #expect(reading.records.count == 1)
        #expect(reading.unreadable.isEmpty)
    }

    // MARK: the three ways there is nothing to draft

    @Test("a directory that has never been created says so, and is not an empty queue")
    func amissingDirectorySaysSo() throws {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "ovation-queue-never-\(UUID().uuidString)", directoryHint: .isDirectory)

        let reading = BookingQueue.read(directory: missing)

        #expect(reading.state == .directoryIsNotThere)
        #expect(reading.records.isEmpty)
    }

    @Test("a directory that is there and empty says THAT, because it means something else")
    func anemptyDirectorySaysSomethingElse() throws {
        let reading = BookingQueue.read(directory: try Self.directory(holding: [:]))

        #expect(reading.state == .nothingQueued)
        #expect(reading.records.isEmpty)
    }

    /// AN UNREADABLE RECORD IS CARRIED, NOT DROPPED, and it does not stop the
    /// readable ones beside it. A record Ovation cannot read is a booking that
    /// may never be invoiced, which is the one outcome that means a shoot went
    /// unbilled (PRD 1).
    @Test("a damaged record is reported by name, and the readable one beside it is still read")
    func adamagedRecordIsReported() throws {
        let directory = try Self.directory(holding: [
            "5FEBD76A-2685-4967-8C39-8D40B7151D34.json": try Self.fixtureData(),
            "damaged.json": Data("{ this is not json".utf8),
        ])

        let reading = BookingQueue.read(directory: directory)

        #expect(reading.records.count == 1)
        #expect(reading.unreadable.count == 1)
        #expect(reading.unreadable.first?.file == "damaged.json")
        #expect(reading.state == .read)
    }

    /// A RECORD BELOW THE FLOOR IS A DIFFERENT SENTENCE FROM A DAMAGED ONE,
    /// because the remedy is an older Downbeat rather than a corrupt file (L11).
    @Test("a record from a Downbeat older than the floor names the version, not a field")
    func abelowFloorRecordNamesTheVersion() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: try Self.fixtureData())
                                    as? [String: Any])
        object["version"] = HandoffRecord.minimumVersion - 1
        let directory = try Self.directory(holding: [
            "old.json": try JSONSerialization.data(withJSONObject: object),
        ])

        let reading = BookingQueue.read(directory: directory)

        #expect(reading.records.isEmpty)
        #expect(reading.unreadable.first?.refusal
                    == .versionBelowMinimum(found: HandoffRecord.minimumVersion - 1,
                                            minimum: HandoffRecord.minimumVersion))
    }
}
