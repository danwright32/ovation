import Foundation
import SwiftData
import Testing

/// ovation#451. The one thing that says a writer committed.
///
/// WHY IT IS THE PLATFORM'S SIGNAL AND NOT OVATION'S. The obvious design is that
/// each writer tells the screen after it saves, and it is the wrong one: a
/// behaviour every call site must opt into cannot be enforced by a scan, so the
/// fifth actor somebody writes is the one that forgets, and the symptom is a
/// screen quietly showing an old answer (L621). That symptom IS ovation#451.
/// `ModelContext.didSave` is posted by `save()` itself, so nothing can write
/// without announcing it and no future writer can be wired up wrongly.
///
/// `SwiftDataBehaviourTests` measures the four platform facts this rests on, and
/// `ModelSaveNoticeProbe` records them. This suite is about Ovation's own part:
/// the scoping, the coalescing, and stopping when it is let go.
@MainActor
struct StoreWriteNoticesTests {

    /// Counts hand offs on the main actor, so a test can wait on the COUNT rather
    /// than on a duration (L290).
    @MainActor
    private final class Heard {
        private(set) var count = 0
        func heard() { count += 1 }
    }

    /// Waits until `condition` holds or gives up, and says which happened.
    ///
    /// THE WAIT IS ON THE CONDITION, never a sleep long enough to probably do it:
    /// a fixed wait asserts about the machine's load rather than about the code
    /// (L290). The deadline exists only so a broken case fails instead of hanging,
    /// and a run that reaches it is reported as a failure rather than passed over.
    private static func settle(
        until condition: @MainActor () -> Bool,
        within seconds: Double = 5
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private static func invoice(in context: ModelContext) throws -> PersistentIdentifier {
        let invoice = Invoice(client: nil, kind: .fromABooking, invoiceDate: nil,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        context.insert(invoice)
        try context.save()
        return invoice.persistentModelID
    }

    @Test("an actor's save reaches the listener, on the main actor")
    func anActorsSaveIsHeard() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let id = try Self.invoice(in: context)

        let heard = Heard()
        let notices = StoreWriteNotices(container: container) { heard.heard() }
        defer { notices.stop() }

        try await InvoiceNumberAllocator(modelContainer: container).allocate(to: id)

        #expect(await Self.settle(until: { heard.count >= 1 }),
                "the allocator saved and nothing reached the listener")
    }

    /// THE SCOPING, and it is not decoration. Every save in the process posts on
    /// this name, so an unscoped listener re-reads on every other container's
    /// writes. In the app there is one container and it would never show; in this
    /// suite it is every test running beside this one (L205, L463).
    @Test("a save into somebody else's store is not heard")
    func anotherStoresSaveIsIgnored() async throws {
        let mine = try OvationSchema.container(inMemory: true)
        let theirs = try OvationSchema.container(inMemory: true)
        let theirContext = ModelContext(theirs)
        let theirID = try Self.invoice(in: theirContext)

        let heard = Heard()
        let notices = StoreWriteNotices(container: mine) { heard.heard() }
        defer { notices.stop() }

        try await InvoiceNumberAllocator(modelContainer: theirs).allocate(to: theirID)

        // THE POSITIVE CONTROL IS IN THE SAME TEST, because "nothing was heard" is
        // satisfied by a listener that hears nothing at all, which is what a
        // broken registration looks like (L159). So after the foreign write is
        // ignored, this store writes and MUST be heard.
        let myContext = ModelContext(mine)
        let myID = try Self.invoice(in: myContext)
        try await InvoiceNumberAllocator(modelContainer: mine).allocate(to: myID)

        #expect(await Self.settle(until: { heard.count >= 1 }),
                "the listener heard nothing at all, so the case above proves nothing")
        #expect(heard.count == 1,
                "heard \(heard.count) times, so the other store's save was counted too")
    }

    /// A BURST IS ONE RE-READ. Re-deriving the whole list is paid per notice, and
    /// a bulk write that saves per row would pay it per row for one answer (L471).
    /// Coalescing is what makes the signal safe to attach to something as frequent
    /// as every save.
    ///
    /// IT IS DRIVEN THROUGH AN INJECTED CENTRE RATHER THAN BY REAL SAVES, and the
    /// reason is that real saves cannot show it. Awaiting each one hands the main
    /// actor back between them, so the hand off has already run and there is
    /// nothing to coalesce; the first version of this case did exactly that and
    /// measured eight of eight, which is correct behaviour reported as a failure.
    /// Posting synchronously, without giving the main actor a chance to drain, is
    /// the burst this exists for, and it is deterministic rather than a race the
    /// machine's load decides (L290, L293).
    ///
    /// The notices are real ones, carrying a real context of this container, so
    /// the scoping this passes through is the same scoping a save goes through.
    @Test("notices arriving faster than they can be drained are one hand off")
    func aburstCoalesces() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let center = NotificationCenter()

        let heard = Heard()
        let notices = StoreWriteNotices(container: container, center: center) { heard.heard() }
        defer { notices.stop() }

        let context = ModelContext(container)
        for _ in 0..<8 {
            center.post(name: ModelContext.didSave, object: context)
        }
        #expect(heard.count == 0, "a notice was handled before the main actor was yielded to")

        // NO DRAIN WAIT HERE, and that is the point of posting synchronously. All
        // eight posts run before the main actor is yielded to, so at most one Task
        // can have been scheduled: once one hand off has arrived, the count is
        // final and there is nothing still in flight to wait out. A pause "long
        // enough for the rest to arrive" would be an assertion about the machine's
        // load (L290).
        #expect(await Self.settle(until: { heard.count >= 1 }), "nothing was heard at all")
        #expect(heard.count == 1, "eight notices in one burst produced \(heard.count) hand offs")
    }

    /// AND THE SLOT IS RELEASED BEFORE THE HAND OFF RUNS, so a write arriving while
    /// a re-read is in flight books the next one rather than being swallowed. A
    /// coalescer that cleared its slot afterwards would drop exactly the write
    /// that lands during the work it triggered, which is the busiest moment.
    @Test("a notice arriving after the burst was drained is its own hand off")
    func alaterNoticeIsNotSwallowed() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let center = NotificationCenter()

        let heard = Heard()
        let notices = StoreWriteNotices(container: container, center: center) { heard.heard() }
        defer { notices.stop() }

        let context = ModelContext(container)
        center.post(name: ModelContext.didSave, object: context)
        #expect(await Self.settle(until: { heard.count == 1 }), "the first notice was not heard")

        center.post(name: ModelContext.didSave, object: context)
        #expect(await Self.settle(until: { heard.count == 2 }),
                "the second notice was swallowed by the first one's slot")
    }

    /// THE BARRIER IS ANOTHER LISTENER, not a pause. Proving that nothing arrived
    /// needs a moment after which it is known nothing more can, and waiting a
    /// couple of hundred milliseconds for that is an assertion about how loaded
    /// the machine is (L290). A second listener registered on the same centre gets
    /// the same post, so once IT has heard the write, the stopped one has had its
    /// chance at the very same notification and declined it.
    @Test("a listener that has been stopped hears nothing more")
    func astoppedListenerIsSilent() async throws {
        let container = try OvationSchema.container(inMemory: true)
        let context = ModelContext(container)
        let first = try Self.invoice(in: context)
        let second = try Self.invoice(in: context)

        let heard = Heard()
        let notices = StoreWriteNotices(container: container) { heard.heard() }

        let allocator = InvoiceNumberAllocator(modelContainer: container)
        try await allocator.allocate(to: first)
        #expect(await Self.settle(until: { heard.count >= 1 }), "nothing was heard before stopping")
        let before = heard.count

        notices.stop()

        let witness = Heard()
        let stillListening = StoreWriteNotices(container: container) { witness.heard() }
        defer { stillListening.stop() }

        try await allocator.allocate(to: second)
        #expect(await Self.settle(until: { witness.count >= 1 }),
                "the witness heard nothing either, so this case proves nothing")

        #expect(heard.count == before,
                "a stopped listener heard \(heard.count - before) more")
    }
}
