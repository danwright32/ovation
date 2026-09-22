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

    /// Which end of a shoot a time belongs to.
    enum Edge { case start, end }

    /// Writing a time Dan has typed, or nil where nothing can write it (every
    /// hosted test written before this, and any caller with no store). The write
    /// itself is `ShootTimesWriter`, reached through the app, because a view may
    /// not hold a context (PRD 51l, ovation#440).
    var setTime: ((PersistentIdentifier, Edge, ClockTime?) -> Void)?
    /// ovation#473. What saving a due date does, or nil where the caller has
    /// nowhere for it to go yet.
    var setDueDate: ((BusinessDate) -> Void)?
    /// Why the last date was not saved, said rather than swallowed (L109).
    var refusedDate: String?

    /// Which empty time fields Dan has asked to fill in. Local to the screen and
    /// deliberately not stored: it is a state of this viewing, and reopening the
    /// invoice should show the word again rather than a picker over nothing.
    @State private var revealed: Set<String> = []

    /// Why the last write was refused, or nil. Shown in the head, beside the times
    /// it is about, because the thing stopping the invoice should be answerable
    /// where it is said, which is the design record's own rule for the tax status.
    var refused: String?

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
        .ovationAppearance()
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
                times
                if let refused {
                    // NEVER RED. A refused write is not something that went wrong
                    // with the invoice, it is a state that changed underneath the
                    // screen, and red belongs only where something genuinely is
                    // (PRD 5.45).
                    Text(refused)
                        .font(.system(size: 12.5))
                        .foregroundStyle(OvationPalette.soft)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            // WHICH THE INVOICE IS, which the design record draws at the top right
            // and which carries ovation#411's held number.
            Text(presenter.state)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OvationPalette.faint)
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
        .accessibilityLabel("\(presenter.client), \(presenter.shoot), \(presenter.state)")
    }

    /// THE TIMES SIT BESIDE THE SHOOT (round 4b), one labelled pair per shoot, and
    /// they are the piece that makes a draft sendable: PRD 3c says a draft carries
    /// no duration and cannot go out until Dan supplies one, and this is where he
    /// supplies it.
    ///
    /// ONE PAIR PER SHOOT, because PRD 5.1a puts more than one on a combined
    /// invoice and Dan asked for that case to be drawn before he chose this
    /// placement: "I worry about how it would work for invoices with multiple
    /// events."
    @ViewBuilder
    private var times: some View {
        if !presenter.shoots.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(presenter.shoots) { shoot in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if presenter.shoots.count > 1 {
                            Text(shoot.name)
                                .font(.system(size: 12.5))
                                .foregroundStyle(OvationPalette.quiet)
                                .lineLimit(1)
                        }
                        Text("Ran").font(.system(size: 12.5))
                            .foregroundStyle(OvationPalette.quiet)
                        timeField(shoot, .start, shoot.start, label: "Start time")
                        Text("to").font(.system(size: 12.5))
                            .foregroundStyle(OvationPalette.quiet)
                        timeField(shoot, .end, shoot.end, label: "End time")
                        if !shoot.derived.isEmpty {
                            Text(shoot.derived)
                                .font(.system(size: 12.5))
                                .foregroundStyle(OvationPalette.quiet)
                        }
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    /// ONE TIME, AS THE PLATFORM'S OWN CONTROL. The design record says so in as many
    /// words: "In the real app this is a SwiftUI DatePicker in its field style,
    /// which is exactly this: a compact field of segments with a stepper. So this
    /// rendering approximates the PLATFORM control rather than inventing one."
    ///
    /// IN THE BUSINESS ZONE, NOT THE MAC'S. A `DatePicker` renders its `Date` in the
    /// environment's time zone, so on a Mac set to anything but New York the hour
    /// drawn would not be the hour stored. `BusinessCalendar.timeZone` is the one
    /// zone every date in this app goes through (plan 1.5, L39), and it is put into
    /// the environment rather than read from `Calendar.current`, which the
    /// forbidden constructs scanner refuses for exactly this reason.
    @ViewBuilder
    private func timeField(_ shoot: InvoiceScreenPresenter.TimedShoot, _ edge: Edge,
                           _ time: ClockTime?, label: String) -> some View {
        if presenter.mayEdit, let setTime {
            // A TIME THAT IS NOT GIVEN IS NOT DRAWN AS A TIME, and this is the one
            // place the platform control cannot do what the design record's own can.
            // `DatePicker` has no empty state: handed a placeholder it renders it as
            // a real time, and a draft with no end time drew "Ran 7:00 PM to
            // 12:00 AM", which is a plausible shoot ending at midnight. A
            // placeholder for a missing required value is a detection, not a label
            // (L67), and the design record has `.tempty` for exactly this.
            //
            // SO IT IS REVEALED RATHER THAN PRE-FILLED. Until Dan asks for the
            // field, the word says there is no time. Asking for it shows the picker
            // seeded at the shoot's start, and NOTHING IS WRITTEN until he moves it,
            // so the seed is a starting point he can see rather than a value that
            // arrived on its own. PRD 3c rejected pre-filling an hour for the same
            // reason: a figure nobody typed is indistinguishable from one somebody
            // did, on exactly the shoots where the mistake matters.
            if time == nil && !revealed.contains(Self.key(shoot, edge)) {
                Button("Not given") { revealed.insert(Self.key(shoot, edge)) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 12.5))
                    .foregroundStyle(OvationPalette.faint)
                    .accessibilityLabel("\(label) for \(shoot.name), not given")
            } else {
                DatePicker(
                    label,
                    selection: Binding(
                        get: { Self.date(of: time ?? shoot.start) },
                        set: { setTime(shoot.id, edge, Self.clockTime(of: $0)) }),
                    displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .environment(\.timeZone, BusinessCalendar.timeZone)
                    .accessibilityLabel("\(label) for \(shoot.name)")
                    .fixedSize()
            }
        } else {
            // NOT OFFERED RATHER THAN OFFERED AND REFUSED. A sent invoice's times
            // priced a document a client holds, and a control that opens onto a
            // refusal is a dead control (L651, L109).
            Text(time.map(Self.written) ?? "not given")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(time == nil ? OvationPalette.faint : OvationPalette.ink)
        }
    }

    /// The gregorian calendar pinned to the one zone every date in this app goes
    /// through (plan 1.5, L39). `Calendar.current` is refused by the forbidden
    /// constructs scanner, and this is why: an hour drawn in the Mac's zone and
    /// stored in New York's are different hours the day Dan travels.
    private static var businessCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BusinessCalendar.timeZone
        return calendar
    }

    /// A clock time as a `Date` the picker can show, on an arbitrary day.
    ///
    /// BUILT FROM COMPONENTS, NOT BY ADDING SECONDS TO A REFERENCE DATE. The
    /// reference date is midnight UTC, which is 19:00 the previous day in New York,
    /// so adding the minutes to it drew an hour five off the one stored.
    static func date(of time: ClockTime?) -> Date {
        let minutes = time?.minutesSinceMidnight ?? 0
        var parts = DateComponents()
        parts.year = 2000; parts.month = 1; parts.day = 1
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        return businessCalendar.date(from: parts) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    /// And back again, through the same zone the picker drew it in.
    static func clockTime(of date: Date) -> ClockTime? {
        let parts = businessCalendar.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return ClockTime(hour: hour, minute: minute)
    }

    /// One field's identity, so revealing the end of one shoot does not reveal the
    /// end of another (L166).
    static func key(_ shoot: InvoiceScreenPresenter.TimedShoot, _ edge: Edge) -> String {
        "\(shoot.id)-\(edge == .start ? "start" : "end")"
    }

    /// `19:00`, the way the duration rule reads and writes one.
    static func written(_ time: ClockTime) -> String {
        let hour = time.minutesSinceMidnight / 60, minute = time.minutesSinceMidnight % 60
        return String(format: "%02d:%02d", hour, minute)
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
            // ovation#473. WHEN IT WAS WRITTEN AND WHEN IT IS DUE, and the second
            // is a control. PRD 5.7 makes the due date overridable per invoice and
            // the app printed it as text, so the one thing the requirement says can
            // be changed could not be.
            DueDateControl(issued: presenter.issued, due: presenter.due,
                           choices: presenter.dueChoices,
                           save: presenter.mayEdit ? setDueDate : nil,
                           refused: refusedDate)
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
    ///
    /// AND IT IS `ActionWord`, THE ONE COMPONENT, rather than the copy that used
    /// to be here. There were two of these, this and the list's action, and a
    /// second hand rolled one is what ovation#450's own guard now refuses (L613).
    private var reviewWord: some View {
        ActionWord(word: "Review", size: 14,
                   press: presenter.mayReview ? review : nil,
                   notYet: presenter.refusal)
    }
}
