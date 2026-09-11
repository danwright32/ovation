import Foundation
import Testing

/// ovation#208. What the import decides to do about each client in Downbeat's
/// export, and what it then does to the store.
///
/// THE DECISION IS SEPARATE FROM THE WRITE, deliberately. `plan` is a pure
/// function of the export rows and the clients Ovation holds, so every rule below
/// is tested without a store, a container or a file. `apply` is the only part
/// that mutates, and it is handed the plan rather than re-deciding, so a rule can
/// never be enforced in one and forgotten in the other.
///
/// THE MATCHING IS NOT REIMPLEMENTED HERE. `BookingClientMatcher` already answers
/// which client a Downbeat record names, with more than one match as its own
/// refusal (ovation#34, L521), and it is reused rather than copied. These cases
/// assert what the IMPORT does with each of its answers, not the matching itself.
struct ClientImportTests {

    // MARK: fixtures

    private static func held(
        _ name: String,
        email: String = "",
        contract: String? = nil,
        downbeat: UUID? = nil,
        tax: TaxStatus = .neverRecorded
    ) -> Client {
        let client = Client(name: name, taxStatus: tax)
        client.email = email
        client.contractEmail = contract
        client.downbeatClientID = downbeat
        return client
    }

    private static func row(
        id: UUID = UUID(),
        name: String = "A choir",
        email: String = "bookings@example.com",
        contract: String = "",
        taxExempt: Bool? = nil
    ) -> DownbeatExport.Client {
        DownbeatExport.Client(id: id, displayName: name, email: email,
                              contractEmail: contract, isTaxExempt: taxExempt)
    }

    // MARK: the first run, which is the one that matters most

    /// THE WHOLE REASON THIS EXISTS. Before this, no code in Ovation constructed a
    /// client outside the model file itself, so the roster screen was correct and
    /// drew nothing.
    @Test("against an empty store every row is a client to create")
    func anEmptyStoreCreatesEverything() {
        let rows = [Self.row(name: "A choir"), Self.row(name: "B orchestra")]
        let plan = ClientImport.plan(for: rows, against: [])
        #expect(plan.count == 2)
        #expect(plan.allSatisfy { if case .create = $0 { return true } else { return false } })
    }

    @Test("creating carries the name, both addresses and Downbeat's own id")
    func creatingCarriesTheFields() {
        let id = UUID()
        let row = Self.row(id: id, name: "A choir", email: "a@example.com",
                           contract: "treasurer@example.com")
        var store: [Client] = []
        let made = ClientImport.apply(ClientImport.plan(for: [row], against: store), to: &store)
        #expect(made.count == 1)
        #expect(made[0].name == "A choir")
        #expect(made[0].email == "a@example.com")
        #expect(made[0].contractEmail == "treasurer@example.com")
        #expect(made[0].downbeatClientID == id)
    }

    // MARK: the tax status, which is the field with two owners

    @Test("a client Downbeat marks exempt arrives exempt")
    func exemptArrivesExempt() {
        var store: [Client] = []
        let made = ClientImport.apply(
            ClientImport.plan(for: [Self.row(taxExempt: true)], against: store), to: &store)
        #expect(made[0].taxStatus == .exempt)
    }

    @Test("a client Downbeat marks not exempt arrives not exempt")
    func notExemptArrivesNotExempt() {
        var store: [Client] = []
        let made = ClientImport.apply(
            ClientImport.plan(for: [Self.row(taxExempt: false)], against: store), to: &store)
        #expect(made[0].taxStatus == .notExempt)
    }

    /// THE 25. A client with no answer upstream arrives with no answer here, which
    /// is what the roster pass exists to clear. Defaulting to not exempt would
    /// report a client as confirmed taxable on the strength of nothing and would
    /// empty the pass of the work it was built for (PRD 5, PRD 5a, L257).
    @Test("a client Downbeat never answered arrives never recorded")
    func unansweredArrivesUnanswered() {
        var store: [Client] = []
        let made = ClientImport.apply(
            ClientImport.plan(for: [Self.row(taxExempt: nil)], against: store), to: &store)
        #expect(made[0].taxStatus == .neverRecorded)
    }

    /// OVATION OWNS THIS FIELD ONCE DAN HAS ANSWERED IT. The import runs on every
    /// launch, so a rule that refreshed the status from Downbeat would silently
    /// undo the roster pass every time the app started, and the pass would never
    /// stay cleared.
    @Test("an answer given in Ovation is never overwritten by the export")
    func ovationsAnswerWins() {
        let id = UUID()
        var store = [Self.held("A choir", downbeat: id, tax: .exempt)]
        let row = Self.row(id: id, taxExempt: false)
        _ = ClientImport.apply(ClientImport.plan(for: [row], against: store), to: &store)
        #expect(store[0].taxStatus == .exempt)
    }

    /// AND IT IS NOT OVERWRITTEN BY AN ABSENCE EITHER, which is the commoner case:
    /// 25 of 31 rows carry no status at all, so a rule that simply assigned the
    /// export's value would reset every answer to never recorded.
    @Test("an answer given in Ovation survives a row that carries no status")
    func ovationsAnswerSurvivesAnEmptyUpstreamValue() {
        let id = UUID()
        var store = [Self.held("A choir", downbeat: id, tax: .exempt)]
        _ = ClientImport.apply(
            ClientImport.plan(for: [Self.row(id: id, taxExempt: nil)], against: store), to: &store)
        #expect(store[0].taxStatus == .exempt)
    }

    /// The other direction: a client Ovation has no answer for takes one that
    /// appears upstream, because there is nothing here to protect.
    @Test("a client with no answer here takes one that appears upstream")
    func anUnansweredClientTakesAnUpstreamAnswer() {
        let id = UUID()
        var store = [Self.held("A choir", downbeat: id, tax: .neverRecorded)]
        _ = ClientImport.apply(
            ClientImport.plan(for: [Self.row(id: id, taxExempt: true)], against: store), to: &store)
        #expect(store[0].taxStatus == .exempt)
    }

    // MARK: re-running, which happens at every launch

    @Test("a client already held is updated rather than created again")
    func aHeldClientIsUpdatedNotDuplicated() {
        let id = UUID()
        var store = [Self.held("A choir", email: "old@example.com", downbeat: id)]
        let plan = ClientImport.plan(for: [Self.row(id: id, name: "A choir",
                                                    email: "new@example.com")],
                                     against: store)
        guard case .update = plan[0] else {
            Issue.record("expected an update, got \(plan[0])")
            return
        }
        let made = ClientImport.apply(plan, to: &store)
        #expect(made.isEmpty)
        #expect(store.count == 1)
        #expect(store[0].email == "new@example.com")
    }

    /// Downbeat is where Dan maintains these, so a rename there reaches Ovation.
    @Test("a rename upstream reaches the client here")
    func aRenameUpstreamIsCarried() {
        let id = UUID()
        var store = [Self.held("Old name", downbeat: id)]
        _ = ClientImport.apply(
            ClientImport.plan(for: [Self.row(id: id, name: "New name")], against: store),
            to: &store)
        #expect(store[0].name == "New name")
    }

    /// MATCHING ON AN ADDRESS IS ALSO WHERE THE KEY IS LEARNED. A client created
    /// by some other route carries no Downbeat id, and stamping it on the first
    /// match is what makes every later run match on the basis that cannot drift.
    @Test("a client matched by address is stamped with Downbeat's id")
    func matchingByAddressLearnsTheIdentifier() {
        let id = UUID()
        var store = [Self.held("A choir", email: "a@example.com", downbeat: nil)]
        _ = ClientImport.apply(
            ClientImport.plan(for: [Self.row(id: id, email: "a@example.com")], against: store),
            to: &store)
        #expect(store[0].downbeatClientID == id)
    }

    // MARK: what it refuses to touch

    /// A NAME IS NOT AN IDENTITY. Two clients can legitimately share one, and a
    /// rename is exactly the case a name match cannot tell from a namesake. The
    /// matcher already says such a match may not link without asking, and this
    /// asserts the import obeys it rather than deciding again.
    @Test("a row matching on name alone is left alone and named")
    func aNameOnlyMatchIsLeftAlone() {
        var store = [Self.held("A choir", email: "held@example.com")]
        let plan = ClientImport.plan(
            for: [Self.row(name: "A choir", email: "different@example.com")], against: store)
        guard case .leftAlone(_, let why) = plan[0] else {
            Issue.record("expected the row to be left alone, got \(plan[0])")
            return
        }
        #expect(why == .matchedOnNameOnly)
        let made = ClientImport.apply(plan, to: &store)
        #expect(made.isEmpty, "a name only match must not create a second client either")
        #expect(store[0].email == "held@example.com", "and must not write over the held one")
    }

    /// MORE THAN ONE MATCH IS ITS OWN REFUSAL, never treated as no match. Creating
    /// here would manufacture a duplicate identity that every later invoice,
    /// payment and referral credit then feeds, and nothing downstream could tell
    /// the two apart afterwards (L521).
    @Test("a row matching more than one client is left alone, not created")
    func anAmbiguousMatchIsLeftAlone() {
        var store = [Self.held("A choir", email: "shared@example.com"),
                     Self.held("A choir under another name", email: "shared@example.com")]
        let plan = ClientImport.plan(for: [Self.row(email: "shared@example.com")], against: store)
        guard case .leftAlone(_, let why) = plan[0] else {
            Issue.record("expected the row to be left alone, got \(plan[0])")
            return
        }
        #expect(why == .matchedMoreThanOne)
        #expect(ClientImport.apply(plan, to: &store).isEmpty)
        #expect(store.count == 2)
    }

    // MARK: what it never does

    /// DAN CHOSE THIS (2026-09-11): a client that has gone from Downbeat is kept
    /// and nothing is said about it. Keeping it is not a preference: it may carry
    /// invoices, payments and referral credit, which are Ovation's financial
    /// history and Downbeat's deletion says nothing about them (L5, L9).
    @Test("a client no longer in the export is left exactly as it was")
    func aClientGoneUpstreamIsUntouched() {
        var store = [Self.held("Still here", downbeat: UUID(), tax: .exempt),
                     Self.held("Gone from Downbeat", downbeat: UUID(), tax: .notExempt)]
        let survivor = store[0].downbeatClientID!
        _ = ClientImport.apply(
            ClientImport.plan(for: [Self.row(id: survivor, name: "Still here")], against: store),
            to: &store)
        #expect(store.count == 2)
        #expect(store[1].name == "Gone from Downbeat")
        #expect(store[1].taxStatus == .notExempt)
    }

    /// AN EXPORT WITH NO CLIENTS DELETES NOTHING. The dangerous reading of an
    /// empty upstream list is that everything here has been removed, and that
    /// reading destroys the roster on the first bad export (L214, L98).
    @Test("an export carrying no clients changes nothing at all")
    func anEmptyExportChangesNothing() {
        var store = [Self.held("A choir", downbeat: UUID(), tax: .exempt)]
        let plan = ClientImport.plan(for: [], against: store)
        #expect(plan.isEmpty)
        #expect(ClientImport.apply(plan, to: &store).isEmpty)
        #expect(store.count == 1)
        #expect(store[0].taxStatus == .exempt)
    }

    // MARK: what it reports

    /// A RUN THAT CHANGED NOTHING MUST BE TELLABLE FROM A RUN THAT DID, or the
    /// launch step cannot decide whether to say anything, and a notice on every
    /// launch is one Dan learns to click past (L36).
    @Test("the outcome counts what it did, separately")
    func theOutcomeCountsEachKind() {
        let heldID = UUID()
        var store = [Self.held("A choir", downbeat: heldID),
                     Self.held("Shared one", email: "shared@example.com"),
                     Self.held("Shared two", email: "shared@example.com")]
        let rows = [Self.row(id: heldID, name: "A choir"),
                    Self.row(name: "Brand new"),
                    Self.row(email: "shared@example.com")]
        let summary = ClientImport.summary(of: ClientImport.plan(for: rows, against: store))
        #expect(summary.created == 1)
        #expect(summary.updated == 1)
        #expect(summary.leftAlone == 1)
        #expect(summary.changedSomething)

        let quiet = ClientImport.summary(of: ClientImport.plan(for: [], against: store))
        #expect(!quiet.changedSomething)
        _ = store
    }
}
