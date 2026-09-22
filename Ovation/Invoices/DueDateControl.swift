// ovation#473, PRD 5.7. When this invoice is due, as a control rather than a
// figure.
//
// THE DESIGN RECORD DRAWS IT AND THE APP PRINTED IT. `docs/design/invoice.html`
// gives the foot "Dated 29 Aug 2026, due " followed by a button that opens a list
// of four terms, each with the day it lands on beside it, and an "Another date..."
// entry that opens a panel. Ovation drew the due date as text, so the one thing
// PRD 5.7 says is overridable per invoice could not be overridden.
//
// THE LIST HANGS UPWARD, which is the design record's own `.poplist.up`: it is
// opened from the foot of the screen and there is no room below it.
//
// THE THREE DOTS SAY A QUESTION IS COMING, which is the macOS convention and is
// true here: that entry opens a panel rather than doing anything.
//
// IT IS NOT OFFERED AT ALL ON AN INVOICE THAT MAY NOT BE EDITED, rather than
// offered and then refused, because a control that opens onto a refusal is a dead
// control (L651, L109). `InvoiceDueDateWriter` refuses the same states, because a
// screen gating a write is not the write being guarded (L196).
import SwiftUI

struct DueDateControl: View {

    /// The date the invoice was written, rendered, or empty where it has none.
    let issued: String
    let due: String
    let choices: [InvoiceScreenPresenter.DueChoice]
    /// What saving a date does, or nil where this invoice may not be edited.
    var save: ((BusinessDate) -> Void)?
    /// Why the last save did not happen, said rather than swallowed.
    var refused: String?

    @State private var listIsOpen = false
    @State private var panelIsOpen = false
    @State private var typed = ""
    @State private var badlyTyped = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(issuedAndDue)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(OvationPalette.soft)
            // THE PRODUCT'S ONE WORD THAT IS A CONTROL (ovation#450), rather
            // than a second copy of the treatment. `check-one-action-word.sh`
            // refuses an underline written anywhere else, which is what caught
            // this one being hand rolled.
            ActionWord(word: due.isEmpty ? "Set a date" : due, size: 12.5,
                       press: canBeChanged ? { listIsOpen.toggle() } : nil,
                       notYet: whyNot)
        }
        .popover(isPresented: $listIsOpen, arrowEdge: .top) { termList }
        .sheet(isPresented: $panelIsOpen) { anotherDate }
    }

    /// Whether the date can be changed at all.
    ///
    /// TWO CONDITIONS READ ONCE, so whether the word is a control and what it
    /// says when it is not come from one answer rather than two that can
    /// disagree (L70).
    private var canBeChanged: Bool { save != nil && !choices.isEmpty }

    /// Why it cannot, in a sentence rather than a silence.
    private var whyNot: String? {
        if save == nil { return "this invoice has been sent" }
        if choices.isEmpty { return "the invoice has no date to count a term from" }
        return nil
    }

    /// "Dated 12 Nov 2026, due " with the control after it.
    private var issuedAndDue: String {
        issued.isEmpty ? "Due " : "Dated \(issued), due "
    }

    // MARK: the list of terms

    /// THE DAY EACH TERM LANDS ON IS BESIDE IT, which the design record shows
    /// rather than leaving the reader to count fourteen days in their head.
    private var termList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(choices) { choice in
                Button {
                    listIsOpen = false
                    save?(choice.day)
                } label: {
                    HStack(spacing: 18) {
                        Text(choice.says)
                        Spacer(minLength: 12)
                        Text(choice.lands)
                            .foregroundStyle(OvationPalette.faint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(OvationPalette.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .accessibilityLabel("\(choice.says), \(choice.lands)")
                .accessibilityAddTraits(choice.isCurrent ? [.isButton, .isSelected] : [.isButton])
            }
            Divider().overlay(OvationPalette.rule).padding(.vertical, 4)
            Button("Another date...") {
                listIsOpen = false
                typed = due
                badlyTyped = false
                panelIsOpen = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(OvationPalette.ink)
            .padding(.horizontal, 16)
            .padding(.bottom, 5)
        }
        .padding(.vertical, 5)
        .frame(minWidth: 186, alignment: .leading)
        .background(OvationPalette.chrome)
        // PRD 43, ovation#474. A popover is its OWN window, so it does not
        // inherit the screen's appearance and `AppearanceParityTests` cannot
        // capture it: it has to set its own, and this is the one place that
        // being true is not proved by that suite.
        .ovationAppearance()
    }

    // MARK: another date

    /// A DATE TYPED IS READ OR REFUSED BY NAME, never quietly rounded to
    /// something near it. The refusal shows the shape rather than describing a
    /// format, in the vocabulary of what is already on screen (L399, L50).
    private var anotherDate: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("When this invoice is due")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OvationPalette.ink)
            Text("Due")
                .font(.system(size: 12))
                .foregroundStyle(OvationPalette.quiet)
            TextField("", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .frame(width: 220)
                .onSubmit(commit)
                .accessibilityLabel("Due date")
            if badlyTyped {
                // THE EXAMPLE IS THIS INVOICE'S OWN DATE, which is already on
                // screen beside the field, rather than a date from nowhere.
                Text(PaymentTerms.refusalSentence(showing: choices[0].day))
                    .font(.system(size: 12))
                    .foregroundStyle(OvationPalette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 260, alignment: .leading)
            }
            if let refused {
                Text(refused)
                    .font(.system(size: 12))
                    .foregroundStyle(OvationPalette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 260, alignment: .leading)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("Cancel") { panelIsOpen = false }
                Button("Save", action: commit)
                    .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 13))
        }
        .padding(20)
        .frame(minWidth: 300, alignment: .leading)
        .background(OvationPalette.background)
        // A sheet is its own window too. Same reason as the list above.
        .ovationAppearance()
    }

    /// Reads what was typed, or says it could not.
    ///
    /// THE PANEL STAYS OPEN ON A REFUSAL, because closing it would throw away
    /// what was typed and leave nothing saying why (L628).
    private func commit() {
        guard let read = PaymentTerms.read(typed) else {
            badlyTyped = true
            return
        }
        badlyTyped = false
        panelIsOpen = false
        save?(read)
    }
}
