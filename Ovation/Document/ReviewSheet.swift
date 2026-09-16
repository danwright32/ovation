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
    /// What closing the sheet does. The sheet does not own its own presentation:
    /// it belongs to the window, so the window closes it (PRD 52a).
    var close: () -> Void

    @State private var page = InvoicePage()
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
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
            HStack(alignment: .top, spacing: 0) {
                stage
                Divider()
                rail
            }
        }
        .frame(width: 800, height: 560)
        .onAppear(perform: showPage)
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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: the document

    /// The way to open the page sits ABOVE it, because the page is taller than the
    /// sheet's visible area and anything beneath it is below the fold (PRD 52b).
    private var stage: some View {
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
            } else {
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

    private var rail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Going to")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.none)

            if let nowhere = presenter.noRecipientsSentence {
                Text(nowhere).font(.system(size: 13))
            } else {
                ForEach(presenter.recipients, id: \.self) { address in
                    Text(address).font(.system(size: 13))
                }
                // SAID ONCE FOR THE GROUP, never once per address: the same
                // sentence printed twice is what PRD 52c rules out.
                if let passedOver = presenter.passedOver {
                    Text("not \(passedOver), who booked it")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
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
