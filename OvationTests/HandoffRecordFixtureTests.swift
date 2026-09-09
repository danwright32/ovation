import Foundation
import Testing

/// ovation#29. The consumer's fixture is the REAL handoff record Downbeat wrote,
/// scrubbed, rather than an object written from reading the producer's source.
///
/// WHY THAT MATTERS. A fixture invented from reading the producer's source is a
/// second definition of the contract, and it drifts in the direction of whatever
/// its author assumed (L48, L52). This one was produced by the installed Downbeat
/// through its own commit path on 2026-09-06, and it already corrected one
/// assumption before any consumer existed: `venue` is ABSENT on an ad hoc venue
/// rather than present and empty, which is the single most likely thing a source
/// reading gets wrong.
///
/// WHAT WAS SCRUBBED, AND WHY IT IS MORE THAN THE ISSUE EXPECTED. ovation#29
/// named one field, `client.hostingSite`, as the only real value. The identity
/// guard disagreed: four more matched Dan's LIVE Downbeat export, because the
/// client, shoot and venue "fabricated" for the throwaway booking became real
/// rows in his data the moment the booking was committed. A guard cannot tell a
/// fabricated row from a customer, and this repository is public, so every
/// readable value is replaced and the SHAPE is what survives. The shape is the
/// whole reason to keep a measured record: which fields exist, which are absent,
/// and which carry both a day string and an instant. None of that is a name.
///
/// The unscrubbed original stays in custody, hashed in `docs/CUSTODY.md`, so the
/// scrub can be re-checked against what was actually produced.
struct HandoffRecordFixtureTests {

    /// Read from the source tree rather than a bundle resource, because the test
    /// target ships no resources and adding a bundle for one 738 byte file is
    /// machinery nothing else needs.
    private static func fixtureData(_ file: StaticString = #filePath) throws -> Data {
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        let url = here.appending(path: "Fixtures/handoff-record-v3-2026-09-06.json")
        return try Data(contentsOf: url)
    }

    private static func fixture() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: try fixtureData())
        return try #require(object as? [String: Any])
    }

    @Test("the fixture is there and parses, so a missing one cannot read as an empty contract")
    func thefixtureIsReadable() throws {
        let record = try Self.fixture()
        #expect(!record.isEmpty)
    }

    @Test("it is version 3, which is what the installed Downbeat writes")
    func theversionIsThree() throws {
        // Measured against the artifact rather than against Downbeat's record of
        // itself, which is the same rule `check-sibling-installs.sh` follows: two
        // systems that must agree cannot be verified against records one of them
        // wrote into the other (L58).
        #expect(try Self.fixture()["version"] as? Int == 3)
    }

    @Test("VENUE IS ABSENT, not present and empty, which is the fact this fixture exists for")
    func venueIsAbsentForAnAdHocVenue() throws {
        // A drain that requires `venue` refuses legitimate records. This record
        // was committed with an ad hoc venue, and the key is simply not there.
        // `booking.venueName` is the whole answer in that case.
        let record = try Self.fixture()
        #expect(record["venue"] == nil)
        let booking = try #require(record["booking"] as? [String: Any])
        let venueName = try #require(booking["venueName"] as? String)
        #expect(!venueName.isEmpty, "and the name still travels, on the booking")
    }

    @Test("a booking carries BOTH day strings and instants, which a source reading would not predict")
    func bothDayStringsAndInstantsAreThere() throws {
        // Four fields where a reader might expect two. The day strings are what a
        // tax year is decided by (ovation#55) and the instants are what the
        // billable hours come from, so dropping either loses something.
        let booking = try #require(try Self.fixture()["booking"] as? [String: Any])
        for key in ["startDate", "endDate"] {
            let value = try #require(booking[key] as? String)
            #expect(value.count == 10, "\(key) is a day string, not an instant")
        }
        for key in ["startsAt", "endsAt"] {
            let value = try #require(booking[key] as? String)
            #expect(value.count > 10, "\(key) is an instant")
            #expect(value.contains("T"))
        }
    }

    @Test("the client carries fields a source reading would not have predicted at all")
    func theclientCarriesMoreThanExpected() throws {
        // Named one by one rather than counted, because a count passes when one
        // field is swapped for another.
        let client = try #require(try Self.fixture()["client"] as? [String: Any])
        for key in ["id", "displayName", "email", "contractEmail", "hostingSite",
                    "hasLeftReview", "specialBehaviors"] {
            #expect(client[key] != nil, Comment(rawValue: "client.\(key) is missing"))
        }
        #expect(client["hasLeftReview"] as? Bool == false)
        #expect((client["specialBehaviors"] as? [Any])?.isEmpty == true,
                "empty, and PRESENT, which is different from absent")
    }

    @Test("both identifiers are UUID shaped, so a consumer can key on them")
    func theidentifiersAreUsable() throws {
        let record = try Self.fixture()
        let booking = try #require(record["booking"] as? [String: Any])
        let client = try #require(record["client"] as? [String: Any])
        for id in [booking["id"], booking["clientId"], client["id"]] {
            let value = try #require(id as? String)
            #expect(UUID(uuidString: value) != nil, "an identifier that is not a UUID")
        }
        #expect(booking["clientId"] as? String == client["id"] as? String,
                "the booking points at the client that travels with it")
    }

    @Test("no readable value in the fixture is left from Dan's own data")
    func thefixtureIsScrubbed() throws {
        // The scrub is asserted HERE as well as by the identity guard, because
        // the guard derives its needles from files outside the repository: on a
        // machine without them it examines nothing and passes (L98, L217). This
        // assertion needs nothing but the fixture.
        let text = String(decoding: try Self.fixtureData(), as: UTF8.self)
        #expect(text.contains("ashgrove.example"), "the scrubbed addresses are reserved-domain")
        #expect(text.contains("a-hosting-site.example"))
        // Every address in it is in a reserved domain, so none can be a real one.
        for line in text.split(separator: "\n") where line.contains("@") {
            #expect(line.contains(".example"),
                    Comment(rawValue: "an address that is not in a reserved domain: \(line)"))
        }
    }
}
