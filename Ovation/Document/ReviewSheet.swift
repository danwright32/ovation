import PDFKit
import SwiftUI

/// The review sheet (ovation#318, PRD 52 to 52c), drawn from the settled record at
/// `docs/design/review-send.html`.
///
/// IT DECIDES NOTHING. Every sentence and every state comes from
/// `ReviewSheetPresenter`, for the reason RootView gives: a decision made inside a
/// view body can only be checked by rendering it.
///
/// THE PAGE IS THE RENDER, SCALED. `InvoicePage` is handed the bytes the send will
/// attach and shows them; it never draws the invoice itself, which is what makes
/// the preview the attachment rather than a second opinion about it (PRD 10c).
struct ReviewSheet: View {

    @Bindable var presenter: ReviewSheetPresenter
    /// The review of a REAL invoice, which can be sent (ovation#42), or nil for the
    /// Debug samples and the pictures, which show the page and the recipients only.
    var review: InvoiceReview?
    /// What closing the sheet does. The sheet does not own its own presentation:
    /// it belongs to the window, so the window closes it (PRD 52a).
    var close: () -> Void

    /// The page view's model, INJECTABLE rather than constructed here, so a caller
    /// that needs the page already drawn (the capture that puts pictures in front of
    /// Dan) can hand one in. A view that builds its own dependency is beyond every
    /// refusal that dependency could offer (L196).
    @State private var page: InvoicePage
    @State private var failure: String?

    init(presenter: ReviewSheetPresenter, review: InvoiceReview? = nil,
         page: InvoicePage = InvoicePage(), close: @escaping () -> Void) {
        self.presenter = presenter
        self.review = review
        self._page = State(initialValue: page)
        self.close = close
    }

    /// THE SHEET'S OWN SIZE, named so a test can hold it to what it has to show
    /// (ovation#393).
    static let size = CGSize(width: 800, height: 560)

    /// HOW TALL IT IS IN THE SMALLEST WINDOW, which is the height its fixed part has to
    /// fit (ovation#393). It floats clear of the title bar and the window's foot by the
    /// floating sheet's margin (ovation#547), so at the minimum window it gives up
    /// height rather than touch either edge.
    static var smallestHeight: CGFloat {
        min(size.height, OvationWindow.minimumHeight - ShellView.titleBarHeight - 2 * FloatingSheet.margin)
    }

    var body: some View {
        laidOut(withLists: true)
            // 560 TALL WHERE THE WINDOW HAS ROOM, AND LESS WHERE IT HAS NOT (ovation#547).
            // It floats with room above and below it, and at the smallest window that
            // room is 582 points less the margins, so it gives up height rather than
            // touch the title bar; the page above scrolls, so nothing is lost.
            .frame(width: Self.size.width)
            .frame(maxHeight: Self.size.height)
            .ovationAppearance()
            .onAppear(perform: showPage)
    }

    /// THE SHEET WITH ITS TWO LISTS LEFT OUT, the page and the recipients, which is what
    /// has to fit its size (Dan, 2026-09-30). The page already scrolls in its own box,
    /// and the recipients do once there are more than fit, so neither counts against
    /// the sheet's height. No frame, because a fixed frame answers with its own height.
    var fixedPart: some View { laidOut(withLists: false) }

    private func laidOut(withLists: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            // A SEND THAT WILL NOT REACH THE CLIENT is said first and loudest, in the one
            // treatment used for nothing else (L623), before anything can be pressed.
            if let redirected = review?.destinationWarning {
                Text(redirected)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(OvationPalette.onRedirectBand)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OvationPalette.redirectBand)
                    .accessibilityAddTraits(.isStaticText)
            }
            // A WARNING IS A BAND ACROSS THE SHEET, UNDER THE TITLE (PRD 52e), and
            // this one carries no control: nothing can answer it except changing the
            // date, which is not done from here.
            if let due = presenter.dueDateWarning {
                Text(due)
                    .font(.system(size: 12))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.14))
                    .accessibilityAddTraits(.isStaticText)
                Divider()
            }
            // ON SEND THE SHEET BECOMES THE OUTCOME (the design record's sending
            // states): the document and the recipients are replaced, so nothing is
            // left to read and nothing to press by mistake.
            if let review, review.state != .ready {
                ReviewOutcome(review: review, close: close)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    stage(withPage: withLists)
                    Divider()
                    rail(withRecipients: withLists)
                }
            }
        }
    }

    // MARK: the head

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("Review and send")
                .font(.system(size: 22, weight: .regular, design: .serif))
            Text(presenter.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Close", action: close)
                .disabled(review?.state.holdsTheSheetOpen == true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: the document

    /// The way to open the page sits ABOVE it, because the page is taller than the
    /// sheet's visible area and anything beneath it is below the fold (PRD 52b).
    private func stage(withPage: Bool) -> some View {
        VStack(alignment: .center, spacing: 10) {
            Button(openLabel, action: togglePage)
                .buttonStyle(.link)
                .font(.system(size: 12))

            if let failure {
                Text(failure)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else if withPage {
                ScrollView {
                    InvoicePageView(page: page)
                        .frame(width: presenter.pageWidth, height: presenter.pageWidth * 1.294)
                        .accessibilityLabel("The invoice that ships, as it will be sent")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .frame(width: 402)
    }

    private var openLabel: String {
        presenter.scale == .fitted
            ? "Press the page to read it at full size"
            : "Press the page to read it at the size it fits"
    }

    // MARK: who it goes to

    private func rail(withRecipients: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Going to")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.none)

            if let nowhere = presenter.noRecipientsSentence, review?.destinationWarning == nil {
                Text(nowhere).font(.system(size: 13))
            } else {
                // WHERE IT ACTUALLY GOES (L64): the test address when sends are
                // redirected, never the client it will not reach. In a box of its own
                // that scrolls once long, since a client can carry any number of
                // addresses (ovation#393).
                if withRecipients {
                    ScrollsWhenLong {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(review?.goingTo ?? presenter.recipients, id: \.self) { address in
                                Text(address).font(.system(size: 13))
                            }
                        }
                    }
                }
                // SAID ONCE FOR THE GROUP, never once per address: the same
                // sentence printed twice is what PRD 52c rules out. Not said of a
                // redirected send, whose recipient is nobody who booked anything.
                if let passedOver = presenter.passedOver, review?.destinationWarning == nil {
                    Text("not \(passedOver), who booked it")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            if let review {
                ReviewMessage(review: review)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: doing

    private func showPage() {
        do {
            try presenter.show(on: page)
            failure = nil
        } catch {
            // A RENDER THAT FAILED IS ITS OWN STATE, never an empty page area: an
            // empty rectangle reads as a document that is still coming (L10).
            failure = "This invoice could not be drawn, so there is nothing to review yet."
        }
    }

    private func togglePage() {
        do {
            if presenter.scale == .fitted {
                try presenter.open(on: page)
            } else {
                try presenter.close(on: page)
            }
            failure = nil
        } catch {
            failure = "This invoice could not be drawn, so there is nothing to review yet."
        }
    }
}

/// What the sheet hands the render to. It holds bytes and a scale and nothing else,
/// so the view above it can be driven by a test without a window (L52).
@MainActor
@Observable
final class InvoicePage: InvoicePageSink {
    private(set) var bytes: Data?
    private(set) var scale: InvoicePageScale = .fitted

    func display(_ bytes: Data, at scale: InvoicePageScale) {
        self.bytes = bytes
        self.scale = scale
    }
}

/// PDFKit shows the page. It is handed the bytes and a scale and reads neither the
/// invoice nor the store.
private struct InvoicePageView: NSViewRepresentable {
    let page: InvoicePage

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = false
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if let bytes = page.bytes, view.document?.dataRepresentation() != bytes {
            view.document = PDFDocument(data: bytes)
        }
        view.scaleFactor = page.scale.factor
    }
}
