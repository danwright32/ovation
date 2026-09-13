import Foundation
import Testing

/// ovation#246. WHAT A PERSON SEES WHILE OVATION IS STARTING.
///
/// The launch sequence runs before any window exists, deliberately: identify,
/// checkpoint, back up, and only then open, because opening is the risky moment.
/// The consequence was that a launch had nowhere to say anything, so a slow
/// backup and a failure to start looked identical.
///
/// Dan's standing rule: a time taking action must make STARTED, STILL ALIVE and
/// FAILED three visibly different things, and a bare indefinite wait is a
/// defect. This is the state those three are read from.
@MainActor
struct LaunchProgressTests {

    @Test("a launch that has not said anything yet is still starting")
    func startsPreparing() {
        let progress = LaunchProgress(now: { Self.instant })

        #expect(progress.phase == .preparing)
        #expect(!progress.sentence.isEmpty)
    }

    /// STARTED IS NOT THE SAME AS STILL ALIVE. The step changes as the sequence
    /// moves, which is what makes a live launch tell itself apart from a stuck
    /// one without anybody counting seconds.
    @Test("the sentence follows the step, so a live launch reads as moving")
    func theSentenceFollowsTheStep() {
        let progress = LaunchProgress(now: { Self.instant })

        progress.stepStarted(.backingUp)
        let backingUp = progress.sentence
        progress.stepStarted(.opening)

        #expect(backingUp != progress.sentence)
        #expect(backingUp == StoreLaunchSequence.Step.backingUp.sentence)
    }

    /// AND SECONDS ARE THE OTHER HALF, because a step that is itself slow does
    /// not change, and a screen frozen on one sentence is the indefinite wait
    /// this exists to replace.
    @Test("a launch that has been going a while says so")
    func aSlowLaunchSaysSo() {
        let clock = Clock(Self.instant)
        let progress = LaunchProgress(now: { clock.now })
        progress.stepStarted(.backingUp)

        #expect(!progress.isTakingLongerThanExpected)
        clock.now = Self.instant.addingTimeInterval(LaunchProgress.longEnoughToMention + 1)

        #expect(progress.isTakingLongerThanExpected)
    }

    /// THE THRESHOLD IS COUNTED FROM THE STEP, not from the launch. A launch
    /// that spent four seconds on three quick steps is not stuck; one that has
    /// spent four seconds on the SAME step might be.
    @Test("the clock restarts on each step, so quick steps never read as stuck")
    func theClockRestartsOnEachStep() {
        let clock = Clock(Self.instant)
        let progress = LaunchProgress(now: { clock.now })
        progress.stepStarted(.identifying)
        clock.now = Self.instant.addingTimeInterval(LaunchProgress.longEnoughToMention + 1)
        #expect(progress.isTakingLongerThanExpected)

        progress.stepStarted(.backingUp)

        #expect(!progress.isTakingLongerThanExpected)
    }

    @Test("a launch that opened is done, and says nothing more")
    func openedIsDone() {
        let progress = LaunchProgress(now: { Self.instant })

        progress.finished(.opened)

        #expect(progress.phase == .opened)
    }

    /// FAILED IS ITS OWN STATE AND CARRIES THE REASON. A refusal that left the
    /// screen saying "starting" for ever is the third state collapsing into the
    /// first (L98).
    @Test("a launch that refused says so, and says which step refused")
    func refusedSaysWhich() {
        let progress = LaunchProgress(now: { Self.instant })

        progress.finished(.refused(step: .checkpoint, detail: "a reader is holding it open"))

        guard case .refused(let detail) = progress.phase else {
            Issue.record("a refusal did not reach the phase, got \(progress.phase)")
            return
        }
        #expect(detail.contains("a reader is holding it open"))
        #expect(progress.sentence.contains("a reader is holding it open"))
    }

    /// AND IT NEVER GOES BACKWARDS. A step arriving after the outcome, which a
    /// task can produce, must not put a finished launch back into starting.
    @Test("a step arriving after the end does not reopen a finished launch")
    func aLateStepDoesNotReopenIt() {
        let progress = LaunchProgress(now: { Self.instant })
        progress.finished(.opened)

        progress.stepStarted(.seeding)

        #expect(progress.phase == .opened)
    }

    private static let instant = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }
}
