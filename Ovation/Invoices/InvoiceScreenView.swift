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

    /// ovation#457. Recording the client's tax status, or nil where the caller has
    /// nowhere to put it.
    ///
    /// NIL STATES THE QUESTION AND OFFERS NO ANSWERS, rather than two words that
    /// look pressable and are not, which is the defect ovation#450 named and this
    /// screen's own header says it must not ship (L109).
    var answerTax: ((PersistentIdentifier, TaxStatus) -> Void)?
    /// Why the last answer was not recorded, said rather than swallowed (L109).
    var refusedTax: String?

    /// ovation#457, PRD 5.4. Adding a line of a chosen type at a typed amount, or
    /// nil where the caller has nowhere to put it, in which case the word is not
    /// drawn at all rather than drawn dead (L109, ovation#450).
    var addLine: ((PersistentIdentifier, Money) -> Void)?
    /// Making a service type from inside the invoice, or nil where nothing can.
    /// NIL DROPS THE LIST'S TRAILING ENTRY rather than offering a word that opens
    /// nothing.
    var createType: ((String, Money?) -> Void)?
    /// Why the last line or type was not written, said rather than swallowed.
    var refusedLine: String?

    /// ovation#457, PRD 5.4a. Changing this invoice's discount, or taking it off
    /// when given nothing. Nil where the caller has nowhere to put it, in which
    /// case the figure is still drawn and the controls are not (L651).
    var setDiscount: ((Discount?) -> Void)?

    /// What is in the discount's value field, and which unit it is in.
    ///
    /// THE TYPING IS THIS SCREEN'S AND THE VALUE IS THE STORE'S. The field holds
    /// what is being typed, and every time the store's answer changes it is
    /// seeded again from that answer, so a committed value comes back in its
    /// canonical form and nothing typed is silently kept over what was saved
    /// (L646, L14).
    @State private var discountTyped = ""
    @State private var discountIsPercent = true

    /// Which type the row being filled in is for, or nil while it is still being
    /// chosen. Local to this viewing, like the revealed times above it: a row
    /// half built is a state of looking at the screen, not of the invoice.
    @State private var adding: InvoiceScreenPresenter.ServiceChoice?
    /// Whether a row is being added at all, which is separate from which type it
    /// is for: the row exists before the type is chosen. TWO PIECES OF STATE
    /// BECAUSE THEY ARE TWO FACTS, and folding them into one optional would make
    /// "no row" and "a row with no type yet" the same thing (L544).
    @State private var addingARow = false
    @State private var typedAmount = ""
    @State private var panelIsOpen = false
    @State private var typedName = ""
    @State private var typedUsual = ""
    /// The name of a type just asked for, until it appears in the list. The
    /// design record settles that a type made from the panel becomes the row's
    /// type, and the name is what identifies it: `ServiceTypeWriter` refuses a
    /// duplicate, so a name names exactly one type.
    @State private var awaitingType: String?

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
                    if addingARow { addingRow }
                    if offersALine { addWord }
                    if let refusedLine { refusal(refusedLine) }
                    money
                    if let question = presenter.taxQuestion { taxQuestion(question) }
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

    // MARK: adding a line

    /// A REFUSED LINE IS SAID ON THE PAGE, never only inside the panel that may
    /// already have closed, because a refusal whose only surface dies with the
    /// attempt leaves pressing it again as the only diagnosis (L148, L109).
    private func refusal(_ sentence: String) -> some View {
        Text(sentence)
            .font(.system(size: 12))
            .foregroundStyle(OvationPalette.quiet)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Column.sideMargin)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Whether the word is drawn at all.
    ///
    /// TWO CONDITIONS READ ONCE, so whether the word is there and whether
    /// pressing it can do anything come from one answer rather than two that can
    /// disagree (L70). `InvoiceLineWriter` refuses the same states, because a
    /// screen gating a write is not the write being guarded (L196).
    private var offersALine: Bool { presenter.mayAddLine(canMakeAType: createType != nil) && addLine != nil }

    /// THE WORD IS QUIET AND IT IS A BUTTON, which is the design record's own
    /// `.laddbtn`: a word with padding, no border and no underline. It is not
    /// `ActionWord`, whose underline is the treatment reserved for the one action
    /// a surface is for, and `check-one-action-word.sh` refuses a second
    /// underline anywhere in the app's Swift.
    private var addWord: some View {
        Button("Add a line") {
            addingARow = true
            adding = nil
            typedAmount = ""
        }
        .buttonStyle(.plain)
        .font(.system(size: 13.5))
        .foregroundStyle(OvationPalette.quiet)
        .padding(.horizontal, Column.sideMargin)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The row being filled in, which is its own view so that every state of it
    /// is a case a test can produce (L442).
    private var addingRow: some View {
        AddingLineRow(
            chosen: adding,
            types: Self.typeRows(for: presenter.serviceTypes),
            amount: $typedAmount,
            askNewType: createType == nil ? nil : {
                typedName = ""
                typedUsual = ""
                panelIsOpen = true
            },
            choose: { row in
                // FOUND BACK BY THE ROW'S OWN IDENTITY rather than by position,
                // because a list addressed by position writes whatever currently
                // occupies it (L237).
                guard let chosen = presenter.serviceTypes
                    .first(where: { $0.name == row.id }) else { return }
                adding = chosen
                typedAmount = Self.prefill(for: chosen)
            },
            commit: commitLine,
            columns: (Column.hours, Column.rate, Column.amount,
                      Column.gap, Column.sideMargin))
        .sheet(isPresented: $panelIsOpen) { newTypePanel }
        // A TYPE MADE FROM THE PANEL BECOMES THIS ROW'S TYPE, which the design
        // record settles. It is picked up when the list it was written to comes
        // back, because the write is an actor's and the screen is rebuilt from
        // the store rather than edited in place (L14).
        .onChange(of: presenter.serviceTypes) { _, types in
            guard let awaitingType,
                  let made = Self.newlyMade(named: awaitingType, in: types) else { return }
            self.awaitingType = nil
            adding = made
            typedAmount = Self.prefill(for: made)
        }
    }

    /// The types as the one list draws them.
    ///
    /// NAMED AND STATIC SO IT CAN BE TESTED, for the reason `DueDateControl.rows`
    /// is: the list lives in a popover, which is its own window and beyond any
    /// view tree test, so this translation is the part a test can hold and it is
    /// the part that decides which type a press writes (L442).
    ///
    /// NOTHING BESIDE THE NAME, which is what the design record's own type list
    /// draws: its rows carry a label and no second column.
    static func typeRows(for types: [InvoiceScreenPresenter.ServiceChoice])
        -> [PopupList.Choice] {
        types.map { PopupList.Choice(id: $0.name, says: $0.name) }
    }

    /// What the amount field starts at when a type is chosen.
    ///
    /// A TYPE WITH NO USUAL AMOUNT LEAVES IT EMPTY, never a zero: the design
    /// record says in terms that a type charging nothing and a type with no usual
    /// amount are different things, and one of them would prefill every line it
    /// is used on with 0.00 (PRD 5.1b).
    static func prefill(for type: InvoiceScreenPresenter.ServiceChoice) -> String {
        type.usually.map(PDFText.amount) ?? ""
    }

    /// The type a name was just asked for, once it is there.
    ///
    /// BY NAME, because that is what was typed and `ServiceTypeWriter` refuses a
    /// duplicate, so a name names exactly one type. Trimmed on both sides, since
    /// the writer stores the trimmed form and the panel holds what was typed
    /// (L185).
    static func newlyMade(named typed: String,
                          in types: [InvoiceScreenPresenter.ServiceChoice])
        -> InvoiceScreenPresenter.ServiceChoice? {
        let wanted = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return types.first { $0.name == wanted }
    }

    /// Whether a name can make a type.
    ///
    /// THE CONTROL LOOKS INERT RATHER THAN REFUSING AFTER THE PRESS, which is the
    /// design record's own reasoning and L109's: a control that does nothing and
    /// gives no reason leaves pressing it again as the only diagnosis.
    /// `ServiceTypeWriter` refuses the same thing, because a screen gating a
    /// write is not the write being guarded (L196).
    static func canCreate(_ typed: String) -> Bool {
        !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Writes the row being filled in, or leaves it alone.
    ///
    /// AN AMOUNT IT CANNOT READ LEAVES THE ROW WHERE IT IS, rather than adding a
    /// line worth nothing that would be indistinguishable from a comped one,
    /// which is the design record's own rule and PRD 5.1b's reason.
    private func commitLine() {
        guard let adding, let amount = Money.read(typedAmount) else { return }
        addLine?(adding.id, amount)
        addingARow = false
        self.adding = nil
        typedAmount = ""
    }

    /// A NEW SERVICE TYPE. It asks one question beyond the name, what the type
    /// usually charges, which a `ServiceType` genuinely carries and none of the
    /// three seeded ones has, and which is what prefills every line it is used on.
    ///
    /// IT DOES NOT ASK FOR THE ROLE. That is code's rather than Dan's: exactly one
    /// type is the hourly photography line and a second would make the invoice's
    /// own pricing ambiguous, so everything made here is ordinary.
    private var newTypePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A new service type")
                .font(.system(size: 21, design: .serif))
                .foregroundStyle(OvationPalette.ink)
            Text("Name")
                .font(.system(size: 12))
                .foregroundStyle(OvationPalette.quiet)
            TextField("", text: $typedName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13.5))
                .frame(width: 280)
                .accessibilityLabel("Name")
            Text("What it usually charges, if it has a usual amount")
                .font(.system(size: 12))
                .foregroundStyle(OvationPalette.quiet)
            TextField("", text: $typedUsual)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13.5, design: .monospaced))
                .frame(width: 280)
                .accessibilityLabel("What it usually charges")
                .onSubmit(commitType)
            if let refusedLine {
                Text(refusedLine)
                    .font(.system(size: 12))
                    .foregroundStyle(OvationPalette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 280, alignment: .leading)
            }
            HStack(spacing: 14) {
                Spacer(minLength: 0)
                Button("Cancel") { panelIsOpen = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(OvationPalette.quiet)
                Button("Create", action: commitType)
                    .buttonStyle(.plain)
                    .fontWeight(Self.canCreate(typedName) ? .semibold : .regular)
                    .foregroundStyle(Self.canCreate(typedName)
                                     ? OvationPalette.accent : OvationPalette.faint)
                    .disabled(!Self.canCreate(typedName))
            }
            .font(.system(size: 13.5))
        }
        .padding(20)
        .frame(minWidth: 344, alignment: .leading)
        .background(OvationPalette.background)
        // A sheet is its own window, so it sets its own appearance (PRD 43,
        // ovation#474).
        .ovationAppearance()
    }

    /// Makes the type, or leaves the panel where it is.
    ///
    /// AN AMOUNT IT CANNOT READ IS NO AMOUNT, never a zero, which is what keeps a
    /// type that charges nothing and a type with no usual amount different things.
    private func commitType() {
        guard Self.canCreate(typedName) else { return }
        awaitingType = typedName
        createType?(typedName, Money.read(typedUsual))
        panelIsOpen = false
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
                // BENEATH THE ROW IT BELONGS TO, above the tax and the total,
                // which is where the design record puts it. It was beneath the
                // whole block until the picture was looked at, which put it
                // four rows from the figure it changes.
                if row.isDiscount, let editing = presenter.discountBeingEdited,
                   setDiscount != nil {
                    discountControls(editing)
                }
            }
        }
        .padding(.horizontal, Column.sideMargin)
        .padding(.top, 10)
    }

    // MARK: the discount

    /// The discount's own line, seeded from the store and handing back what was
    /// typed.
    ///
    /// AN UNREADABLE VALUE LEAVES THE DISCOUNT ALONE, and that is a deliberate
    /// difference from the design record, filed as ovation#495. The record's own
    /// field turns anything it cannot read into a ZERO, and a zero discount is a
    /// legitimate recorded decision rather than an absence (PRD 5.1b), so that
    /// would write a decision nobody made and leave an invoice indistinguishable
    /// from one discounted to nothing on purpose (L340). It is also what the
    /// line's amount field already does, for the reason the record gives there.
    private func discountControls(_ editing: InvoiceScreenPresenter.DiscountEdit) -> some View {
        DiscountLine(isPercent: discountIsPercent,
                     value: $discountTyped,
                     width: 318,
                     setUnit: { wantsPercent in
                         discountIsPercent = wantsPercent
                         commitDiscount()
                     },
                     commit: commitDiscount,
                     remove: { setDiscount?(nil) })
            // NO SIDE MARGIN OF ITS OWN: it is inside the money block, which
            // already carries it, and a second one would put this line's right
            // edge off the one every figure above it shares (L553).
            // SEEDED FROM THE STORE, INCLUDING THE FIRST TIME. `initial: true` is
            // what makes an invoice opened with a discount already on it show
            // that discount rather than an empty field, which no later change
            // would ever fix.
            .onChange(of: presenter.discountBeingEdited, initial: true) { _, _ in
                discountTyped = editing.typed
                discountIsPercent = editing.isPercent
            }
    }

    /// Reads what was typed and saves it, or leaves the discount as it is.
    ///
    /// THE TWO UNITS READ THROUGH ONE PARSER, each stripping only its own sign,
    /// so a figure typed into one cannot be read as the other's (L118).
    private func commitDiscount() {
        guard let read = Hundredths.read(discountTyped,
                                         stripping: discountIsPercent ? "%" : "$")
        else { return }
        let wanted = discountIsPercent
            ? Discount(percentBasisPoints: read)
            : Discount(dollars: Money(cents: read))
        // REFUSED BY THE TYPE, NOT BY A SECOND RULE HERE. A share outside
        // nothing to everything and a negative amount are what `Discount`'s own
        // initialisers refuse, and a control that refused them again would be a
        // second place for that rule to live (L370).
        guard let wanted else { return }
        setDiscount?(wanted)
    }

    // MARK: the tax status question

    /// THE TWO ANSWERS SIT IN THE BLOCK THAT STATES THE FACT, which is the design
    /// record's own rule: "the thing stopping the invoice should be answerable
    /// where it is said."
    ///
    /// THEY ARE ON THEIR OWN LINE BENEATH THE SENTENCE, and that is measured
    /// rather than chosen: the record notes that at the block's width the
    /// sentence and two controls do not fit on one line and the second answer
    /// wrapped under the first.
    ///
    /// NO SENTENCE EXPLAINS THAT THE ANSWER IS RECORDED ON THE CLIENT. The design
    /// record settled that deliberately and says why: that was the interface being
    /// explained rather than the domain (L604).
    @ViewBuilder
    private func taxQuestion(_ question: InvoiceScreenPresenter.TaxQuestion) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(question.says)
                .font(.system(size: 12.5))
                .foregroundStyle(OvationPalette.quiet)
                .multilineTextAlignment(.trailing)
            if let answerTax {
                HStack(spacing: 6) {
                    ForEach(question.answers, id: \.self) { answer in
                        Button { answerTax(question.about, answer) } label: {
                            answerChip(answer.exportLabel)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let refusedTax {
                Text(refusedTax)
                    .font(.system(size: 12))
                    .foregroundStyle(OvationPalette.quiet)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, Column.sideMargin)
        .padding(.top, 8)
    }

    /// NOTHING NATIVE, NOTHING DEFAULT (L607). The roster pass records this same
    /// answer and its chips came out as ghost text with no visible edge while they
    /// were SwiftUI's `.bordered`, which no view tree test could see because the
    /// words were all present.
    ///
    /// AND IT IS NOT THAT SCREEN'S CHIP, deliberately. The geometry here is
    /// `docs/design/invoice.html`'s `.taxpick`, quoted rather than invented: 12px,
    /// 2 by 9 padding, a 5px radius, the chrome fill and a one pixel rule. The
    /// roster's is its own record's `.chip`: 3 by 11 padding, a 4px radius, the
    /// soft ink on the page background. Two similar rules that differ may each be
    /// a recorded decision, and both of these are, settled on the surface each is
    /// drawn on, the same way this screen writes "Sales tax, 8.875%" where the PDF
    /// writes "Sales tax (8.875%)" (L542). Making them agree is a design question
    /// for Dan rather than a tidy up, and it is filed as one.
    private func answerChip(_ word: String) -> some View {
        Text(word)
            .font(.system(size: 12))
            .foregroundStyle(OvationPalette.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(OvationPalette.chrome)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(OvationPalette.rule, lineWidth: 1))
            )
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
            // THE FOOT DOES NOT REPEAT WHAT THE BODY IS ALREADY ANSWERING, which
            // the presenter decides, because a view deciding it could only be
            // checked by rendering (L605).
            if let refusal = presenter.refusalAtTheFoot {
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
