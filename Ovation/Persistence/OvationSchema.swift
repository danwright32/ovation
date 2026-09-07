// ovation#60. The one list of what the store holds, and the one way to open it.
//
// EVERY MODEL TYPE IS NAMED HERE. A type missing from this list is simply absent
// from the store: SwiftData does not complain, it just has no table for it, and
// the first symptom is a fetch that returns nothing (L96). `models` is therefore
// checked against the sources by a script rather than maintained by whoever
// remembers, the same way the isolation floor is.
//
// THE LIVE STORE IS NOT REACHED FROM HERE. `StoreLocation.liveStoreURL()` is on
// the isolation floor and already refuses under a disposable launch; this factory
// takes a URL or builds an in memory container, so a test can never open the real
// one by forgetting an argument (L196, L2).
//
// IT DOES NOT RUN THE LAUNCH SEQUENCE. Identify, checkpoint, back up, then open
// is ovation#88, and putting it here would make every test pay for it and would
// hide the ordering inside a factory. This opens a container and nothing else.
import Foundation
import SwiftData

enum OvationSchema {
    /// Everything the store holds.
    static let models: [any PersistentModel.Type] = [
        Client.self,
        Invoice.self,
        Shoot.self,
        LineItem.self,
        ServiceType.self,
        Payment.self,
        PaymentAllocation.self,
        Refund.self,
    ]

    static var schema: Schema { Schema(models) }

    /// A container over a store file, or an in memory one for tests.
    ///
    /// The URL is REQUIRED for an on disk container rather than defaulted,
    /// because a default would be the platform's own path and a caller that
    /// forgot the argument would silently get a store somewhere nobody chose.
    static func container(at url: URL) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
    }

    static func container(inMemory: Bool) throws -> ModelContainer {
        precondition(inMemory, "an on disk container is opened with container(at:)")
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }
}
