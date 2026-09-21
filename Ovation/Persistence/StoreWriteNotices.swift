// ovation#451. The one thing in Ovation that says a writer committed.
//
// WHAT WAS WRONG. `OvationApp` built the invoice list once, inside the launch,
// and held the result as values. Nothing rebuilt it, so the list, the sidebar
// card's counts and the rail's held money figure were a photograph of the store
// taken at launch. It was invisible by construction: nothing in the app could
// change an invoice yet, so the photograph was always current and every test
// passed (L3, L14).
//
// WHY THE SIGNAL IS THE PLATFORM'S AND NOT OVATION'S. The obvious design is that
// each writer tells the screen after it saves, and it is the wrong one. That is
// a behaviour every present and future writer has to opt into, and a behaviour
// each call site must opt into cannot be enforced by a scan (L621): the fifth
// actor somebody adds is the one that forgets, and its symptom is a screen
// quietly showing an old answer, which is exactly the defect this file exists to
// end. `ModelContext.didSave` is posted by `save()` itself, so nothing can write
// without announcing it and nothing can be wired up wrongly.
//
// THE FOUR PLATFORM FACTS IT RESTS ON ARE MEASURED, not assumed, because a
// platform guarantee is only true of the version it was measured on and SwiftData
// ships with the operating system (L82). `SwiftDataBehaviourTests` runs them on
// every suite and `ModelSaveNoticeProbe` records what macOS 26.5.1 answered:
//
//   1. a `@ModelActor`'s save DOES post `ModelContext.didSave`
//   2. the notice carries `inserted`, `updated` and `deleted`
//   3. the row the actor wrote is named under `updated`
//   4. at the instant of delivery a fresh reader can ALREADY see the write,
//      which is what makes re-reading on the notice give the new answer rather
//      than the old one with a notification bolted on top
//   5. the notice's `object` is the saving context, so it can be scoped to one
//      container
//
// IT IS SCOPED TO ONE STORE, and that is not decoration. Every save in the
// process posts on this name. In the app there is one container and an unscoped
// listener would never show it; in the suite it is every container every other
// test is holding, and the listener would re-read on all of them (L205, L463).
import Foundation
import SwiftData

/// Calls `onWrite`, on the main actor, after anything commits to this store.
final class StoreWriteNotices: @unchecked Sendable {

    /// Whether a hand off to the main actor is already on its way.
    ///
    /// A BURST IS ONE RE-READ. Re-deriving the whole list is paid per notice, and
    /// an operation that saves several times would pay it several times over for
    /// one answer (L471). The slot is released BEFORE `onWrite` runs, so a save
    /// arriving while the re-read is in flight books the next one rather than
    /// being swallowed.
    private final class Coalescer: @unchecked Sendable {
        private let mutex = NSLock()
        private var queued = false

        /// Takes the slot, or reports that somebody already holds it.
        func take() -> Bool {
            mutex.lock()
            defer { mutex.unlock() }
            if queued { return false }
            queued = true
            return true
        }

        func release() {
            mutex.lock()
            defer { mutex.unlock() }
            queued = false
        }
    }

    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    /// - Parameters:
    ///   - container: the store whose writes matter. Everything else in the
    ///     process is ignored.
    ///   - center: injected so a test can drive this without the process wide one.
    ///   - onWrite: run on the main actor, after the write is readable.
    init(
        container: ModelContainer,
        center: NotificationCenter = .default,
        onWrite: @escaping @MainActor @Sendable () -> Void
    ) {
        self.center = center
        let coalescer = Coalescer()
        // NOTHING IS CAPTURED FROM `self`, so the observer cannot keep this object
        // alive and there is no cycle to break. Stopping is removing the token,
        // and that is all it is.
        token = center.addObserver(
            forName: ModelContext.didSave, object: nil, queue: nil
        ) { notice in
            guard (notice.object as? ModelContext)?.container === container else { return }
            guard coalescer.take() else { return }
            Task { @MainActor in
                coalescer.release()
                onWrite()
            }
        }
    }

    /// Stops listening. Idempotent, so an owner may call it and then be released.
    func stop() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }

    deinit { if let token { center.removeObserver(token) } }
}
