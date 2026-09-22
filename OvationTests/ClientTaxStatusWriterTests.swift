import Foundation
import SwiftData
import Testing

/// ovation#457, PRD 5.5. Recording a client's sales tax status.
///
/// THE ANSWER IS A FACT ABOUT THE CLIENT, NOT THE INVOICE, which is why nothing
/// here refuses a sent invoice the way `InvoiceDueDateWriter` does. `Invoice.tax`
/// reads the status at render time deliberately, a decision Dan made on
/// 2026-09-19 against the measurement that his own history has clients taxed on
/// some invoices and not others; PRD 5a1 records what that costs. A refusal
/// written here on the grounds that some invoice has gone out would contradict
/// that decision.
///
/// EVERY CASE DRIVES THE ACTOR FROM A DIFFERENT CONTEXT THAN THE ONE READING THE
/// RESULT BACK, the same arrangement the other two writers' suites use, because
/// the defect it exists to prevent is two contexts that do not merge.
@MainActor
struct ClientTaxStatusWriterTests {

    private static func roster() throws -> (ModelContainer, PersistentIdentifier) {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: "Cedar Hill Youth Orchestra", taxStatus: .neverRecorded)
        context.insert(client)
        try context.save()
        return (container, client.persistentModelID)
    }

    private static func read(_ id: PersistentIdentifier,
                             in container: ModelContainer) throws -> Client {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Client>())
            .first { $0.persistentModelID == id })
    }

    // MARK: the answer lands

    @Test("each answer a person can give is recorded", arguments: TaxStatus.answers)
    func eachanswerIsRecorded(_ answer: TaxStatus) async throws {
        let (container, clientID) = try Self.roster()

        try await ClientTaxStatusWriter(modelContainer: container)
            .setTaxStatus(answer, on: clientID)

        #expect(try Self.read(clientID, in: container).taxStatus == answer)
    }

    /// A STATUS ALREADY RECORDED CAN BE CORRECTED, which is the same decision:
    /// the status is a fact about the client and Dan's own history contains
    /// mistakes he made by hand.
    @Test("a status already recorded can be changed to the other answer")
    func arecordedStatusCanBeCorrected() async throws {
        let (container, clientID) = try Self.roster()
        let writer = ClientTaxStatusWriter(modelContainer: container)

        try await writer.setTaxStatus(.notExempt, on: clientID)
        try await writer.setTaxStatus(.exempt, on: clientID)

        #expect(try Self.read(clientID, in: container).taxStatus == .exempt)
    }

    // MARK: what cannot be written

    /// THE ABSENCE OF AN ANSWER IS NOT AN ANSWER. `TaxStatus.answers` keeps it off
    /// every screen, and this refuses it as well, because a screen gating a write
    /// is not the write being guarded (L196). Writing it would turn an answered
    /// client back into an unanswered one and quietly stop every invoice they have.
    @Test("never recorded is refused, and whatever was there is left alone")
    func neverrecordedIsRefused() async throws {
        let (container, clientID) = try Self.roster()
        let writer = ClientTaxStatusWriter(modelContainer: container)
        try await writer.setTaxStatus(.exempt, on: clientID)

        await #expect(throws: ClientTaxStatusRefusal.notAnAnswer) {
            try await writer.setTaxStatus(.neverRecorded, on: clientID)
        }
        #expect(try Self.read(clientID, in: container).taxStatus == .exempt,
                "the refused status was written anyway")
    }

    /// REMOVED SINCE THE SCREEN READ IT, which is the only way this can be reached
    /// from the invoice: the screen is a photograph taken at the last write.
    @Test("a client who is no longer there is refused by name")
    func agoneClientIsRefused() async throws {
        let (container, clientID) = try Self.roster()
        let context = ModelContext(container)
        for each in try context.fetch(FetchDescriptor<Client>()) { context.delete(each) }
        try context.save()

        await #expect(throws: ClientTaxStatusRefusal.noSuchClient) {
            try await ClientTaxStatusWriter(modelContainer: container)
                .setTaxStatus(.exempt, on: clientID)
        }
    }

    /// EVERY REFUSAL SAYS SOMETHING, because a control that does nothing and gives
    /// no reason leaves pressing it again as the only diagnosis available (L109).
    @Test("every refusal carries a sentence, and none of them is empty")
    func everyrefusalSaysSomething() {
        for refusal in ClientTaxStatusRefusal.allCases {
            #expect(refusal.sentence.isEmpty == false)
            #expect(refusal.sentence.hasSuffix("."))
        }
    }
}
