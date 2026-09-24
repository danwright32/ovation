// ovation#42. The half of the review sheet that sends: the subject, the message, the
// Send, and what the sheet becomes once Send is pressed.
//
// DRAWN FROM THE SETTLED RECORD, `docs/design/review-send.html`: the subject is
// "Invoice N, shoot", the message is editable in place and an empty one greys Send with
// the one sentence it is waiting on (Dan, 2026-09-09), and on Send the sheet BECOMES the
// outcome. Working, sent and not sent are visibly different, and working counts the
// seconds so it can never look stalled (PRD 33). There is no spinner anywhere.
//
// IT DECIDES NOTHING. Every sentence comes from `InvoiceReview` and the sender behind it.
import SwiftUI

struct ReviewMessage: View {
    @Bindable var review: InvoiceReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Subject")
            Text(review.subject).font(.system(size: 13))

            label("Message")
            // THE DESIGN SYSTEM'S OWN EDITING CONTROL, the same bordered box the
            // Settings pane uses, never the platform's bare default (L607).
            TextEditor(text: $review.message)
                .font(.system(size: 13))
                .frame(minHeight: 110)
                .padding(6)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 6).fill(OvationPalette.background))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(OvationPalette.rule))
                .accessibilityLabel("Message")

            if let waiting = review.whySendIsWaiting {
                Text(waiting)
                    .font(.system(size: 12))
                    .foregroundStyle(OvationPalette.soft)
            }

            HStack {
                Spacer()
                // GREYED, NEVER ABSENT, with its reason beside it above (L109).
                Button("Send") { Task { await review.send() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(review.whySendIsWaiting != nil)
            }
        }
        .padding(.top, 12)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

/// What the sheet becomes once Send is pressed.
struct ReviewOutcome: View {
    let review: InvoiceReview
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch review.state {
            case .ready:
                EmptyView()
            case .working(let since):
                big("Sending")
                // THE SECONDS COUNT, so a send in progress can never be mistaken for one
                // that stalled (PRD 33).
                TimelineView(.periodic(from: since, by: 1)) { context in
                    let seconds = max(0, Int(context.date.timeIntervalSince(since)))
                    Text("Sending through Gmail, \(seconds)s")
                        .font(.system(size: 13))
                        .foregroundStyle(OvationPalette.soft)
                }
            case .sent(let at, let to):
                big("Sent")
                Text(InvoiceMail.sentLine(time: at.formatted(date: .omitted, time: .shortened),
                                          to: to, number: review.number))
                    .font(.system(size: 13))
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            case .refused(let sentence):
                big("Not sent")
                Text(sentence).font(.system(size: 13))
                HStack(spacing: 12) {
                    Button("Try again") { review.tryAgain() }
                        .keyboardShortcut(.defaultAction)
                    Button("Close", action: close)
                }
            case .couldNotTell(let sentence):
                big("Could not tell whether it went")
                Text(sentence).font(.system(size: 13))
                Button("Close", action: close)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func big(_ text: String) -> some View {
        Text(text).font(.system(size: 22, weight: .regular, design: .serif))
            .foregroundStyle(OvationPalette.ink)
    }
}
