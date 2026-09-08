import Foundation
import Testing
@testable import Ovation

/// ovation#21. `venueName` is authoritative and `venues[]` is not, settled by the
/// measurement rather than by preference.
struct BookingVenueTests {

    /// EVERY VENUE NAME BELOW IS FABRICATED, and that is not fastidiousness.
    /// The first draft of this suite used the real names from the measurement in
    /// ovation#21, and the identity guard refused the push with six occurrences
    /// in this file. It was right: this repository is public, and those are
    /// venues Dan actually shoots at. The names carry nothing the test needs, so
    /// nothing is lost by inventing them (L155: redact where the evidence is
    /// RECORDED rather than trusting the implementer to anonymise it later).
    @Test("a named venue is what goes on the invoice")
    func anamedVenueIsUsed() {
        let venue = BookingVenueReader.read(venueName: "Ashgrove Hall")

        #expect(venue == .named("Ashgrove Hall"))
        #expect(venue.mayBeSent)
        #expect(venue.forTheInvoice == "Ashgrove Hall")
    }

    @Test("a venue with no row in venues[] still resolves, which is the whole finding")
    func avenueMissingFromTheListStillResolves() {
        // Measured 2026-09-06: of the six distinct venue names bookings use,
        // THREE have no row in `venues[]`. A consumer resolving through that list
        // would find nothing for three real shoots and would do it silently.
        for name in ["Harbour Line Rooms", "The Society for Fabricated Culture", "Yarrow Park"] {
            #expect(BookingVenueReader.read(venueName: name) == .named(name))
            #expect(BookingVenueReader.read(venueName: name).mayBeSent)
        }
    }

    @Test("TBD is NOT DECIDED YET, which is neither a venue nor an absence")
    func aplaceholderIsItsOwnOutcome() {
        // One real booking on the live schedule carries this. It is a deliberate
        // "not chosen", so it must not be printed on an invoice and must not be
        // read as nothing having been sent.
        let venue = BookingVenueReader.read(venueName: "TBD")

        #expect(venue == .notDecidedYet(placeholder: "TBD"))
        #expect(!venue.mayBeSent)
        #expect(venue.forTheInvoice == nil, "an invoice must never print TBD where a venue goes")
        #expect(venue != .absent, "absent means Downbeat sent nothing, which is a different fact")
    }

    @Test("a placeholder is matched whole and case insensitively, never as a substring")
    func aplaceholderIsMatchedWhole() {
        // A substring match would refuse a real venue that happens to contain the
        // letters, and the cost of that is a shoot Ovation will not invoice.
        #expect(BookingVenueReader.read(venueName: "tbd") == .notDecidedYet(placeholder: "tbd"))
        #expect(BookingVenueReader.read(venueName: " TBD ")
            == .notDecidedYet(placeholder: "TBD"), "trimmed before it is judged")
        #expect(BookingVenueReader.read(venueName: "Tbdale Hall") == .named("Tbdale Hall"))
        #expect(BookingVenueReader.read(venueName: "The TBD Rooms") == .named("The TBD Rooms"))
    }

    @Test("no venue at all is ABSENT, which is not the same as not decided yet")
    func nothingSentIsAbsent() {
        // They lead to different work: absent is a record Downbeat sent without
        // one, not decided is Dan's to settle in Downbeat.
        #expect(BookingVenueReader.read(venueName: nil) == .absent)
        #expect(BookingVenueReader.read(venueName: "") == .absent)
        #expect(BookingVenueReader.read(venueName: "   ") == .absent)
        #expect(!BookingVenueReader.read(venueName: nil).mayBeSent)
    }

    @Test("the real handoff record's venue resolves from its NAME, with no venue row present")
    func therealRecordResolvesFromTheName() throws {
        // The record ovation#29 captured was committed with an AD HOC venue, so
        // it carries `booking.venueName` and no `venue` object at all. That is
        // the case a consumer reading `venues[]` gets wrong, and it is the
        // commonest one this contract has.
        let record = try HandoffFixture.load()
        #expect(record["venue"] == nil, "the record carries no venue object")

        let booking = try #require(record["booking"] as? [String: Any])
        let name = try #require(booking["venueName"] as? String)
        let venue = BookingVenueReader.read(venueName: name)

        #expect(venue == .named(name))
        #expect(venue.mayBeSent,
                "and it can be invoiced, which resolving through venues[] would not have allowed")
    }
}
