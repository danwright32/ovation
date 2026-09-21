// ovation#457, PRD 4, 4a, 5, 7, 8, 51a to 51l. The invoice, drawn.
//
// TRANSLATED FROM `docs/design/invoice.html`, NOT COPIED, on the same terms as
// `InvoiceListView` and `RosterPassView`: an action is a word rather than a
// button, the window chrome is the system's, and the type is the system's. That
// file is nine rounds settled with Dan, and the geometry below is its own.
//
// IT DECIDES NOTHING. Every string comes from `InvoiceScreenPresenter`. A
// decision made inside a view body can only be checked by rendering it, and the
// states that matter here are the ones no ordinary fixture produces.
//
// IT HOLDS NO CONTEXT AND WRITES NOTHING, which is PRD 51l and ovation#440.
// `scripts/check-forbidden-constructs.sh` refuses a view that holds a
// `ModelContext` or calls `save`, and this screen is the one that rule was
// written ahead of.
//
// THE COLUMNS ARE FIXED RATHER THAN AUTO, which is the design record's own
// reasoning and the same as the list's date column: an auto column is sized per
// row, so the figures stop lining up the moment a second line is added.
//
// WHAT IS NOT HERE YET, and is deliberately not drawn as a control that does
// nothing (L109, ovation#450): adding a line and choosing its type (round A),
// the discount (round 5), the due date terms panel (round 8), the Edit menu's
// rare actions, the history pane (round 7), and recording a payment. Each has
// its own issue and each arrives as a control when it arrives at all. A word
// that looks pressable and is not is the defect this screen must not ship.
import SwiftData
import SwiftUI

struct InvoiceScreenView: View {

    let presenter: InvoiceScreenPresenter

    /// Leaving the invoice. Coming back to a list you recognise is ovation#125,
    /// which owns the scroll position and the row that moved; this is only the
    /// way out.
    let close: () -> Void

    /// Opening the review, or nil where the caller has nowhere for it to go yet.
    /// NIL DRAWS THE WORD QUIET RATHER THAN HIDING IT, so the foot does not change
    /// shape depending on what is wired (L678).
    var review: (() -> Void)?

    /// The design record's own column widths, named once so the header and every
    /// row are laid out by one declaration and cannot drift apart (L553).
    private enum Column {
        static let hours: CGFloat = 66
        static let rate: CGFloat = 92
        static let amount: CGFloat = 96
        static let gap: CGFloat = 14
        static let sideMargin: CGFloat = 24
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    columnHeader
                    ForEach(presenter.lines) { line(for: $0) }
                    money
                }
            }
            Spacer(minLength: 0)
            foot
        }
        .background(OvationPalette.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: the head

    /// THE CLIENT IS THE HEADING AND THE SHOOT SITS UNDER IT, which is the Clients
    /// detail pane's treatment reused rather than a new one invented here.
    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(presenter.client)
                    .font(.system(size: 25, weight: .regular, design: .serif))
                    .foregroundStyle(OvationPalette.ink)
                    .lineLimit(1)
                Text(presenter.shoot)
                    .font(.system(size: 13))
                    .foregroundStyle(OvationPalette.quiet)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Back to the list", action: close)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(OvationPalette.quiet)
        }
        .padding(.horizontal, Column.sideMargin)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Divider().overlay(OvationPalette.rule) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(presenter.client), \(presenter.shoot)")
    }

    // MARK: the lines

    private var columnHeader: some View {
        HStack(spacing: Column.gap) {
            Text(InvoiceScreenPresenter.columns[0]).frame(maxWidth: .infinity, alignment: .leading)
            Text(InvoiceScreenPresenter.columns[1]).frame(width: Column.hours, alignment: .trailing)
            Text(InvoiceScreenPresenter.columns[2]).frame(width: Column.rate, alignment: .trailing)
            Text(InvoiceScreenPresenter.columns[3]).frame(width: Column.amount, alignment: .trailing)
        }
        .font(.system(size: 10.5, weight: .bold))
        .tracking(1.26)
        .textCase(.uppercase)
        .foregroundStyle(OvationPalette.faint)
        .padding(.horizontal, Column.sideMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Divider().overlay(OvationPalette.ruleSoft) }
        .accessibilityHidden(true)
    }

    private func line(for row: InvoiceScreenPresenter.Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Column.gap) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.describes)
                    .font(.system(size: 14.5))
                    .foregroundStyle(OvationPalette.ink)
                    .lineLimit(1)
                if !row.beneath.isEmpty {
                    Text(row.beneath)
                        .font(.system(size: 12.5))
                        .foregroundStyle(OvationPalette.quiet)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            figure(row.hours, width: Column.hours)
            figure(row.rate, width: Column.rate)
            // A WORD WHERE THE AMOUNT WOULD BE (round 3), drawn in the reading
            // face rather than the figures face, because it is not a figure. Never
            // red: an unpriced draft is work waiting, not something gone wrong
            // (PRD 5.45).
            if row.amountIsAWord {
                // IT DOES NOT WRAP, which is the design record's own `white-space:
                // nowrap` on this word. At the amount column's 96px "Needs the end
                // time" breaks over two lines and the row grows taller than every
                // other, so the word takes the width it needs and runs leftward
                // into the space the figures are not using.
                Text(row.amount)
                    .font(.system(size: 12.5))
                    .foregroundStyle(OvationPalette.quiet)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: Column.amount, alignment: .trailing)
            } else {
                figure(row.amount, width: Column.amount)
            }
        }
        .padding(.horizontal, Column.sideMargin)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().overlay(OvationPalette.ruleSoft) }
        // ONE ELEMENT READ AS ONE LINE, in the order the line reads, which is what
        // the list already does for its rows.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spoken(row))
    }

    /// A figure, in tabular monospaced digits so the columns line up down the page.
    private func figure(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 13.5, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(OvationPalette.ink)
            .frame(width: width, alignment: .trailing)
    }

    /// What a screen reader says for one line. A blank column is left out rather
    /// than read as an empty pause, because a flat charge genuinely has no hours
    /// and saying nothing is what the column draws.
    static func spoken(_ row: InvoiceScreenPresenter.Line) -> String {
        var parts = [row.describes]
        if !row.beneath.isEmpty { parts.append(row.beneath) }
        if !row.hours.isEmpty { parts.append("\(row.hours) hours at \(row.rate)") }
        parts.append(row.amount)
        return parts.joined(separator: ", ")
    }

    // MARK: the money

    private var money: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(presenter.money, id: \.label) { row in
                HStack(spacing: Column.gap) {
                    Spacer(minLength: 0)
                    Text(row.label)
                        .font(.system(size: row.isTotal ? 14 : 13,
                                      weight: row.isTotal ? .semibold : .regular))
                        .foregroundStyle(row.isTotal ? OvationPalette.ink : OvationPalette.quiet)
                    Text(row.value)
                        .font(.system(size: row.isTotal ? 15 : 13.5, design: .monospaced))
                        .monospacedDigit()
                        .fontWeight(row.isTotal ? .semibold : .regular)
                        .foregroundStyle(OvationPalette.ink)
                        .frame(width: Column.amount, alignment: .trailing)
                }
                .padding(.vertical, row.isTotal ? 8 : 4)
                .overlay(alignment: .top) {
                    if row.isTotal { Divider().overlay(OvationPalette.rule) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(row.label), \(row.value)")
            }
        }
        .padding(.horizontal, Column.sideMargin)
        .padding(.top, 10)
    }

    // MARK: the foot

    /// WHAT THE FOOT CARRIES CHANGES WITH THE INVOICE'S STATE (round 9), and the
    /// refusal sits beside the action rather than replacing it: a greyed control
    /// with no reason is a dead control (L109).
    private var foot: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            if !presenter.due.isEmpty {
                Text("Due \(presenter.due)")
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(OvationPalette.soft)
            }
            Spacer(minLength: 0)
            if let refusal = presenter.refusal {
                Text(refusal)
                    .font(.system(size: 13))
                    .foregroundStyle(OvationPalette.quiet)
                    .multilineTextAlignment(.trailing)
            }
            reviewWord
        }
        .padding(.horizontal, Column.sideMargin)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider().overlay(OvationPalette.rule) }
    }

    /// THE WORD IS DRAWN QUIET AND UNPRESSABLE WHEN IT CANNOT BE PRESSED, rather
    /// than pressable with nothing behind it. It is the honest option ovation#450
    /// names: the foot says what is needed without offering to do it.
    @ViewBuilder
    private var reviewWord: some View {
        if presenter.mayReview, let review {
            Button("Review", action: review)
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OvationPalette.ink)
                .underline()
        } else {
            Text("Review")
                .font(.system(size: 14))
                .foregroundStyle(OvationPalette.faint)
                .accessibilityLabel(presenter.refusal.map { "Review, not yet: \($0)" } ?? "Review")
        }
    }
}
