// Ported-From: danwright32/downbeat Downbeat/Downbeat/Integration/BlockingWork.swift @ 66966ccf9bab12427fff9949cf566d188616bafe
//
// Port discipline: docs/PORT-DISCIPLINE.md. Ported for ovation#246, because the
// launch's heavy work must leave the main actor and `Task.detached` is the wrong
// way to send it: `scripts/check-forbidden-constructs.sh` refuses it in this
// tree, and it is right. The cooperative pool is about one thread per core and
// does not grow, so work that BLOCKS a thread never gives it back (L241). A
// backup copies and hashes everything Ovation holds, which is exactly that
// shape.
//
// PORTED RATHER THAN REINVENTED, which is the whole point of L195: Downbeat
// built this after downbeat#402, and the lesson records that Overture and
// PostRoll each reached for the wrong mechanism nine days later. Writing a third
// one here would be the fourth time.
//
// WHAT DIFFERS FROM THE SOURCE, called out rather than inherited:
//
//   The keychain entry points are NOT ported. They are `BlockingWork.read`,
//   `.write` and `.delete` over Downbeat's `KeychainStore`, which Ovation does
//   not have: its own credential store arrives with ovation#76. Porting them
//   would be three functions over a type that does not exist, and a clone copies
//   a pattern AS FIRST WRITTEN including what it does not need (L501).
//
//   Everything else is taken whole, including the deadline, because both halves
//   are load bearing and the reasoning for each is measured in the source rather
//   than asserted.
//
// WHAT OVATION USES IT FOR, which is a different shape from the keychain and is
// why the generic half was worth taking: file copying and hashing onto a folder
// that may sync to a Synology. Those block, they can be slow for entirely
// ordinary reasons, and the deadline is what stops a slow volume becoming a
// launch that never finishes.
import Foundation

/// What blocking keychain work came back with, or did not (#402).
///
/// Three cases, never two. A read that has not answered yet, a read that
/// answered with a refusal, and a read that was abandoned are three different
/// situations with three different remedies, and flattening the last two into
/// "could not read the keychain" sends the person to fix a keychain that may be
/// working perfectly (L11).
enum BlockingWorkOutcome<Value: Sendable>: Sendable {
    case answered(Value)
    case failed(String)
    case gaveUp(after: Duration)
}

extension BlockingWorkOutcome: Equatable where Value: Equatable {}

/// The one place BLOCKING work is run from, whatever it blocks on (#402, #443).
///
/// Called `KeychainWork` until #443, because the keychain is where the incident came
/// from. It is not what the type does: since #439 it also runs the Settings file reads,
/// and a file reader calling something named for the keychain reads as a mistake. The
/// keychain detail below is kept in full, because it is why BOTH halves, the thread hop
/// and the deadline, are load bearing rather than defensive.
///
/// `SecItemCopyMatching` and its neighbours are synchronous, and they can block
/// for as long as they like: they go down through `securityd` into a decrypt
/// that may need the PERSON to authorize it. Run on the main thread that is a
/// deadlock, because the thread that would have to draw the question is the one
/// waiting for the answer.
///
/// Measured 2026-08-22, sampled three times across two builds: one click on the
/// Integrations tab put the main thread inside `SwiftUICore
/// Update.dispatchActions()`, in a view's `.onAppear`, down through
/// `SecKeychainItemCopyContent` into `CSSM_DecryptDataFinal`, and left it there.
/// The app kept running with no windows, no menu bar and no answer to its own
/// deep links. Nothing crashed and nothing was logged, so the only visible fact
/// was an app that had stopped existing (L236).
///
/// TWO halves, and both are load bearing. The work goes to another thread, so
/// the drawing thread stays free. And it goes under a DEADLINE, because a wait
/// with no deadline cannot fail, it can only hang, and a hang reads as slowness
/// for as long as anyone is willing to keep waiting (L110).
///
/// The deadline ABANDONS the wait rather than stopping the work, because a
/// blocking C call cannot be cancelled: `Task.cancel` sets a flag nothing in
/// `SecItemCopyMatching` ever reads. So a run that gives up leaves one thread
/// sitting in the keychain until it returns on its own. That is the trade, taken
/// deliberately: one parked thread against an app that needs a force quit.
nonisolated enum BlockingWork {

    /// How long a keychain call may take before the surface stops waiting on it.
    ///
    /// A read that is behaving costs microseconds, which
    /// `BlockingWorkTests.thedeadlineIsFarAboveAHealthyRead` measures in the same
    /// run rather than trusting this comment (L224). Five seconds is far above
    /// anything healthy and still short enough that nobody sits in front of a row
    /// that says nothing: past it the surface says it gave up and offers the
    /// person something to do.
    static let defaultDeadline: Duration = .seconds(5)

    /// Runs `body` off the calling thread and answers within `deadline`.
    ///
    /// `sleeping` is injected so a test can drive the deadline without paying it.
    static func run<Value: Sendable>(
        deadline: Duration = BlockingWork.defaultDeadline,
        sleeping: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        _ body: @escaping @Sendable () throws -> Value
    ) async -> BlockingWorkOutcome<Value> {
        let answer = FirstAnswer<Value>()

        // A DISPATCH queue, not `Task.detached`, and this is the load bearing part.
        //
        // Swift's cooperative pool has about one thread per core and does not grow: a
        // task that BLOCKS one never gives it back, and blocking is the entire premise
        // here, since `SecItemCopyMatching` is what this exists to survive. Measured
        // 2026-08-22 with `Task.detached`, a suite whose fixtures blocked a handful of
        // these killed the whole test process partway through, reporting 1835 failures
        // that were really one starved runtime. In the app the same shape would take
        // every other await down with it, which is a worse version of the hang #402
        // was about.
        //
        // Dispatch's global queues DO grow their thread pool, so a parked thread costs
        // one thread rather than a share of the only pool the app has.
        //
        // Nothing here is cancellable and nothing pretends to be: a blocking C call
        // reads no cancellation flag, so the deadline abandons the wait rather than
        // stopping the work.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                answer.offer(.answered(try body()))
            } catch {
                answer.offer(.failed(String(describing: error)))
            }
        }

        let timer = Task {
            do {
                try await sleeping(deadline)
            } catch is CancellationError {
                // The work answered first, so there is nothing left to time out.
                // The ONLY throw that may end this task quietly.
                return
            } catch {
                // Any other failure of the clock still ends the wait. Swallowing
                // it would leave the work with no deadline at all, which is the
                // hang this whole type exists to prevent, arriving by the one
                // route nobody would look at (L95, L110).
            }
            answer.offer(.gaveUp(after: deadline))
        }

        let outcome = await answer.wait()
        timer.cancel()
        return outcome
    }
}

/// Whichever of the two arrives first, once.
///
/// A plain continuation is not enough on its own: the work and the deadline race,
/// and resuming a continuation twice is a crash rather than a wasted call. The
/// lock is what makes "first wins" true rather than usually true.
private nonisolated final class FirstAnswer<Value: Sendable>: @unchecked Sendable {

    private let lock = NSLock()
    private var waiting: CheckedContinuation<BlockingWorkOutcome<Value>, Never>?
    private var early: BlockingWorkOutcome<Value>?
    private var delivered = false

    /// Offers an outcome. The first one through is the answer; the rest are
    /// dropped, including the abandoned work arriving long after the deadline.
    func offer(_ candidate: BlockingWorkOutcome<Value>) {
        var resume: CheckedContinuation<BlockingWorkOutcome<Value>, Never>?
        lock.lock()
        if !delivered && early == nil {
            if let waiting {
                delivered = true
                resume = waiting
                self.waiting = nil
            } else {
                early = candidate
            }
        }
        lock.unlock()
        resume?.resume(returning: candidate)
    }

    func wait() async -> BlockingWorkOutcome<Value> {
        await withCheckedContinuation { continuation in
            var ready: BlockingWorkOutcome<Value>?
            lock.lock()
            if let early, !delivered {
                delivered = true
                ready = early
            } else {
                waiting = continuation
            }
            lock.unlock()
            if let ready {
                continuation.resume(returning: ready)
            }
        }
    }
}
