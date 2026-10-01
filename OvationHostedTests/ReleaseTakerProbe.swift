// Who takes a click's release, measured rather than guessed. Review of #644.
//
// On the CI runner, where the test app is the active one, the Clients screen's
// names answered no click: 234 of 250 releases were taken by something other than
// `RealClick` (runs 36884439109 and 36903510802), and changing how the click is
// dispatched changed nothing. This records the call stack of every dequeue of a
// left mouse release while it is installed, so a failing case can say WHICH code
// took it instead of a fix being guessed at (L681).
//
// INSTALLED FOR ONE CASE AND REMOVED AFTER IT. It replaces the implementation of
// `NSApplication.nextEvent(matching:until:inMode:dequeue:)` and puts the original
// back in `remove()`, so nothing outside the case that installs it is changed.
import AppKit
import ObjectiveC
@testable import Ovation

@MainActor
final class ReleaseTakerProbe {
    /// The call stacks of the dequeues that took a release, oldest first.
    private(set) var stacks: [[String]] = []
    private let method: Method
    private let original: IMP
    private typealias Next = @convention(c) (AnyObject, Selector, UInt64, NSDate?, NSString, Bool) -> NSEvent?

    init() {
        let selector = #selector(NSApplication.nextEvent(matching:until:inMode:dequeue:))
        guard let method = class_getInstanceMethod(NSApplication.self, selector) else {
            preconditionFailure("NSApplication has no nextEvent(matching:until:inMode:dequeue:) to measure")
        }
        self.method = method
        original = method_getImplementation(method)
        let call = unsafeBitCast(original, to: Next.self)
        let record: @convention(block) (AnyObject, UInt64, NSDate?, NSString, Bool) -> NSEvent? = {
            [weak self] app, mask, date, mode, dequeue in
            let event = call(app, selector, mask, date, mode, dequeue)
            if dequeue, event?.type == .leftMouseUp {
                let stack = Thread.callStackSymbols
                MainActor.assumeIsolated { self?.stacks.append(stack) }
            }
            return event
        }
        method_setImplementation(method, imp_implementationWithBlock(record))
    }

    func remove() {
        method_setImplementation(method, original)
    }

    /// The first stack that was not `RealClick` taking its own release, cut to
    /// its readable frames: the code that took the release out from under it.
    var firstTaker: String {
        let others = stacks.filter { stack in
            !stack.dropFirst(2).prefix(1).contains { $0.contains("RealClick") }
        }
        guard let stack = others.first else { return "none recorded" }
        return stack.dropFirst(2).prefix(24).map { frame in
            // "3   AppKit   0x...   -[NSWindow trackEvents...] + 12" keeps module and symbol.
            let parts = frame.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count > 3 else { return frame }
            return String(parts[1]) + " " + parts[3...].joined(separator: " ")
        }.joined(separator: " < ")
    }
}
