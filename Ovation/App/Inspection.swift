// ovation#485. A way for a hosted test to read a view WHILE IT IS ON SCREEN, which is
// the only way to read or drive its `@State`.
//
// WHY A VIEW NEEDS THIS AT ALL. A test inspecting a view value it built evaluates
// that value's body with state that was never installed, so anything the view keeps
// in `@State` reads as its initial value for ever, and a press that sets it changes
// nothing (SwiftUI says so in the log: "Accessing State's value outside of being
// installed on a View"). ShellView keeps the invoice that is open in `@State`, so
// without this nothing can reach the screen it builds for that invoice, and whether
// the app's writes reach that screen was unprovable (ovation#485, L718).
//
// IT DOES NOTHING IN THE APP. `notice` is sent only by ViewInspector's
// `inspect(after:)`, from a test, so in the shipping app the subscription below
// never fires and the view draws exactly what it drew before. This is ViewInspector's
// own documented pattern; the conformance that lets a test call `inspect` on it is
// declared in the hosted test target, so the app carries no test dependency.
import Combine

@MainActor
final class Inspection<V> {
    let notice = PassthroughSubject<UInt, Never>()
    var callbacks: [UInt: (V) -> Void] = [:]

    /// Hands the view as it is ON SCREEN to the test waiting on `line`, once.
    func visit(_ view: V, _ line: UInt) {
        if let callback = callbacks.removeValue(forKey: line) {
            callback(view)
        }
    }
}
