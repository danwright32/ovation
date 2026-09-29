// ovation#604. WHAT A DISPOSABLE LAUNCH OPENS IN PLACE OF DAN'S STORE.
//
// A disposable launch may touch nothing real (`AppEnvironment`), so the launch
// sequence never runs in one: `StoreLocation.liveStoreURL` answers nil and there
// is nothing to identify, back up or open. Before this, that also meant the
// launch never FINISHED. The window sat on the Starting screen for the whole of
// every hosted run, so no hosted test ever saw the shell inside the window the
// `Window` scene makes, and a regression only that window has (its appearance,
// its title bar, its safe area) shipped unseen: the dark title bar Dan saw on
// 2026-09-27 went out that way (L3, L472).
//
// SO A DISPOSABLE LAUNCH CAN OPEN A STORE IN MEMORY, and hands it on exactly as
// the real sequence hands on the one it opened, so everything from the container
// to the window is the code a real launch runs. In memory, never a file: nothing
// a test host does can reach Dan's data, and nothing it writes outlives it (L2).
//
// ONLY WHEN A TEST ASKS (`Gate`). Opened at once, the window would leave Starting
// before any test could look at it, and Starting is the screen the #593 pin was
// measured missing on: the shell pins its own window, so a window already on the
// shell cannot show whether the scene's pin is there. Held until asked, one test
// can ask of Starting and then of the shell, in that order, in one place.
//
// NIL FOR A REAL LAUNCH, decided here from the one predicate every refusal reads
// (L261), so the app's launch cannot hand Dan a store that vanishes when he quits,
// nor wait on a test that will never come.
import Foundation
import SwiftData

enum DisposableLaunchStore {

    /// What was opened, and how the launch ended, in the terms `LaunchProgress`
    /// already reads for a real one.
    struct Opening {
        let container: ModelContainer?
        let outcome: StoreLaunchSequence.Outcome
    }

    /// Holds a disposable launch on Starting until a test asks for the store.
    ///
    /// AN ASK BEFORE THE WAIT IS KEPT, not lost: the test and the launch's task
    /// race, and a gate that only released waiters already waiting would leave
    /// the window on Starting whenever the test won.
    @MainActor
    final class Gate {
        static let shared = Gate()

        private var asked = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func ask() {
            asked = true
            let released = waiting
            waiting = []
            for continuation in released { continuation.resume() }
        }

        func wait() async {
            if asked { return }
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    /// A store in memory for a disposable launch once a test asks for it, or nil
    /// at once for a real launch.
    @MainActor
    static func openWhenAsked(
        isDisposableLaunch: Bool = AppEnvironment.isDisposableLaunch(),
        gate: Gate = .shared
    ) async -> Opening? {
        guard isDisposableLaunch else { return nil }
        await gate.wait()
        return open(isDisposableLaunch: isDisposableLaunch)
    }

    /// A store in memory for a disposable launch, or nil for a real one.
    ///
    /// A STORE THAT WILL NOT OPEN IS A REFUSAL, carrying the reason, so the window
    /// leaves Starting for the problems window rather than waiting for ever (L98).
    /// It names the same step the real sequence names when its open fails.
    @MainActor
    static func open(
        isDisposableLaunch: Bool = AppEnvironment.isDisposableLaunch(),
        make: () throws -> ModelContainer = { try OvationSchema.container(inMemory: true) }
    ) -> Opening? {
        guard isDisposableLaunch else { return nil }
        do {
            return Opening(container: try make(), outcome: .opened)
        } catch {
            return Opening(
                container: nil,
                outcome: .refused(
                    step: .identify,
                    detail: "the store this test launch keeps in memory would not open: "
                        + error.localizedDescription))
        }
    }
}
