import Foundation
import Testing

/// ovation#208. The decoder for Downbeat's whole export, which is where Ovation's
/// client roster comes from.
///
/// THE FIXTURES ARE SYNTHETIC AND THAT IS DELIBERATE. The real export carries
/// every one of Dan's clients by name and this repository is public
/// (`docs/PRIVACY-FLOOR.md`), so a suite that read it would put real names in the
/// tree and would change every time he takes a booking (L2, L48). What the real
/// file is allowed to settle is the SHAPE, and the shape was measured from both
/// custody snapshots before any of this was written: 31 clients in each, ids that
/// all parse as UUIDs, `isTaxExempt` present on 6 and absent on 25, and an
/// identical client shape in version 2 and version 3.
///
/// THE FLOOR IS 2 BECAUSE 2 WAS MEASURED, not because a lower number is safer. A
/// floor is a minimum rather than an equality, so the producer's next additive
/// bump does not take the consumer out entirely (L255), and it may only claim
/// versions somebody has actually looked at (L52). Both custody snapshots were
/// read: `downbeat-export-2026-08-27.json` is version 2 and
/// `downbeat-export-v3-2026-09-05.json` is version 3, and their `clients[]`
/// entries carry the same five fields with the same meanings.
struct DownbeatExportTests {

    // MARK: fixtures

    /// One export, built from parts, so every case says only what it is about.
    private static func export(version: Int = 3,
                               exportedAt: String = "2026-08-29T15:07:27Z",
                               clients: String = "[]") -> Data {
        Data("""
        { "version": \(version), "exportedAt": "\(exportedAt)",
          "blockedDates": ["2026-12-25"],
          "venues": [{"id": "8B5F0C2E-0000-4000-8000-000000000001", "name": "A hall"}],
          "bookings": [],
          "clients": \(clients) }
        """.utf8)
    }

    private static let oneClient = """
    [{"id": "8B5F0C2E-0000-4000-8000-0000000000AA",
      "displayName": "A choir",
      "email": "bookings@example.com",
      "contractEmail": "bookings@example.com",
      "hasLeftReview": false,
      "hostingSite": "pixieset",
      "specialBehaviors": []}]
    """

    private static func read(_ data: Data) -> DownbeatExport {
        guard case .read(let export) = DownbeatExport.read(data) else {
            Issue.record("expected the export to read")
            return DownbeatExport(version: 0, exportedAt: .distantPast, clients: [])
        }
        return export
    }

    private static func refusal(_ data: Data) -> DownbeatReadRefusal? {
        guard case .refused(let refusal) = DownbeatExport.read(data) else { return nil }
        return refusal
    }

    // MARK: what it reads

    @Test("an export at the current version reads, and carries its clients")
    func currentVersionReads() {
        let export = Self.read(Self.export(clients: Self.oneClient))
        #expect(export.version == 3)
        #expect(export.clients.count == 1)
        #expect(export.clients[0].displayName == "A choir")
        #expect(export.clients[0].email == "bookings@example.com")
    }

    /// THE FLOOR IS A MINIMUM. Version 2 is the older custody snapshot and its
    /// client shape was measured to be identical, so refusing it would refuse a
    /// file this decoder can demonstrably read.
    @Test("an export at the floor version reads too")
    func floorVersionReads() {
        let export = Self.read(Self.export(version: DownbeatExport.minimumVersion,
                                           clients: Self.oneClient))
        #expect(export.clients.count == 1)
    }

    /// AND A NEWER ONE READS, which is the whole point of a floor. An equality
    /// gate turns Downbeat's next additive bump into a total outage of the
    /// roster, and empty data is indistinguishable from the data being gone
    /// (L255).
    @Test("an export from a NEWER Downbeat reads rather than being refused")
    func newerVersionReads() {
        let export = Self.read(Self.export(version: DownbeatExport.minimumVersion + 9,
                                           clients: Self.oneClient))
        #expect(export.clients.count == 1)
    }

    /// THREE STATES, AND ABSENT IS ONE OF THEM. Folding a missing key into false
    /// would report a client as confirmed taxable on the strength of nothing,
    /// which is the distinction PRD 5 rests on and the reason the roster pass
    /// exists at all.
    @Test("a client with no isTaxExempt is absent rather than not exempt")
    func absentTaxStatusIsNotFalse() {
        let export = Self.read(Self.export(clients: Self.oneClient))
        #expect(export.clients[0].isTaxExempt == nil)
    }

    @Test("a client that IS marked carries the value either way")
    func recordedTaxStatusIsCarried() {
        let exempt = Self.oneClient.replacingOccurrences(
            of: "\"hasLeftReview\": false", with: "\"isTaxExempt\": true, \"hasLeftReview\": false")
        #expect(Self.read(Self.export(clients: exempt)).clients[0].isTaxExempt == true)

        let taxed = Self.oneClient.replacingOccurrences(
            of: "\"hasLeftReview\": false", with: "\"isTaxExempt\": false, \"hasLeftReview\": false")
        #expect(Self.read(Self.export(clients: taxed)).clients[0].isTaxExempt == false)
    }

    /// AN EXPORT WITH NO CLIENTS IS READ, NOT REFUSED, and that is deliberate
    /// rather than an oversight. It is a legitimate state for a fresh Downbeat,
    /// and what to DO about an empty roster is the importer's decision, made
    /// where the store is known. Refusing here would report a readable file as
    /// damaged.
    @Test("an export carrying no clients is read rather than refused")
    func emptyRosterIsRead() {
        let export = Self.read(Self.export(clients: "[]"))
        #expect(export.clients.isEmpty)
    }

    // MARK: what it refuses, each cause on its own

    @Test("bytes that are not JSON are refused as unreadable")
    func notJSONIsRefused() {
        #expect(Self.refusal(Data("not json at all".utf8)) != nil)
        if case .notReadable = Self.refusal(Data("not json at all".utf8)) {} else {
            Issue.record("expected notReadable")
        }
    }

    @Test("an empty file is unreadable rather than an empty roster")
    func emptyFileIsRefused() {
        guard case .notReadable = Self.refusal(Data()) else {
            Issue.record("an empty file must not read as an export with no clients")
            return
        }
    }

    /// NOT FOLDED INTO "TOO OLD" AS VERSION ZERO. A file that never said how old
    /// it is needs different work from one that said it and is too old (L11).
    @Test("an export that does not say its version is its own refusal")
    func missingVersionIsItsOwnRefusal() {
        let data = Data("""
        { "exportedAt": "2026-08-29T15:07:27Z", "clients": [] }
        """.utf8)
        #expect(Self.refusal(data) == .versionMissing)
    }

    @Test("an export below the floor is refused, naming BOTH numbers")
    func belowTheFloorIsRefused() {
        let found = DownbeatExport.minimumVersion - 1
        #expect(Self.refusal(Self.export(version: found))
                == .versionBelowMinimum(found: found, minimum: DownbeatExport.minimumVersion))
    }

    @Test("a client missing a field Ovation needs is refused by NAME")
    func missingFieldIsNamed() {
        let noName = """
        [{"id": "8B5F0C2E-0000-4000-8000-0000000000AA",
          "email": "bookings@example.com",
          "contractEmail": ""}]
        """
        guard case .fieldMissing(let field) = Self.refusal(Self.export(clients: noName)) else {
            Issue.record("expected a named missing field")
            return
        }
        #expect(field.contains("displayName"))
    }

    @Test("a client id that is not an identifier is a malformed field, not a missing one")
    func malformedIdIsNamed() {
        let badID = """
        [{"id": "not-an-id", "displayName": "A choir",
          "email": "a@example.com", "contractEmail": ""}]
        """
        guard case .fieldMalformed(let field, _) = Self.refusal(Self.export(clients: badID)) else {
            Issue.record("expected a named malformed field")
            return
        }
        #expect(field.contains("id"))
    }

    // MARK: what Dan is told

    /// THE SENTENCE BELONGS TO THIS READER and says what a failure here actually
    /// costs, which is a roster that was not refreshed. It is not the handoff
    /// record's sentence, which is about a shoot going uninvoiced and a file left
    /// in a queue, and the two must never be one sentence (ovation#208, L11).
    @Test("every refusal says what happened, names the file, and says what it cost")
    func everyRefusalHasItsOwnSentence() {
        let refusals: [DownbeatReadRefusal] = [
            .notReadable(detail: "it is not JSON"),
            .versionMissing,
            .versionBelowMinimum(found: 1, minimum: 2),
            .fieldMissing("clients.displayName"),
            .fieldMalformed("clients.id", detail: "expected a UUID")
        ]
        for refusal in refusals {
            let sentence = DownbeatExport.sentence(for: refusal, file: "downbeat-export.json")
            #expect(sentence.contains("downbeat-export.json"),
                    Comment(rawValue: "\(refusal) does not name the file"))
            #expect(sentence.count > 40, Comment(rawValue: "\(refusal) says too little"))
            #expect(!sentence.contains("queue"),
                    Comment(rawValue: "\(refusal) is using the handoff record's consequence"))
        }
    }

    @Test("the version refusal names BOTH numbers, because one of them is the remedy")
    func theVersionRefusalNamesBothNumbers() {
        let sentence = DownbeatExport.sentence(for: .versionBelowMinimum(found: 1, minimum: 2),
                                               file: "downbeat-export.json")
        #expect(sentence.contains("1"))
        #expect(sentence.contains("2"))
    }
}
