// ovation#510, PRD 51m, 48a and 48b. Recording a payment on a sent invoice.
//
// IT FLOATS, CENTRED, OVER A DIMMED WINDOW, every corner rounded, and is drawn
// here rather than presented as a system sheet, because a macOS sheet hangs from
// the title bar with its top corners flat, which is the one thing Dan's rule for
// every sheet refuses (48a, rounds 1 and 1b).
//
// THE AMOUNT AND THE DATE ARE ONE WIDTH, ONE HEIGHT AND RIGHT ALIGNED (48b).
//
// A CLICK OUTSIDE OR ESCAPE CLOSES IT ONLY WHEN NOTHING WAS CHANGED, and
// otherwise asks (Dan, 2026-09-25). Cancel is a decision and closes at once.
//
// ITS RULES ARE `PaymentForm`'s. This draws the form and hands edits to it,
// because a view tree test cannot type into a field and read back what a view's
// own state made of it (L442).
import SwiftUI

struct PaymentSheet: View {

    let number: String
    let starts: InvoiceScreenPresenter.PaymentStart
    /// Why the last press was not recorded, in the recorder's own words (L109).
    let refused: String?
    /// Whether a press is being recorded now, so the sheet says it started and
    /// cannot be pressed twice while it is (L608).
    let isRecording: Bool
    let record: (PaymentEntry) -> Void
    let close: () -> Void
    /// Told whenever the form changes. A refusal answers the press it came from,
    /// so once the form is edited the host clears it and the sheet says what is
    /// true of the form now instead (L680).
    let edited: () -> Void

    @State private var form: PaymentForm
    @State private var asking = false
    /// ONE PRESS FOR THE LIFE OF THE SHEET, so a retry after a refusal or a
    /// press that arrives twice is the same payment rather than a second one.
    @State private var press = UUID()
    /// ViewInspector's way into the hosted sheet, the same hook ShellView carries,
    /// so a test can type into a field and see what the sheet did with it (L442).
    let inspection = Inspection<Self>()

    /// One width for both boxes, the design's 108px (48b).
    private static let boxWidth: CGFloat = 108

    init(number: String, starts: InvoiceScreenPresenter.PaymentStart, refused: String?,
         isRecording: Bool, record: @escaping (PaymentEntry) -> Void,
         close: @escaping () -> Void, edited: @escaping () -> Void = {}) {
        self.number = number
        self.starts = starts
        self.refused = refused
        self.isRecording = isRecording
        self.record = record
        self.close = close
        self.edited = edited
        _form = State(initialValue: PaymentForm(starting: starts))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .contentShape(Rectangle())
                .onTapGesture(perform: closeIncidentally)
                .accessibilityHidden(true)
            card
        }
        .onExitCommand(perform: closeIncidentally)
        .onChange(of: form) { edited() }
        .onReceive(inspection.notice) { inspection.visit(self, $0) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Record a payment on invoice \(number)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OvationPalette.ink)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    label("Amount")
                    box($form.amount, named: "Amount")
                }
                GridRow {
                    label("Received")
                    box($form.received, named: "Received")
                }
                GridRow {
                    label("By")
                    HStack(spacing: 4) {
                        ForEach(PaymentMethod.allCases, id: \.self) { method($0) }
                    }
                }
            }
            if asking { askBeforeClosing } else { foot }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 360, alignment: .leading)
        .background(OvationPalette.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.28), radius: 17, y: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Record a payment on invoice \(number)")
    }

    private func label(_ words: String) -> some View {
        Text(words)
            .font(.system(size: 12))
            .foregroundStyle(OvationPalette.quiet)
    }

    private func box(_ text: Binding<String>, named name: String) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 6)
            .frame(width: Self.boxWidth, height: 26)
            .background(RoundedRectangle(cornerRadius: 4).fill(OvationPalette.sunk))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(OvationPalette.rule, lineWidth: 1))
            .accessibilityLabel(name)
            .onSubmit(pressRecord)
    }

    /// One of the four, drawn the way the discount's unit is (DiscountLine), so the
    /// screen has one look for a choice between words.
    private func method(_ method: PaymentMethod) -> some View {
        let chosen = form.method == method
        return Button { form.method = method } label: {
            Text(method.exportLabel)
                .font(.system(size: 12))
                .foregroundStyle(chosen ? OvationPalette.background : OvationPalette.quiet)
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(chosen ? OvationPalette.accent : OvationPalette.chrome)
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(chosen ? OvationPalette.accent : OvationPalette.rule,
                                    lineWidth: 1))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : [.isButton])
        .accessibilityValue(chosen ? "chosen" : "not chosen")
    }

    private var foot: some View {
        HStack(spacing: 16) {
            if isRecording {
                Text("Recording")
                    .font(.system(size: 12))
                    .foregroundStyle(OvationPalette.quiet)
            } else if let why = refused ?? form.whyNot {
                Text(why)
                    .font(.system(size: 12))
                    .foregroundStyle(OvationPalette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Cancel", action: close)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(OvationPalette.quiet)
            Button("Record", action: pressRecord)
                .buttonStyle(.plain)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(mayRecord ? OvationPalette.accent : OvationPalette.faint)
                .disabled(!mayRecord)
        }
        .padding(.top, 4)
    }

    private var askBeforeClosing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Close without recording this payment?")
                .font(.system(size: 13))
                .foregroundStyle(OvationPalette.ink)
            HStack(spacing: 16) {
                Spacer(minLength: 0)
                Button("Keep editing") { asking = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(OvationPalette.quiet)
                Button("Close", action: close)
                    .buttonStyle(.plain)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(OvationPalette.accent)
            }
        }
        .padding(.top, 4)
    }

    private var mayRecord: Bool { !isRecording && form.whyNot == nil }

    /// Not while asking whether to close: an Enter then is not a decision to record.
    private func pressRecord() {
        guard !asking, mayRecord, let entry = form.entry(press: press) else { return }
        record(entry)
    }

    private func closeIncidentally() {
        guard !isRecording else { return }
        if form.changed { asking = true } else { close() }
    }
}
