import Foundation
import Testing

/// ovation#461. Every field a version 3 handoff record carries, with the decision
/// taken about it.
///
/// A DECODER THAT DECLARES ONLY THE FIELDS IT NEEDS TODAY DISCARDS EVERY SIBLING
/// IN THE SAME OBJECT, and nothing anywhere reports the loss (L425).
/// `HandoffRecord` already refuses that: it decodes and keeps every field
/// Downbeat sends. The drafter is where the loss can happen instead, by carrying
/// a field into no part of the store, and ovation#457 then asks Dan for a value
/// Downbeat already sent.
///
/// SO THE ENUMERATION IS THE TEST. Each field is listed below with what becomes
/// of it, read off the record's own shape rather than off a list somebody
/// maintained beside it (L41, L96): a field Downbeat adds appears here as a
/// failure naming the field, with nowhere for the decision to be missed.
struct BookingFieldDecisionsTests {

    private static func fixtureData(_ file: StaticString = #filePath) throws -> Data {
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        return try Data(contentsOf: here.appending(path: "Fixtures/handoff-record-v3-2026-09-06.json"))
    }

    private static func record() throws -> HandoffRecord {
        guard case .read(let record) = HandoffRecord.read(try Self.fixtureData()) else {
            throw Missing.theFixtureDidNotDecode
        }
        return record
    }

    private enum Missing: Error { case theFixtureDidNotDecode }

    private static func fields(of subject: Any) -> Set<String> {
        Set(Mirror(reflecting: subject).children.compactMap(\.label))
    }

    /// WHAT BECOMES OF THE BOOKING'S FIELDS.
    ///
    ///   `id`              the shoot's `bookingKey`, which is the home of the key
    ///                     (`BookingDrafter` says why it is the shoot and not the
    ///                     invoice).
    ///   `clientID`        the strongest matching basis, the only one that links
    ///                     without asking.
    ///   `clientDisplayName`  the weakest matching basis, and the name a
    ///                     name only refusal has to speak.
    ///   `shootName`       the shoot's name.
    ///   `startDate`       the shoot's day, the invoice's date, and through PRD
    ///                     5.7 the due date.
    ///   `endDate`         NOT carried. A shoot's day is the day it STARTED,
    ///                     which is what `ShootWhen.day` means everywhere else in
    ///                     this product, and a booking whose end date differs is
    ///                     a shoot that ran past midnight, already covered by
    ///                     that. The measured record is such a shoot: its
    ///                     instants cross midnight UTC and both its day strings
    ///                     say the 6th.
    ///   `startsAt`        NOT carried, deliberately, PRD 3a and 3c. Downbeat's
    ///   `endsAt`          times are a placeholder nothing may be priced from,
    ///                     and Dan types the real ones on the invoice screen.
    ///                     This is the single easiest mapping in the drafter to
    ///                     write by accident, and doing it prices every invoice
    ///                     from a guess.
    ///   `venueID`         NOT carried. Ovation has no venue roster to point at:
    ///                     `Shoot.venue` is a string. ovation#95 is where a venue
    ///                     gets a surface.
    ///   `venueName`       the shoot's venue.
    ///   `isRerunOf`       the second key the already drafted check reads, so a
    ///                     rerun does not draft a second invoice for one shoot.
    @Test("every field the booking carries has a decision recorded against it")
    func everybookingFieldHasADecision() throws {
        let carried: Set<String> = ["id", "clientID", "clientDisplayName", "shootName",
                                    "startDate", "venueName", "isRerunOf"]
        let deliberatelyNotCarried: Set<String> = ["endDate", "startsAt", "endsAt", "venueID"]

        let decided = carried.union(deliberatelyNotCarried)
        let found = Self.fields(of: try Self.record().booking)
        let undecided = found.subtracting(decided)
        let gone = decided.subtracting(found)

        #expect(found == decided,
                "the booking carries \(undecided) that nothing has decided about, and \(gone) is gone")
    }

    /// WHAT BECOMES OF THE CLIENT'S FIELDS, on the arm that creates one.
    ///
    ///   `id`              the client's `downbeatClientID`, which is what makes
    ///                     every later run match on the basis that cannot drift.
    ///   `displayName`     the client's name.
    ///   `email`           the client's email.
    ///   `contractEmail`   the client's contract email.
    ///   `isTaxExempt`     the client's tax status, in three states, because an
    ///                     absent answer must never read as confirmed taxable
    ///                     (PRD 5, L257).
    ///   `shortName`       NOT carried. `Client` has no field for any of these
    ///   `phoneNumber`     five: they are Downbeat's own business, measured
    ///   `notes`           2026-09-21 against `Client.swift`, and ovation#32
    ///   `hasLeftReview`   revisits them when the drain is built. Recorded here
    ///   `specialBehaviors`  rather than dropped silently, because a field with
    ///   `hostingSite`     nowhere to go is exactly what this enumeration exists
    ///                     to make visible.
    @Test("every field the frozen client carries has a decision recorded against it")
    func everyclientFieldHasADecision() throws {
        let carried: Set<String> = ["id", "displayName", "email", "contractEmail", "isTaxExempt"]
        let noHomeOnClient: Set<String> = ["shortName", "phoneNumber", "notes",
                                           "hasLeftReview", "specialBehaviors", "hostingSite"]

        let decided = carried.union(noHomeOnClient)
        let found = Self.fields(of: try Self.record().client)
        let undecided = found.subtracting(decided)

        #expect(found == decided, "the client carries \(undecided) that nothing has decided about")
    }

    /// AND THE RECORD'S OWN FOUR.
    ///
    ///   `version`         the floor gate, in `HandoffRecord.read`.
    ///   `committedAt`     NOT carried. The invoice is dated from the SHOOT, which
    ///                     is what lets an unconsumed record turning up months
    ///                     later still produce the right tax year.
    ///   `booking`         above.
    ///   `client`          above.
    ///   `venue`           NOT carried, and absent on the one real record there
    ///                     is. Everything on it (the editing profile, the staff
    ///                     notification addresses, the address) is about running
    ///                     the shoot rather than billing it, and `Shoot.venue` is
    ///                     a name. ovation#95 is where it gets a surface.
    @Test("every field the record itself carries has a decision recorded against it")
    func everyrecordFieldHasADecision() throws {
        let decided: Set<String> = ["version", "committedAt", "booking", "client", "venue"]

        let found = Self.fields(of: try Self.record())
        let undecided = found.subtracting(decided)

        #expect(found == decided, "the record carries \(undecided) that nothing has decided about")
    }
}
