// ovation#246. WHAT A PERSON SEES WHILE OVATION IS STARTING.
//
// The launch sequence runs before the store is opened, deliberately: identify,
// checkpoint, back up, and only then open, because opening is the risky moment
// (plan 1.2). Until now it also ran before any WINDOW existed, so a launch had
// nowhere to say anything: a slow backup and a failure to start looked
// identical, and there was not even a spinner, because there was no surface.
//
// Dan's standing rule: a time taking action must make STARTED, STILL ALIVE and
// FAILED three visibly different things, and a bare indefinite wait is a defect.
// This holds the state those three are read from, so the window can appear at
// once and the work can happen behind it with the ordering unchanged.
//
// TWO SIGNALS OF LIFE, because one is not enough. The STEP changes as the
// sequence moves, which distinguishes a live launch from a stuck one without
// anybody counting. And a step that is itself slow does not change, so the
// SECONDS on the current step are the other half: a screen frozen on one
// sentence is the indefinite wait this exists to replace.
import Foundation

@MainActor
@Observable
final class LaunchProgress {

    enum Phase: Equatable {
        case preparing
        case opened
        case refused(String)
    }

    /// How long one step may take before it is worth mentioning.
    ///
    /// NOT A THRESHOLD ON THE WHOLE LAUNCH. A launch that spent four seconds
    /// across three quick steps is not stuck; one that has spent four seconds on
    /// the SAME step might be, and that is the question worth asking.
    ///
    /// Three seconds because it is longer than any step takes on a local disk
    /// today and shorter than a person waits before wondering. It is a first
    /// value, and ovation#246 records that the real one comes from watching a
    /// backup onto the Synology, where the copying actually costs something.
    static let longEnoughToMention: TimeInterval = 3

    private(set) var phase: Phase = .preparing
    private(set) var step: StoreLaunchSequence.Step?

    private let now: @MainActor () -> Date
    private var stepStartedAt: Date

    init(now: @escaping @MainActor () -> Date = Date.init) {
        self.now = now
        self.stepStartedAt = now()
    }

    /// The sentence to put on screen. Domain, never interface: it says what
    /// Ovation is doing to Dan's records, not what a function is called (L604).
    var sentence: String {
        switch phase {
        case .preparing:
            return step?.sentence ?? "Starting"
        case .opened:
            return ""
        case .refused(let detail):
            return detail
        }
    }

    /// Whether the CURRENT step has been going long enough to be worth saying so.
    var isTakingLongerThanExpected: Bool {
        guard phase == .preparing else { return false }
        return now().timeIntervalSince(stepStartedAt) > Self.longEnoughToMention
    }

    func stepStarted(_ step: StoreLaunchSequence.Step) {
        // IT NEVER GOES BACKWARDS. A step arriving after the outcome, which a
        // task can produce, must not put a finished launch back into starting
        // (L14): the screen would then show "starting" over an app that is open.
        guard phase == .preparing else { return }
        self.step = step
        stepStartedAt = now()
    }

    func finished(_ outcome: StoreLaunchSequence.Outcome) {
        switch outcome {
        case .opened:
            phase = .opened
        case .refused(let step, let detail):
            // THE REASON TRAVELS WITH IT. A refusal that left the screen saying
            // "starting" for ever is the third state collapsing into the first
            // (L98), and one that said only "something went wrong" would send Dan
            // looking without naming where to look (L11).
            phase = .refused("Ovation could not start: \(detail) (\(step.rawValue))")
        }
        self.step = nil
    }
}
