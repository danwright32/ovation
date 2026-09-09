import Foundation
import SwiftData
import Testing

/// ovation#60 corrected, ovation#40. Where an invoice actually goes, and what is
/// genuinely wrong with a client's contact details.
///
/// CORRECTED 2026-09-07 after Dan read the roster round. The model had ONE email
/// field called `contractEmail` and treated its absence as a gap. That is
/// backwards: Downbeat exports `email` AND `contractEmail`, the second is an
/// OVERRIDE used by the handful of clients who want invoices sent somewhere other
/// than to the person who booked, and its absence is the ordinary case.
///
/// Measured against the custody export of 2026-09-05, counts only: 31 clients,
/// every one has a main email, 1 has an empty override, and the other 30 carry an
/// override that is an EXACT COPY of the main email. Not one client has a genuine
/// override today.
struct ClientContactTests {

    private static let day = Date(timeIntervalSince1970: 1_794_531_600)

    private static func client(
        email: String, contract: String? = nil
    ) -> Client {
        let c = Client(name: "A company", taxStatus: .notExempt)
        c.email = email
        c.contractEmail = contract
        return c
    }

    // MARK: where an invoice goes

    @Test("with no override, an invoice goes to the address of whoever booked")
    func noOverrideMeansTheMainEmail() {
        let c = Self.client(email: "hello@example.example")
        #expect(c.emailForInvoices == "hello@example.example")
        #expect(!c.hasInvoiceOverride)
    }

    @Test("with a different override, the invoice goes there and the main address does not")
    func anOverrideWins() {
        let c = Self.client(email: "director@example.example", contract: "treasurer@example.example")
        #expect(c.emailForInvoices == "treasurer@example.example")
        #expect(c.hasInvoiceOverride)
    }

    @Test("an override that is EMPTY is not an override, which is the case the real data has")
    func anEmptyOverrideIsNoOverride() {
        #expect(Self.client(email: "hello@example.example", contract: "").emailForInvoices
                == "hello@example.example")
        #expect(Self.client(email: "hello@example.example", contract: "   ").emailForInvoices
                == "hello@example.example")
        #expect(!Self.client(email: "hello@example.example", contract: "").hasInvoiceOverride)
    }

    @Test("an override that COPIES the main address is not an override either")
    func acopiedOverrideIsNoOverride() {
        // 30 of the 31 real clients are exactly this. Reporting them as having a
        // second address to check would be 30 findings about nothing.
        let c = Self.client(email: "hello@example.example", contract: "hello@example.example")
        #expect(c.emailForInvoices == "hello@example.example")
        #expect(!c.hasInvoiceOverride)
    }

    @Test("a copy differing only in case or spacing is still a copy")
    func aCopyIsMatchedLoosely() {
        let c = Self.client(email: "Hello@Example.example", contract: " hello@example.example ")
        #expect(!c.hasInvoiceOverride)
    }

    @Test("a client with nothing anywhere has nowhere to send, and says so rather than returning empty")
    func nothingAnywhereIsNil() {
        let c = Self.client(email: "", contract: "")
        #expect(c.emailForInvoices == nil)
        #expect(c.recipientsForInvoices.isEmpty)
        #expect(c.contactProblems.contains(.noAddressAtAll))
    }

    // MARK: several recipients, which is a VALUE and not a fault

    /// Dan, 2026-09-07, overruling PRD 38 as originally written: "I should be
    /// allowed to do two addresses in one field. there's nothing stopping me from
    /// invoicing 2 emails at the same company at the same time for the same
    /// event."
    ///
    /// 38a had refused this on the grounds that it "puts a recipient Dan never
    /// chose onto an invoice he reviewed and approved". He did choose them. The
    /// protection that rule was reaching for is the review screen showing every
    /// recipient (PRD 5.10, L64), which is where it belongs.
    @Test("two addresses in one field is a value meaning both, not a fault")
    func severalAddressesAreLegitimate() {
        let c = Self.client(email: "treasurer@example.example, director@example.example")
        #expect(c.contactProblems.isEmpty)
        #expect(c.recipientsForInvoices == ["treasurer@example.example", "director@example.example"])
    }

    @Test("a semicolon separates them too, and spacing around them does not matter")
    func separatorsAndSpacingAreTolerated() {
        let c = Self.client(email: " one@a.example ;two@b.example,  three@c.example ")
        #expect(c.recipientsForInvoices == ["one@a.example", "two@b.example", "three@c.example"])
        #expect(c.contactProblems.isEmpty)
    }

    @Test("one address is one recipient, which is 29 of the 31 real clients")
    func oneAddressIsOneRecipient() {
        #expect(Self.client(email: "hello@example.example").recipientsForInvoices
                == ["hello@example.example"])
    }

    // MARK: what is genuinely wrong (PRD 38, corrected)

    @Test("human text in an address field is the one thing that is actually broken")
    func textInAnAddressFieldIsBroken() {
        let c = Self.client(email: "ask at the box office")
        #expect(c.contactProblems.contains(.addressIsNotAnAddress))
        #expect(c.recipientsForInvoices.isEmpty, "nothing here can be sent to")
    }

    @Test("ONE bad part spoils the whole value, rather than the good parts being sent to")
    func amixedValueIsBroken() {
        // Sending to the parts that happen to parse would send an invoice to a
        // subset nobody chose, which is the thing PRD 38a was actually protecting.
        let c = Self.client(email: "good@example.example, ask at the box office")
        #expect(c.contactProblems.contains(.addressIsNotAnAddress))
        #expect(c.recipientsForInvoices.isEmpty)
    }

    @Test("a bad OVERRIDE is a problem even where the main address is fine")
    func abadOverrideIsStillAProblem() {
        let c = Self.client(email: "fine@example.example", contract: "ask at the box office")
        #expect(c.contactProblems.contains(.addressIsNotAnAddress))
    }

    @Test("an ordinary client has nothing wrong with it at all")
    func anOrdinaryClientIsClean() {
        #expect(Self.client(email: "hello@example.example").contactProblems.isEmpty)
        #expect(Self.client(email: "hello@example.example", contract: "hello@example.example")
                .contactProblems.isEmpty)
    }

    // MARK: a shared address, which warns and can be settled

    @Test("two clients on one address is a WARNING and never a refusal")
    func sharingWarnsRatherThanRefusing() {
        let c = Self.client(email: "office@shared.example")
        #expect(!c.sharesItsAddress(with: ["someone@else.example"]))
        #expect(c.sharesItsAddress(with: ["office@shared.example"]))
        #expect(c.contactProblems.isEmpty, "sharing is not a fault, so it is not a problem")
    }

    @Test("acknowledging that a shared address is correct stops it being raised again")
    func anAcknowledgementSettlesIt() {
        let c = Self.client(email: "office@shared.example")
        #expect(c.shareNeedsAnswering(against: ["office@shared.example"]))
        c.acknowledgeSharedAddress(on: .stamping(Self.day))
        #expect(!c.shareNeedsAnswering(against: ["office@shared.example"]),
                "it was answered, and every rule that asks must see the answer")
    }

    @Test("the acknowledgement is for THAT address, so changing it asks again")
    func changingTheAddressAsksAgain() {
        let c = Self.client(email: "office@shared.example")
        c.acknowledgeSharedAddress(on: .stamping(Self.day))
        #expect(!c.shareNeedsAnswering(against: ["office@shared.example"]))

        c.email = "different@shared.example"
        #expect(c.shareNeedsAnswering(against: ["different@shared.example"]),
                "a new address is a new question, and the old answer does not cover it")
    }

    @Test("an acknowledgement records WHEN it was given, not merely that it was")
    func theAcknowledgementCarriesItsDate() {
        let c = Self.client(email: "office@shared.example")
        c.acknowledgeSharedAddress(on: .stamping(Self.day))
        #expect(c.sharedAddressAcknowledgedOn?.dayKey == BusinessCalendar.dayKey(for: Self.day))
    }

    // MARK: it survives the store

    @Test("both addresses and the acknowledgement read back")
    func itAllRoundTrips() throws {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let c = Self.client(email: "director@example.example", contract: "treasurer@example.example")
        context.insert(c)
        c.acknowledgeSharedAddress(on: .stamping(Self.day))
        try context.save()

        let read = try #require(try context.fetch(FetchDescriptor<Client>()).first)
        #expect(read.email == "director@example.example")
        #expect(read.contractEmail == "treasurer@example.example")
        #expect(read.emailForInvoices == "treasurer@example.example")
        #expect(read.sharedAddressAcknowledgedOn != nil)
        #expect(!read.shareNeedsAnswering(against: ["director@example.example"]))
    }
}
