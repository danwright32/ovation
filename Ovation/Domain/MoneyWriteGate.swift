// ovation#175. The one thing that serializes every writer of money against an
// invoice.
//
// WHAT WAS WRONG. `PaymentAllocator` is a `@ModelActor`, so read, decide and
// write happen with nothing else in between, and its header says that is the
// whole reason allocation does not live on the model as a method. Its release
// carried the same claim: "it runs on the same actor as `allocate`, so a release
// and an allocation cannot interleave." That was true of ITS release and false
// of the other one. `InvoiceCloser.cancel` releases the same rows from a
// DIFFERENT `@ModelActor` with its own context, and `releaseActiveAllocations`
// iterates only what that context can see.
//
// So an allocation written while a cancellation is in flight survives it: the
// cancelled invoice keeps a live allocation, the money is neither released nor
// refunded, and the export cannot see it, because the payment does have an
// active allocation (ovation#176 is the shape of what that then reports).
//
// THE DOCSTRING IS WHY THIS MATTERS MORE THAN THE WINDOW. A recorded guarantee
// is the whole record of an exclusion, so every later reader takes it as
// established and writes against it (L407, L263). Two same-named things on
// either side of a boundary are never compared.
//
// WHY A GATE RATHER THAN ONE ACTOR. The two writers cannot simply be merged:
// `InvoiceCloser.cancel` does the prior year refusal, the money question, the
// refund rows and the closure, and its own header requires all of that to be ONE
// context and ONE save so a crash cannot leave the allocations released and the
// invoice open (L33). Nor can they share an executor: `@ModelActor` derives its
// executor from its own context, and taking that over is what makes the context
// safe to touch. What they can share is exclusion.
//
// IT IS PER STORE, NOT GLOBAL. Two containers are two independent sets of money,
// and a process wide gate would serialize a suite's parallel tests against each
// other for no reason, which is a shared mutable object several tests touch
// (L205). The registry is keyed on the container and holds it weakly, so a
// container that goes away takes its gate with it.
//
// IT IS A CLASS AND NOT AN ACTOR, and that is the whole of the design. An actor
// with an `async` unlock cannot be released from a `defer`, so every caller
// would have to unlock on each exit path by hand, which is the shape where one
// path gets missed and the gate is held for the life of the process (L515). A
// lock and a wait queue give a SYNCHRONOUS unlock, so `defer` covers every path
// including a throw.
import Foundation
import os
import SwiftData

/// A first come, first served async lock.
///
/// THE STATE IS BEHIND AN `OSAllocatedUnfairLock` RATHER THAN AN `NSLock`, and
/// that is a requirement rather than a preference: `NSLock.lock()` is unavailable
/// from an async context, because holding an OS lock across a suspension blocks
/// a cooperative pool thread, which is the failure L241 is about. This lock is
/// only ever held for the few instructions that move the queue, never across an
/// `await`.
final class MoneyWriteGate: @unchecked Sendable {
    private struct Waiting {
        var busy = false
        var queue: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: Waiting())

    /// Waits until nothing else is writing money, then takes the gate.
    func lock() async {
        let mine = state.withLock { waiting -> Bool in
            if waiting.busy { return false }
            waiting.busy = true
            return true
        }
        if mine { return }
        await withCheckedContinuation { continuation in
            let handOver = state.withLock { waiting -> CheckedContinuation<Void, Never>? in
                // TAKEN AGAIN INSIDE THE CONTINUATION, because the holder can
                // have finished between the two reads above and this one. Left
                // unchecked, a caller that arrived in that window would be
                // queued behind a gate nobody holds and would never be resumed.
                if !waiting.busy {
                    waiting.busy = true
                    return continuation
                }
                waiting.queue.append(continuation)
                return nil
            }
            handOver?.resume()
        }
    }

    /// Hands the gate to whoever is next, or leaves it free.
    ///
    /// SYNCHRONOUS ON PURPOSE, so `defer { gate.unlock() }` covers a throw, an
    /// early return and a refusal without any caller having to remember.
    func unlock() {
        let next = state.withLock { waiting -> CheckedContinuation<Void, Never>? in
            if waiting.queue.isEmpty {
                waiting.busy = false
                return nil
            }
            return waiting.queue.removeFirst()
        }
        next?.resume()
    }
}

/// The gate belonging to one store.
///
/// WEAKLY HELD. A suite makes a container per test and a strong registry would
/// keep every one of them alive for the run, which is a leak that grows with the
/// suite rather than with the app.
enum MoneyWriteGates {
    /// The table and the lock around it are one value, so the table cannot be
    /// reached without the lock.
    private final class Registry: @unchecked Sendable {
        private let mutex = NSLock()
        private let gates = NSMapTable<ModelContainer, MoneyWriteGate>
            .weakToStrongObjects()

        func gate(for container: ModelContainer) -> MoneyWriteGate {
            mutex.lock()
            defer { mutex.unlock() }
            if let found = gates.object(forKey: container) { return found }
            let made = MoneyWriteGate()
            gates.setObject(made, forKey: container)
            return made
        }
    }

    private static let registry = Registry()

    static func gate(for container: ModelContainer) -> MoneyWriteGate {
        registry.gate(for: container)
    }
}
