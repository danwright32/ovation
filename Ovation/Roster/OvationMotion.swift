// The one place Ovation's motion lives: how long a transition runs, the curve it
// runs on, and what happens for somebody who has asked their Mac to reduce
// motion.
//
// ovation#124. The invoice screen settled Ovation's first animation and nothing
// recorded how movement works, so the next screen would have copied it by eye or
// invented its own. A wrong duration is FELT rather than seen, so it gets argued
// about instead of measured, which is why the numbers live in one place with the
// file that draws them cited beside each one.
//
// IT IS A COMPONENT RATHER THAN A RULE, and that is the whole point (L27, L621).
// A rule saying "honour reduce motion" is followed by whoever read it, and reduce
// motion is exactly the kind nobody notices being skipped: the person who needs
// it is not the person building the screen, and no test they run will fail. So a
// screen cannot write a transition at all without coming through here, and
// `scripts/check-motion-owner.sh` refuses an animation written anywhere else
// under `Ovation/`.
//
// EVERY NUMBER IS QUOTED, NEVER CHOSEN HERE. `docs/design/invoice.html:852`
// draws the slide and `:643` draws the fade; the design record's Motion section
// says what each is for and which direction each layer travels. Changing one
// means changing the design file and the record, and
// `OvationTests/OvationMotionTests.swift` reads that file and refuses a
// component that has drifted from it (L638).
//
// NOT A MOTION SYSTEM, AND MUST NOT GROW INTO ONE BY ACCIDENT, the same standing
// as `OvationPalette` beside it. Two durations and one curve are what the design
// has settled. A third duration is a design decision and belongs in a round, not
// in a constant added here to make one screen feel right.
import SwiftUI

enum OvationMotion {

    /// The transitions the design has settled, and nothing else. `CaseIterable`
    /// because the tests enumerate the kinds from here rather than restating
    /// them, so a kind added to this list is covered without anybody having to
    /// remember (L96, L217).
    enum Kind: CaseIterable {
        /// Something that displaces its neighbour. The invoice list standing
        /// aside as the invoice arrives, and the audit history pane pushing the
        /// invoice across (PRD 51d).
        case slide
        /// Something that arrives in place. The tip naming what a refused Send
        /// is waiting on.
        case fade
    }

    /// `docs/design/invoice.html:852`, `transition: width 280ms`.
    static let slideMilliseconds = 280

    /// `docs/design/invoice.html:643`, `transition: opacity 120ms linear`.
    static let fadeMilliseconds = 120

    /// `cubic-bezier(.32,.72,0,1)`, the same line. It is the only easing written
    /// anywhere in the repository: the list to invoice arrival is recorded as
    /// using "the same easing", and nothing draws that arrival, so this is what
    /// the claim resolves to.
    static let slideCurve = (x1: 0.32, y1: 0.72, x2: 0.0, y2: 1.0)

    /// How long a kind runs, in the milliseconds the design record is written in.
    static func milliseconds(_ kind: Kind) -> Int {
        switch kind {
        case .slide: slideMilliseconds
        case .fade: fadeMilliseconds
        }
    }

    /// The animation for a kind, or NOTHING when motion is reduced.
    ///
    /// NOT A SHORTER ANIMATION. The design file's own
    /// `prefers-reduced-motion: reduce` rules remove the transition outright
    /// (`docs/design/invoice.html:855` and `:647`), and a fast slide is still a
    /// slide to somebody it makes ill. `nil` is what SwiftUI's own animation
    /// modifiers take to mean no animation, so nothing downstream has to branch.
    static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        switch kind {
        case .slide:
            return .timingCurve(slideCurve.x1, slideCurve.y1, slideCurve.x2, slideCurve.y2,
                                duration: seconds(slideMilliseconds))
        case .fade:
            return .linear(duration: seconds(fadeMilliseconds))
        }
    }

    /// SwiftUI counts in seconds and the design record counts in milliseconds, so
    /// the conversion happens once, here.
    ///
    /// `TimeInterval` IS NOT THE MONEY RULE BEING EVADED BY SPELLING. Ovation's
    /// money is `Int64` minor units and `scripts/check-forbidden-constructs.sh`
    /// refuses floating point on any path that could reach it. A duration is not
    /// money and never reaches one: it is the type SwiftUI's own animation API
    /// takes, and there is no integer form of it, the same standing the palette's
    /// colour channels have.
    private static func seconds(_ milliseconds: Int) -> TimeInterval {
        TimeInterval(milliseconds) / 1000
    }
}

// MARK: the two ways a screen asks for motion

extension View {
    /// A change that FOLLOWS A VALUE: the declarative half.
    ///
    ///     .ovationMotion(.slide, value: shell.showingHistory)
    ///
    /// The reduce motion answer is read inside, from the environment, so a call
    /// site cannot forget it and cannot get it wrong.
    func ovationMotion(_ kind: OvationMotion.Kind, value: some Equatable) -> some View {
        modifier(OvationMotionModifier(kind: kind, value: value))
    }
}

private struct OvationMotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: OvationMotion.Kind
    let value: Value

    func body(content: Content) -> some View {
        content.animation(OvationMotion.animation(kind, reduceMotion: reduceMotion), value: value)
    }
}

/// A change an ACTION makes: the imperative half, for a press rather than a value
/// a view is watching.
///
///     @Environment(\.ovationMotion) private var motion
///     ...
///     motion.run(.slide) { shell.showingHistory = true }
///
/// It exists so that `withAnimation` never has to be written on a screen. A guard
/// may refuse only what the product can do another way, or it is a refusal with
/// no remedy (L54, L109).
struct OvationMotionReader {
    let reduceMotion: Bool

    @MainActor
    func run<Result>(_ kind: OvationMotion.Kind, _ change: () -> Result) -> Result {
        withAnimation(OvationMotion.animation(kind, reduceMotion: reduceMotion), change)
    }
}

extension EnvironmentValues {
    /// Derived from the system's own answer on every read rather than stored, so
    /// nothing can hold a stale copy of a setting the person can change while the
    /// app is open (L175).
    var ovationMotion: OvationMotionReader {
        OvationMotionReader(reduceMotion: accessibilityReduceMotion)
    }
}
