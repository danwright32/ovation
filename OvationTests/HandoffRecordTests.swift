import Foundation
import Testing
@testable import Ovation

/// ovation#33, PRD 6.34 and section 8 item 8. The decoder for one queued booking,
/// and the version floor that decides which records it will read.
///
/// THE FLOOR IS A MINIMUM, NEVER AN EQUALITY. An equality gate turns the
/// producer's next additive bump into a total outage of the consumer, and a
/// payload refused whole produces empty data indistinguishable from the data
/// being gone (L255). That is not hypothetical between these two apps: Phase 0.2
/// exists because installing a version 3 Downbeat in front of an Overture with an
/// equality gate would have made it refuse the export and lose the client roster.
///
/// THE DECLARED MINIMUM AND THE ENFORCED MINIMUM ARE TIED BY BEHAVIOUR HERE.
/// `integration/downbeat-handoff-accepted-versions.json` is what Downbeat's push
/// gate reads; the decoder is what actually refuses a record. A test that read
/// the constant out of the decoder and compared it with the file would prove only
/// that one number was copied to two places (L70). So these tests read the FILE
/// and then drive the DECODER with records built either side of what it says.
///
/// THE FIXTURE IS THE REAL RECORD for everything the real record can show.
/// `handoff-record-v3-2026-09-06.json` came out of the installed Downbeat through
/// its own commit path (ovation#29), so it is evidence rather than a second
/// definition of the contract written from reading the producer (L48, L52). What
/// it cannot show, a venue and a re-run, comes from the published contract
/// document rather than from Downbeat's source, and is marked where it is used.
struct HandoffRecordTests {

    // MARK: what the declaration says, read once and used by everything below

    /// The repository root, from this file rather than from a working directory,
    /// because a test's working directory is the runner's business.
    private static func repositoryRoot(_ file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()   // OvationTests
            .deletingLastPathComponent()   // the repository
    }

    private static var declarationURL: URL {
        repositoryRoot()
            .appending(path: "integration/downbeat-handoff-accepted-versions.json")
    }

    private struct Declaration: Decodable {
        let minimumVersion: Int
        let maximumVersion: Int?
    }

    private static func declaration() throws -> Declaration {
        try JSONDecoder().decode(Declaration.self, from: Data(contentsOf: declarationURL))
    }

    @Test("the declaration Downbeat's gate reads is there and states a minimum")
    func theDeclarationExists() throws {
        // Downbeat's `scripts/test-export-consumer-version.sh` reads exactly this
        // path and these key names, and answers CANNOT MEASURE while the file is
        // absent. A file present and unreadable BLOCKS its push, deliberately, so
        // the shape is part of the contract rather than this repository's own
        // business.
        let declaration = try Self.declaration()
        #expect(declaration.minimumVersion >= 1)
        // No ceiling. A maximum would put the equality gate back one step along:
        // the next additive bump would be refused by a number rather than by a
        // comparison, with the same outage (L255).
        #expect(declaration.maximumVersion == nil)
    }

    @Test("the DECODER refuses the version one below what the declaration states")
    func theDecoderEnforcesTheDeclaredFloor() throws {
        // The behaviour tie. Nothing here reads `HandoffRecord.minimumVersion`:
        // the number comes from the file and the answer comes from the decoder,
        // so a decoder that drifted from the published floor fails this even
        // though both halves are internally consistent (L70).
        let minimum = try Self.declaration().minimumVersion
        let older = try Self.fixtureRecord(version: minimum - 1)

        guard case .refused(let reason) = HandoffRecord.read(older) else {
            Issue.record("a record below the declared minimum was accepted")
            return
        }
        #expect(reason == .versionBelowMinimum(found: minimum - 1, minimum: minimum))
    }

    @Test("and it accepts the version the declaration states")
    func theDeclaredFloorItselfIsAccepted() throws {
        // The positive control for the test above. Without it, a decoder that
        // refused EVERYTHING would pass, which is the shape this gate exists to
        // prevent in the first place (L159).
        let minimum = try Self.declaration().minimumVersion
        let atTheFloor = try Self.fixtureRecord(version: minimum)

        guard case .read(let record) = HandoffRecord.read(atTheFloor) else {
            Issue.record("a record at the declared minimum was refused")
            return
        }
        #expect(record.version == minimum)
    }

    @Test("a version ABOVE the minimum is read, which is the whole reason for a floor")
    func aNewerVersionIsRead() throws {
        // The case an equality gate gets wrong, and it is silent: Downbeat bumps
        // its format, every record is refused, and a queue nothing drains looks
        // exactly like a quiet week (L255, L98).
        let minimum = try Self.declaration().minimumVersion
        let newer = try Self.fixtureRecord(version: minimum + 7)

        guard case .read(let record) = HandoffRecord.read(newer) else {
            Issue.record("a record from a newer version was refused")
            return
        }
        #expect(record.version == minimum + 7)
    }

    @Test("a newer version carrying a field this build has never heard of is still read")
    func anUnknownFieldDoesNotRefuseTheRecord() throws {
        // An additive bump IS a field this build does not know. Refusing on one
        // would make the floor decorative, since every version above the minimum
        // would fail for a different reason than the version check.
        //
        // The field is dropped, and that is the accepted cost of the shape rather
        // than an oversight (L425): what is lost is a value this build has no use
        // for, and the version in the record says a newer Ovation should re-read
        // it. The queue file is not deleted until an invoice is saved (ovation#32),
        // so nothing is destroyed by reading a record with a field in it.
        var object = try Self.fixtureObject()
        object["somethingAddedLater"] = ["nested": true]
        object["version"] = try Self.declaration().minimumVersion + 1

        guard case .read = HandoffRecord.read(try Self.data(from: object)) else {
            Issue.record("a record with an unknown field was refused")
            return
        }
    }

    // MARK: the refusals are distinct, because the remedies are

    @Test("bytes that are not JSON are refused as unreadable, not as a version problem")
    func rubbishIsNotAVersionProblem() throws {
        let refusal = try #require(Self.refusal(from: Data("this is not json".utf8)))
        guard case .notReadable = refusal else {
            Issue.record("unreadable bytes were reported as \(refusal)")
            return
        }
    }

    @Test("an EMPTY file is refused rather than read as a record with nothing in it")
    func anEmptyFileIsRefused() throws {
        // PRD 5.34: a malformed handoff file is refused loudly and named, and is
        // never read as an empty file. An empty record that decoded would draft
        // an invoice for nobody.
        let refusal = try #require(Self.refusal(from: Data()))
        guard case .notReadable = refusal else {
            Issue.record("an empty file was reported as \(refusal)")
            return
        }
    }

    @Test("a record with no version at all says THAT, rather than being compared with the floor")
    func aMissingVersionIsItsOwnRefusal() throws {
        // A missing version is not version zero. Treating it as a number below
        // the floor would report "this record is too old" about a file that never
        // said how old it is, and the two need different work: one is a Downbeat
        // to upgrade and the other is a file that is not a handoff record (L11).
        var object = try Self.fixtureObject()
        object["version"] = nil

        let refusal = try #require(Self.refusal(from: try Self.data(from: object)))
        #expect(refusal == .versionMissing)
    }

    @Test("a field the invoice cannot be priced without is NAMED when it is missing")
    func aMissingFieldIsNamed() throws {
        // `startsAt` and `endsAt` are what the billable hours come from, so a
        // record without them cannot produce an invoice. Named rather than
        // defaulted: a zero length shoot would price at nothing and the invoice
        // would total correctly against its own parts (L67, ShootWhen).
        var object = try Self.fixtureObject()
        var booking = try #require(object["booking"] as? [String: Any])
        booking["startsAt"] = nil
        object["booking"] = booking

        let refusal = try #require(Self.refusal(from: try Self.data(from: object)))
        guard case .fieldMissing(let name) = refusal else {
            Issue.record("a missing startsAt was reported as \(refusal)")
            return
        }
        #expect(name.contains("startsAt"))
    }

    @Test("a field of the wrong TYPE is refused as malformed, not as missing")
    func aWrongTypeIsNotAMissingField() throws {
        var object = try Self.fixtureObject()
        var booking = try #require(object["booking"] as? [String: Any])
        booking["startsAt"] = 17
        object["booking"] = booking

        let refusal = try #require(Self.refusal(from: try Self.data(from: object)))
        guard case .fieldMalformed(let name, _) = refusal else {
            Issue.record("a startsAt of the wrong type was reported as \(refusal)")
            return
        }
        #expect(name.contains("startsAt"))
    }

    @Test("every refusal can say what happened, in a sentence naming the file")
    func everyRefusalHasASentence() throws {
        // A drain raises these through the one problems store, so each has to be
        // a sentence Dan can act on rather than a case name (PRD 5.34).
        let refusals: [HandoffRefusal] = [
            .notReadable(detail: "not valid JSON"),
            .versionMissing,
            .versionBelowMinimum(found: 2, minimum: 3),
            .fieldMissing("booking.startsAt"),
            .fieldMalformed("booking.startsAt", detail: "expected a date")
        ]
        for refusal in refusals {
            let sentence = refusal.sentence(for: "5FEBD76A.json")
            #expect(sentence.contains("5FEBD76A.json"),
                    Comment(rawValue: "\(refusal) does not name the file"))
            #expect(sentence.count > 40, Comment(rawValue: "\(refusal) says too little"))
        }
    }

    @Test("the version refusal names BOTH numbers, because one of them is the remedy")
    func theVersionRefusalNamesBothNumbers() {
        let sentence = HandoffRefusal.versionBelowMinimum(found: 2, minimum: 3)
            .sentence(for: "a-booking.json")
        #expect(sentence.contains("2"))
        #expect(sentence.contains("3"))
    }

    // MARK: the real record, field by field

    @Test("the real record Downbeat wrote decodes, and every field arrives")
    func therealRecordDecodes() throws {
        // Named one by one rather than counted, because a count passes when one
        // field is swapped for another.
        guard case .read(let record) = HandoffRecord.read(try Self.fixtureData()) else {
            Issue.record("the real record did not decode")
            return
        }
        #expect(record.version == 3)
        #expect(record.booking.id == UUID(uuidString: "5FEBD76A-2685-4967-8C39-8D40B7151D34"))
        #expect(record.booking.clientID == record.client.id)
        #expect(record.booking.shootName == "A rehearsal shoot")
        #expect(record.booking.startDate == "2026-09-06")
        #expect(record.booking.endDate == "2026-09-06")
        #expect(record.booking.venueName == "A hall")
        #expect(record.client.displayName == "Ashgrove Chamber Players")
        #expect(record.client.email == "booking@ashgrove.example")
        #expect(record.client.contractEmail == "accounts@ashgrove.example")
        #expect(record.client.hasLeftReview == false)
        #expect(record.client.specialBehaviors.isEmpty)
    }

    @Test("the instants arrive as instants and the days stay days")
    func theinstantsAndDaysAreBothCarried() throws {
        // Four fields where a reader might expect two. The day strings are what a
        // tax year is decided by (ovation#55) and the instants are what the
        // billable hours come from, so dropping either loses something. The days
        // are kept as Downbeat wrote them rather than re-derived from the
        // instants: they are authored in Dan's shooting zone, and re-deriving
        // them here would answer with this Mac's zone instead.
        guard case .read(let record) = HandoffRecord.read(try Self.fixtureData()) else {
            Issue.record("the real record did not decode")
            return
        }
        #expect(record.booking.startsAt == ISO8601DateFormatter().date(from: "2026-09-06T23:00:00Z"))
        #expect(record.booking.endsAt == ISO8601DateFormatter().date(from: "2026-09-07T00:00:00Z"))
        #expect(record.committedAt == ISO8601DateFormatter().date(from: "2026-09-06T17:28:16Z"))
        // The instants cross midnight UTC while both day strings say the 6th,
        // which is the case a consumer that re-derived the day would get wrong.
        #expect(record.booking.startDate == record.booking.endDate)
    }

    @Test("VENUE IS ABSENT on the real record and that is not a refusal")
    func anAbsentVenueIsLegitimate() throws {
        // The fact the measured fixture exists for. A drain that requires `venue`
        // refuses legitimate records, and this is the part of the contract a
        // source reading is most likely to get wrong: it is absent for an ad hoc
        // venue rather than present and empty.
        guard case .read(let record) = HandoffRecord.read(try Self.fixtureData()) else {
            Issue.record("the real record did not decode")
            return
        }
        #expect(record.venue == nil)
        #expect(record.booking.venueID == nil, "and no venueId either, for the same reason")
        #expect(record.booking.venueName == "A hall", "the name still travels, on the booking")
    }

    @Test("a record WITH a venue carries it, from the published contract's own example")
    func avenueIsCarriedWhenItIsThere() throws {
        // NOT measured: no real record with a roster venue has been captured yet.
        // The shape comes from `Integration/OvertureExport/CONTRACT.md`, which is
        // the published contract rather than a reading of Downbeat's source, and
        // it is marked here so that the day a real one is captured, this is the
        // test to re-point at it.
        //
        // THE NAMES ARE NOT THE CONTRACT'S. Its example uses a venue that is real
        // in Dan's data, and `check-identity-leaks.sh` refused this file for it,
        // correctly: this repository is public, and a name copied out of a
        // document is as real as one copied out of a database (L155, L222). The
        // fictional venue is the one the shell fixtures already use, so there is
        // one invented name rather than two.
        var object = try Self.fixtureObject()
        var booking = try #require(object["booking"] as? [String: Any])
        booking["venueId"] = "33333333-3333-3333-3333-333333333333"
        booking["venueName"] = "Nowhere Hall"
        object["booking"] = booking
        object["venue"] = [
            "id": "33333333-3333-3333-3333-333333333333",
            "name": "Nowhere Hall",
            "editingProfile": "performingArts",
            "specialBehaviors": [],
            "staffNotificationEmails": []
        ] as [String: Any]

        guard case .read(let record) = HandoffRecord.read(try Self.data(from: object)) else {
            Issue.record("a record with a venue did not decode")
            return
        }
        let venue = try #require(record.venue)
        #expect(venue.name == "Nowhere Hall")
        #expect(venue.id == UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        #expect(record.booking.venueID == venue.id)
    }

    @Test("isRerunOf is absent on an ordinary booking and carried when it is there")
    func arerunIdentifierIsCarried() throws {
        // Contract item 3, and the field most easily dropped when mapping. A
        // re-run adds a note to the invoice that already exists rather than
        // drafting a second one, so losing it here produces a duplicate invoice
        // for one shoot and nothing reports it.
        guard case .read(let ordinary) = HandoffRecord.read(try Self.fixtureData()) else {
            Issue.record("the real record did not decode")
            return
        }
        #expect(ordinary.booking.isRerunOf == nil)

        var object = try Self.fixtureObject()
        var booking = try #require(object["booking"] as? [String: Any])
        booking["isRerunOf"] = "22222222-2222-2222-2222-222222222222"
        object["booking"] = booking

        guard case .read(let rerun) = HandoffRecord.read(try Self.data(from: object)) else {
            Issue.record("a re-run record did not decode")
            return
        }
        #expect(rerun.booking.isRerunOf == UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
    }

    @Test("an optional client field that is simply omitted is not a refusal")
    func omittedOptionalClientFieldsAreFine() throws {
        // The contract's convention throughout: an optional field is OMITTED
        // entirely rather than written as null, and a reader must treat a missing
        // key as no value. The real record omits all four of these already, which
        // is why it is the fixture rather than an invented one.
        guard case .read(let record) = HandoffRecord.read(try Self.fixtureData()) else {
            Issue.record("the real record did not decode")
            return
        }
        #expect(record.client.shortName == nil)
        #expect(record.client.phoneNumber == nil)
        #expect(record.client.isTaxExempt == nil)
        #expect(record.client.notes == nil)
    }

    @Test("a client field that IS there is carried rather than dropped")
    func presentOptionalClientFieldsAreCarried() throws {
        // The positive control for the test above: four fields that are always
        // nil would satisfy it (L159). `isTaxExempt` matters beyond tidiness,
        // since ovation#122 is about where tax status actually lives.
        var object = try Self.fixtureObject()
        var client = try #require(object["client"] as? [String: Any])
        client["shortName"] = "Ashgrove"
        client["phoneNumber"] = "555-0100"
        client["isTaxExempt"] = true
        client["notes"] = "a note"
        object["client"] = client

        guard case .read(let record) = HandoffRecord.read(try Self.data(from: object)) else {
            Issue.record("a record with the optional client fields did not decode")
            return
        }
        #expect(record.client.shortName == "Ashgrove")
        #expect(record.client.phoneNumber == "555-0100")
        #expect(record.client.isTaxExempt == true)
        #expect(record.client.notes == "a note")
    }

    // MARK: fixtures

    private static func fixtureData(_ file: StaticString = #filePath) throws -> Data {
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        return try Data(contentsOf: here.appending(path: "Fixtures/handoff-record-v3-2026-09-06.json"))
    }

    private static func fixtureObject() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: try fixtureData())
        return try #require(object as? [String: Any])
    }

    /// The real record with its version replaced, so a version test differs from
    /// the measured record in exactly one field.
    private static func fixtureRecord(version: Int) throws -> Data {
        var object = try fixtureObject()
        object["version"] = version
        return try data(from: object)
    }

    private static func data(from object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func refusal(from data: Data) -> HandoffRefusal? {
        guard case .refused(let reason) = HandoffRecord.read(data) else { return nil }
        return reason
    }
}
