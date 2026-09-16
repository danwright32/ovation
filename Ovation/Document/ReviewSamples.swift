#if DEBUG
import SwiftUI

/// The states the review sheet is looked at in, in the Debug build only
/// (ovation#318 B5).
///
/// WHY A LIST RATHER THAN ONE SAMPLE. The states worth judging are the ones the
/// real data does not have: not one of the 31 real clients carries a genuine
/// override, and nothing in the store is past its due date on purpose. A screen
/// that can only be seen in its ordinary state has had its other states reviewed
/// by nobody (L606, L546).
enum ReviewSample: String, CaseIterable, Identifiable {
    case ordinary
    case genuineOverride
    case twoAddressesInOneField
    case nowhereToSend
    case pastDue
    case dueSoon
    case waitingOnTaxStatus
    case discountTooLarge

    var id: String { rawValue }

    /// What the menu says. Written here rather than derived from the case name,
    /// because a name is for code and this is read by a person (L399).
    var says: String {
        switch self {
        case .ordinary: return "Ordinary"
        case .genuineOverride: return "A genuine override"
        case .twoAddressesInOneField: return "Two addresses in one field"
        case .nowhereToSend: return "Nowhere to send"
        case .pastDue: return "Past its due date"
        case .dueSoon: return "Due in three days"
        case .waitingOnTaxStatus: return "Waiting on the tax status"
        case .discountTooLarge: return "A discount larger than the invoice"
        }
    }

    /// Whether Review would open at all for this sample, and the sentence it says
    /// when it would not. The samples that refuse are how that state is looked at,
    /// since the sheet deliberately never opens over them (PRD 52g).
    var refusalSentence: String? {
        switch self {
        case .waitingOnTaxStatus: return ReviewGate.sentence(for: .taxStatusNeverRecorded)
        case .discountTooLarge: return ReviewGate.sentence(for: .discountExceedsSubtotal)
        default: return nil
        }
    }
}

/// What the Debug menu presses and the window shows. It holds which sample is on
/// screen and nothing else.
@MainActor
@Observable
final class ReviewSamplesCommand {
    static let title = "Review sheet samples"

    var showing: ReviewSample?
    /// Why the sheet did not open, when the sample is one that refuses. Said rather
    /// than left as nothing happening, because a press that does nothing is
    /// indistinguishable from a broken menu (L109).
    var refused: String?

    func press(_ sample: ReviewSample) {
        if let sentence = sample.refusalSentence {
            refused = sentence
            showing = nil
        } else {
            refused = nil
            showing = sample
        }
    }

    func close() {
        showing = nil
        refused = nil
    }
}

/// Presenting the sheet from the WINDOW's content (PRD 52a), and saying so when a
/// sample refuses instead.
extension View {
    func reviewSamples(_ command: ReviewSamplesCommand) -> some View {
        modifier(ReviewSamplesPresentation(command: command))
    }
}

private struct ReviewSamplesPresentation: ViewModifier {
    @Bindable var command: ReviewSamplesCommand

    func body(content: Content) -> some View {
        content
            .sheet(item: $command.showing) { sample in
                sheet(for: sample)
            }
            .alert("Review is not offered for this one",
                   isPresented: Binding(get: { command.refused != nil },
                                        set: { if !$0 { command.close() } })) {
                Button("All right") { command.close() }
            } message: {
                Text(command.refused ?? "")
            }
    }

    @ViewBuilder
    private func sheet(for sample: ReviewSample) -> some View {
        // A SAMPLE THAT CANNOT BE BUILT SAYS SO. It is Debug only, and a blank
        // sheet would read as a sheet still loading (L10).
        if let presenter = try? ReviewSampleWorld.presenter(for: sample) {
            ReviewSheet(presenter: presenter, close: { command.close() })
        } else {
            VStack(spacing: 12) {
                Text("This sample could not be built, so there is nothing to show.")
                Button("Close") { command.close() }
            }
            .padding(24)
            .frame(width: 420)
        }
    }
}
#endif
