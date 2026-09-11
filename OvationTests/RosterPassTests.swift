import Foundation
import SwiftData
import Testing

/// ovation#40. The one pass that clears the roster before invoicing goes live,
/// as a value rather than as a screen.
///
/// THE COUNT AND THE ROWS IT PROMISES COME FROM ONE PLACE (L16). The screen says
/// "Started with 25 of 31", and if that number were computed beside the sections
/// rather than from them, the first time 25 on the left disagreed with the rows
/// on the right it would read as a defect in the data rather than in the screen.
///
/// WHAT IT STARTED WITH IS CAPTURED, NOT RECOMPUTED. The whole point of saying
/// the number is that the pass reads as a one time job rather than a standing
/// nag (PRD 5a), and a figure that counts down as you work is the nag. So it is
/// taken once, when the pass begins, and what is LEFT is what is derived.
///
/// A SHARED ADDRESS IS NOT IN THE PASS, settled with Dan on 2026-09-10 (PRD 5a,
/// 38c): it warns, it can never block a send, and this pass holds what blocks.
/// That is asserted here in both directions, because a rule about what is absent
/// is satisfied by a pass that finds nothing at all (L98).
struct RosterPassTests {

    private static func client(
        _ name: String,
        tax: TaxStatus = .notExempt,
        email: String = "hello@example.example",
        contract: String? = nil
    ) -> Client {
        let c = Client(name: name, taxStatus: tax)
        c.email = email
        c.contractEmail = contract
        return c
    }

    // MARK: what the pass CANNOT hold, which is why the chip has one look

    /// EVERY CLIENT IN THE TAX SECTION HAS NO RECORDED STATUS, by construction,
    /// which is what makes a chosen chip unreachable on that screen.
    ///
    /// `RosterPassView` used to draw a filled chip for the answer already
    /// recorded, taken from the design file, which carries the same branch. It
    /// can never fire: the section is built from `needingTaxStatus`, so the only
    /// value any of those clients holds is `neverRecorded`, and answering one
    /// takes it out of the section rather than marking it. The treatment was
    /// removed and this is the statement that keeps it removable (L29).
    @Test("no client in the tax section can already carry a status")
    func theTaxSectionHoldsOnlyUnansweredClients() {
        let pass = RosterPass(clients: [
            Self.client("A", tax: .neverRecorded),
            Self.client("B", tax: .exempt),
            Self.client("C", tax: .notExempt),
        ])

        #expect(pass.needingTaxStatus.count == 1)
        #expect(pass.needingTaxStatus.allSatisfy { $0.taxStatus == .neverRecorded })
    }

    // MARK: what the pass holds

    @Test("a client with no recorded tax status is in the pass")
    func missingTaxStatusIsInThePass() {
        let pass = RosterPass(clients: [Self.client("A", tax: .neverRecorded)])
        #expect(pass.needingTaxStatus.count == 1)
        #expect(pass.startedWith == 1)
        #expect(!pass.isSettled)
    }

    @Test("a client whose address is not an address is in the pass")
    func unusableAddressIsInThePass() {
        let pass = RosterPass(clients: [Self.client("A", email: "ring the office")])
        #expect(pass.withUnusableAddress.count == 1)
        #expect(pass.startedWith == 1)
    }

    @Test("a client with both is counted once, never twice")
    func bothProblemsCountOnce() {
        let pass = RosterPass(clients: [
            Self.client("A", tax: .neverRecorded, email: "ring the office")])
        #expect(pass.withUnusableAddress.count == 1)
        #expect(pass.needingTaxStatus.count == 1)
        #expect(pass.startedWith == 1)
    }

    @Test("the number it started with is the number of clients in it, never a second count")
    func theCountIsTheRows() {
        let pass = RosterPass(clients: [
            Self.client("A", tax: .neverRecorded),
            Self.client("B", tax: .neverRecorded, email: "ring the office"),
            Self.client("C"),
        ])
        let rows = Set(pass.withUnusableAddress.map(\.id))
            .union(pass.needingTaxStatus.map(\.id))
        #expect(pass.startedWith == rows.count)
        #expect(pass.startedWith == 2)
        #expect(pass.rosterSize == 3)
    }

    // MARK: what it deliberately does not hold

    @Test("two clients sharing an address are NOT in the pass")
    func aSharedAddressIsNotInThePass() {
        let pass = RosterPass(clients: [
            Self.client("A", email: "office@example.example"),
            Self.client("B", email: "office@example.example"),
        ])
        #expect(pass.startedWith == 0)
        #expect(pass.isSettled)
    }

    @Test("and the same two are still in it when one of them also lacks a status")
    func aSharedAddressDoesNotHideAReasonToBeThere() {
        let pass = RosterPass(clients: [
            Self.client("A", tax: .neverRecorded, email: "office@example.example"),
            Self.client("B", email: "office@example.example"),
        ])
        #expect(pass.startedWith == 1)
        #expect(pass.needingTaxStatus.count == 1)
    }

    // MARK: what it started with, against what is left

    @Test("answering one leaves the started figure alone and lowers what is left")
    func startedWithDoesNotCountDown() {
        let a = Self.client("A", tax: .neverRecorded)
        let b = Self.client("B", tax: .neverRecorded)
        let pass = RosterPass(clients: [a, b])
        #expect(pass.startedWith == 2)
        #expect(pass.remaining == 2)

        a.taxStatus = .exempt
        #expect(pass.startedWith == 2, "the figure the screen shows must not count down")
        #expect(pass.remaining == 1)
        #expect(!pass.isSettled)

        b.taxStatus = .notExempt
        #expect(pass.startedWith == 2)
        #expect(pass.remaining == 0)
        #expect(pass.isSettled)
    }

    @Test("an empty roster is settled and says it started with nothing")
    func anEmptyRosterIsSettled() {
        let pass = RosterPass(clients: [])
        #expect(pass.startedWith == 0)
        #expect(pass.remaining == 0)
        #expect(pass.isSettled)
        #expect(pass.rosterSize == 0)
    }
}
