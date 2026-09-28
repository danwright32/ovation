import Foundation
import SwiftData
import Testing

/// ovation#568, PRD 51j and 38c. The client page's standing payment terms and its
/// "That is correct" for a shared address, written by an actor and read back from
/// another context, as every writer's tests do.
@MainActor
struct ClientStandingWriterTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    private static func client(email: String = "office@draytonarts.example") throws
        -> (ModelContainer, PersistentIdentifier) {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let client = Client(name: "Drayton Wind Ensemble", taxStatus: .exempt)
        client.email = email
        context.insert(client)
        try context.save()
        return (container, client.persistentModelID)
    }

    private static func read(_ id: PersistentIdentifier, in container: ModelContainer) throws -> Client {
        try #require(try ModelContext(container).fetch(FetchDescriptor<Client>())
            .first { $0.persistentModelID == id })
    }

    @Test("each of the four terms is recorded as the client's standing terms")
    func eachTermIsRecorded() async throws {
        for term in PaymentTerms.all {
            let (container, id) = try Self.client()
            try await ClientStandingWriter(modelContainer: container).setPaymentTerm(term, on: id)
            #expect(try Self.read(id, in: container).paymentTermDays == term.days)
        }
    }

    @Test("a term the invoice's control does not offer is refused, and nothing changes")
    func anotherTermIsRefused() async throws {
        let (container, id) = try Self.client()

        await #expect(throws: ClientStandingRefusal.notATerm) {
            try await ClientStandingWriter(modelContainer: container)
                .setPaymentTerm(PaymentTerm(says: "45 days", days: 45), on: id)
        }
        #expect(try Self.read(id, in: container).paymentTermDays == nil)
    }

    @Test("a shared address said to be correct is recorded against that address")
    func asharedAddressIsAcknowledged() async throws {
        let (container, id) = try Self.client()

        try await ClientStandingWriter(modelContainer: container)
            .acknowledgeSharedAddress(on: id, day: .stamping(Self.noon))

        let client = try Self.read(id, in: container)
        #expect(client.sharedAddressAcknowledgedFor == "office@draytonarts.example")
        #expect(!client.shareNeedsAnswering(against: ["office@draytonarts.example"]))
    }

    @Test("a client gone since the page was read is refused by name")
    func agoneClientIsRefused() async throws {
        let (container, id) = try Self.client()
        let context = ModelContext(container)
        try context.delete(model: Client.self)
        try context.save()

        await #expect(throws: ClientStandingRefusal.noSuchClient) {
            try await ClientStandingWriter(modelContainer: container)
                .setPaymentTerm(PaymentTerms.standard, on: id)
        }
    }

    @Test("each refusal says what happened")
    func eachRefusalIsSaid() {
        #expect(ClientStandingRefusal.noSuchClient.sentence
                == "That client is no longer there, so nothing was saved.")
        #expect(ClientStandingRefusal.notATerm.sentence
                == "That is not one of the four terms, so nothing was saved.")
    }
}
