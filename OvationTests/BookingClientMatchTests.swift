import Foundation
import SwiftData
import Testing
@testable import Ovation

/// ovation#34. Which of Ovation's clients a queued booking names, and a refusal
/// rather than a guess when that cannot be answered.
struct BookingClientMatchTests {

    private static func client(
        _ name: String, email: String = "", contract: String? = nil, downbeat: UUID? = nil
    ) -> Client {
        let client = Client(name: name, taxStatus: .notExempt)
        client.email = email
        client.contractEmail = contract
        client.downbeatClientID = downbeat
        return client
    }

    // MARK: the stable identifier first

    @Test("Downbeat's own identifier matches, and links without asking")
    func theidentifierLinksAutomatically() {
        let id = UUID()
        let wanted = Self.client("Ashgrove Chamber Players", downbeat: id)
        let other = Self.client("Harbour Line Theatre", downbeat: UUID())

        let match = BookingClientMatcher.match(
            downbeatClientID: id, displayName: "a different name now",
            emails: ["nobody@ashgrove.example"], against: [other, wanted])

        #expect(match == .matched(clientID: wanted.id, on: .downbeatIdentifier))
        #expect(match.linksWithoutAsking)
    }

    @Test("the identifier wins over a name that has since changed, which is why it is first")
    func theidentifierBeatsAStaleName() {
        // A queued record freezes its values at commit time, so a client renamed
        // since then will not match by name. The id is the thing that survives.
        let id = UUID()
        let renamed = Self.client("Ashgrove Chamber Players", downbeat: id)
        let namesake = Self.client("The old name")

        let match = BookingClientMatcher.match(
            downbeatClientID: id, displayName: "The old name", emails: [],
            against: [renamed, namesake])

        #expect(match == .matched(clientID: renamed.id, on: .downbeatIdentifier))
    }

    // MARK: then an address

    @Test("an unknown identifier matching exactly one address links automatically")
    func oneAddressLinksAutomatically() {
        let wanted = Self.client("Ashgrove", email: "booking@ashgrove.example")
        let other = Self.client("Harbour Line", email: "hello@harbour.example")

        let match = BookingClientMatcher.match(
            downbeatClientID: UUID(), displayName: "Not this name",
            emails: ["booking@ashgrove.example"], against: [wanted, other])

        #expect(match == .matched(clientID: wanted.id, on: .emailAddress))
        #expect(match.linksWithoutAsking)
    }

    @Test("either address the record carries can be the one Ovation knows")
    func eitherAddressMatches() {
        // Downbeat sends a main AND a contract address, and Ovation may hold
        // either. Matching only the main one would miss the client whose invoice
        // address is the one Ovation recorded.
        let wanted = Self.client("Ashgrove", email: "", contract: "accounts@ashgrove.example")

        let match = BookingClientMatcher.match(
            downbeatClientID: nil, displayName: nil,
            emails: ["booking@ashgrove.example", "accounts@ashgrove.example"], against: [wanted])

        #expect(match == .matched(clientID: wanted.id, on: .emailAddress))
    }

    @Test("an EMPTY address is not a match candidate at all")
    func anemptyAddressMatchesNobody() {
        // Matching on an empty string would link every client with no recorded
        // address to each other, which measured against the real roster is 25 of
        // 31 (ovation#40). Dropped BEFORE the comparison, so nothing rests on an
        // empty string never happening to be equal.
        let first = Self.client("Ashgrove", email: "", contract: "")
        let second = Self.client("Harbour Line", email: "", contract: nil)

        let match = BookingClientMatcher.match(
            downbeatClientID: nil, displayName: nil, emails: ["", "  "],
            against: [first, second])

        #expect(match == .noMatch, "and NOT ambiguous, because nothing was compared")
    }

    @Test("case and whitespace are normalised, on both sides, through one place")
    func normalisationIsShared() {
        // Two spellings that normalise alike must not survive as two candidates
        // and then collide on one stored key (L185).
        let wanted = Self.client("Ashgrove", email: "  Booking@Ashgrove.Example ")

        let match = BookingClientMatcher.match(
            downbeatClientID: nil, displayName: nil,
            emails: ["booking@ashgrove.example"], against: [wanted])

        #expect(match == .matched(clientID: wanted.id, on: .emailAddress))
    }

    // MARK: then the name, which never links on its own

    @Test("a name only match is found, and does NOT link without asking")
    func anameOnlyMatchAsks() {
        // Two clients can legitimately share a name, and a rename can make the
        // record's name belong to somebody else. Enough to propose, never enough
        // to link silently.
        let wanted = Self.client("Ashgrove Chamber Players")

        let match = BookingClientMatcher.match(
            downbeatClientID: nil, displayName: "Ashgrove Chamber Players",
            emails: [], against: [wanted])

        #expect(match == .matched(clientID: wanted.id, on: .nameOnly))
        #expect(!match.linksWithoutAsking, "a namesake would otherwise be billed for this shoot")
    }

    // MARK: what it refuses

    @Test("two clients sharing an address is AMBIGUOUS, never no match and never the first")
    func twoOnOneAddressIsAmbiguous() {
        // The create-new path manufactures a duplicate identity that every later
        // invoice, payment and referral credit feeds, so the cost of guessing
        // here compounds silently and invisibly.
        let first = Self.client("Ashgrove", email: "treasurer@shared.example")
        let second = Self.client("Harbour Line", email: "treasurer@shared.example")

        let match = BookingClientMatcher.match(
            downbeatClientID: nil, displayName: nil,
            emails: ["treasurer@shared.example"], against: [first, second])

        guard case .ambiguous(let ids, let basis) = match else {
            Issue.record("two clients on one address gave \(match)")
            return
        }
        #expect(Set(ids) == [first.id, second.id], "and it NAMES them, so Dan can settle it")
        #expect(basis == .emailAddress)
        #expect(!match.linksWithoutAsking)
    }

    @Test("an ambiguity does NOT fall through to a weaker basis that happens to be decisive")
    func anambiguityStopsThere() {
        // Falling through would resolve "two clients share this address" by
        // picking whichever of them has the matching name, which is a guess
        // wearing the appearance of a rule.
        let first = Self.client("Ashgrove Chamber Players", email: "treasurer@shared.example")
        let second = Self.client("Harbour Line Theatre", email: "treasurer@shared.example")

        let match = BookingClientMatcher.match(
            downbeatClientID: nil, displayName: "Ashgrove Chamber Players",
            emails: ["treasurer@shared.example"], against: [first, second])

        guard case .ambiguous(_, let basis) = match else {
            Issue.record("it fell through to \(match) rather than refusing")
            return
        }
        #expect(basis == .emailAddress, "it stopped at the level that was ambiguous")
    }

    @Test("two clients sharing a NAME is ambiguous too")
    func twoOnOneNameIsAmbiguous() {
        let first = Self.client("Ashgrove Chamber Players")
        let second = Self.client("ashgrove chamber players")

        let match = BookingClientMatcher.match(
            downbeatClientID: nil, displayName: "Ashgrove Chamber Players",
            emails: [], against: [first, second])

        guard case .ambiguous(_, let basis) = match else {
            Issue.record("two clients on one name gave \(match)")
            return
        }
        #expect(basis == .nameOnly, "and normalisation is why the two were seen as one name")
    }

    @Test("nothing matching at all is NO MATCH, which is a different situation entirely")
    func nothingMatchingIsItsOwnOutcome() {
        // No match means create or ask. Several means the data is ambiguous.
        // Reporting one as the other sends the caller to do the opposite work.
        let other = Self.client("Harbour Line", email: "hello@harbour.example")

        let match = BookingClientMatcher.match(
            downbeatClientID: UUID(), displayName: "Nobody Ovation Knows",
            emails: ["new@somewhere.example"], against: [other])

        #expect(match == .noMatch)
        #expect(!match.linksWithoutAsking)
    }

    @Test("an empty roster is no match rather than a crash or an ambiguity")
    func anemptyRosterIsNoMatch() {
        let match = BookingClientMatcher.match(
            downbeatClientID: UUID(), displayName: "Anybody",
            emails: ["a@b.example"], against: [])

        #expect(match == .noMatch)
    }

    // MARK: against the real record

    @Test("the real handoff record resolves against a roster built from itself")
    func therealRecordMatches() throws {
        // The fixture is the record Downbeat actually wrote (ovation#29), so this
        // exercises the field names the producer really uses rather than the ones
        // a source reading assumed.
        let record = try HandoffFixture.load()
        let clientBlock = try #require(record["client"] as? [String: Any])
        let rawID = try #require(clientBlock["id"] as? String)
        let downbeatID = try #require(UUID(uuidString: rawID))

        let displayName = try #require(clientBlock["displayName"] as? String)
        let email = try #require(clientBlock["email"] as? String)
        let known = Self.client(displayName, email: email, downbeat: downbeatID)

        let match = BookingClientMatcher.match(
            downbeatClientID: downbeatID,
            displayName: clientBlock["displayName"] as? String,
            emails: [clientBlock["email"] as? String, clientBlock["contractEmail"] as? String]
                .compactMap { $0 },
            against: [known])

        #expect(match == .matched(clientID: known.id, on: .downbeatIdentifier))
    }
}

/// The committed handoff fixture, in one place, so every suite that needs it
/// reads the same file rather than growing its own copy of the path.
enum HandoffFixture {
    static func load(_ file: StaticString = #filePath) throws -> [String: Any] {
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        let url = here.appending(path: "Fixtures/handoff-record-v3-2026-09-06.json")
        let object = try JSONSerialization.jsonObject(with: try Data(contentsOf: url))
        return try #require(object as? [String: Any])
    }
}
