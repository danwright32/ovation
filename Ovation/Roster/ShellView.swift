// ovation#40, PRD 44a and 44. The window: the espresso rail, and whatever screen
// you are standing on.
//
// THE RAIL IS FULL HEIGHT AND CARRIES THE COLOUR (PRD 44). In the design file
// the traffic lights are drawn on it by hand; here the system draws them, which
// is one of the three web idioms the design record says must be translated
// rather than copied.
//
// THE CARD SAYS WHAT IS TRUE ON DAY ONE. PRD 46a's five counts are counts of
// INVOICES, and Ovation holds none, so the card says `Nothing waiting` rather
// than borrowing the invoice list's fixture numbers. A number in this card means
// this many things need you (PRD 46b), and drawing four that nothing can produce
// would break that promise on the first screen that ever states it.
//
// MONEY HELD IS NOT DRAWN AT ALL YET, and that is the zero rule rather than an
// omission: PRD 46b makes it a quantity, and a quantity of nothing is not drawn.
import SwiftData
import SwiftUI

struct ShellView: View {
    @Bindable var shell: ShellPresenter
    @Bindable var roster: RosterPresenter
    /// WHERE A LAUNCH NOTICE LANDS ONCE THE SHELL OWNS THE WINDOW. `RootView` is
    /// the one surface every launch time condition reaches Dan through
    /// (ovation#59), and this view REPLACES it, so without the status block at
    /// the foot of the rail a foreign store, a failed backup or a stale export
    /// would be raised, recorded, and seen by nobody (L242, L98).
    ///
    /// NOT OPTIONAL AND WITH NO DEFAULT, deliberately. A default would let a
    /// future call site forget the wiring and still compile, which is the whole
    /// shape of this failure (L168).
    @Bindable var problems: ProblemsStore
    /// When "I have read this" was pressed, stamped on the acknowledgement. The app
    /// passes the real clock and a test a fixed one, the same seam `RootView` has.
    var now: () -> Date = Date.init
    /// ovation#162. The year end export, so a run in progress is said at the foot
    /// of the rail. Nil where this launch has no export control, and in hosted tests
    /// written before the shell carried it.
    var exportCommand: YearEndExportCommand?

    /// The invoice list, or nil where it could not be read out of the store.
    /// NOT OPTIONAL BECAUSE IT IS OPTIONAL TO PASS: the nil means one thing only,
    /// that the read failed and a problem was raised for it.
    var invoices: InvoiceListPresenter?

    /// What Ovation is holding across every client, drawn under the card (PRD 46b),
    /// and nil where it is holding nothing, because a quantity of nothing is not
    /// drawn.
    var heldMoney: String?

    /// ovation#457. How to build the screen for a row, or nil where nothing can
    /// (every hosted test written before this, and every launch with no store).
    ///
    /// A CLOSURE RATHER THAN THE SOURCE ITSELF, so this view cannot reach a
    /// `ModelContext` even by accident: the resolution lives on
    /// `InvoiceListSource`, which owns the container (PRD 51l, ovation#440).
    var openInvoice: ((PersistentIdentifier) -> InvoiceScreenPresenter?)?

    /// ovation#457. Writing a time Dan typed, which is what makes a draft sendable
    /// (PRD 3c). Nil where nothing can write. The write itself is
    /// `ShootTimesWriter`; this view only says which shoot and which end.
    var writeTime: ((PersistentIdentifier, InvoiceScreenView.Edge, ClockTime?) async -> String?)?
    /// ovation#473. What saving a due date does, and what it says when it does
    /// not. Nil where this launch has no store to write to.
    var writeDueDate: ((PersistentIdentifier, BusinessDate) async -> String?)?
    /// ovation#457, PRD 5.5. Recording the client's sales tax status, which is
    /// the one question this screen asks about the client rather than the
    /// invoice. Nil where this launch has no store to write to.
    var writeTaxStatus: ((PersistentIdentifier, TaxStatus) async -> String?)?
    /// ovation#457, PRD 5.4. Adding a line of a chosen type at a typed amount,
    /// and making a service type from inside the invoice. Nil where this launch
    /// has no store to write to.
    var writeLine: ((PersistentIdentifier, PersistentIdentifier, Money) async -> String?)?
    var writeServiceType: ((String, Money?) async -> String?)?
    /// ovation#457, PRD 5.4a. Changing this invoice's discount, or taking it off
    /// when given nothing. Nil where this launch has no store to write to.
    var writeDiscount: ((PersistentIdentifier, Discount?) async -> String?)?
    /// ovation#457, PRD 5.8 and 5.51e. Putting the client's referral credit on
    /// this invoice or taking it back off. Nil where this launch has no store to
    /// write to.
    var writeReferralCredit: ((PersistentIdentifier, ReferralCreditChange) async -> String?)?
    /// ovation#510, PRD 51m and 51n. Recording a payment on the invoice on
    /// screen, and clearing a check, each answering with a sentence where it did
    /// nothing. Nil where this launch has no store to write to.
    var writePayment: ((PersistentIdentifier, PaymentEntry) async -> String?)?
    var writeCleared: ((PersistentIdentifier) async -> String?)?
    /// ovation#185, PRD 14i and 14j. Putting the client's held money on the
    /// invoice on screen, or taking it back off. Nil where this launch has no
    /// store to write to.
    var writeHeldMoney: ((PersistentIdentifier, HeldMoneyChange) async -> String?)?

    /// ovation#568. The Clients screen, derived in the same read as the list, or
    /// nil where that read failed (or in a hosted test written before it existed).
    var clients: ClientsPresenter?
    /// ovation#568, PRD 51j and 38c. Recording a client's standing payment terms,
    /// and saying a shared address is correct. Nil where nothing can write. The tax
    /// status is `writeTaxStatus`, the one write every screen that asks it uses.
    var writePaymentTerm: ((PersistentIdentifier, PaymentTerm) async -> String?)?
    var acknowledgeSharedAddress: ((PersistentIdentifier) async -> String?)?

    /// What the Edit menu is allowed to offer about the invoice on screen. The
    /// menu is declared on the app, outside every view, so this is how what is
    /// open reaches it (ovation#457).
    var edits: InvoiceEditCommand?
    /// ovation#42. Opening the review of the invoice on screen, sending it, and closing
    /// it, as ONE value rather than a closure per act, so a layer cannot pass half of it
    /// (ovation#485). Nil where this launch has no store, and then Review is not offered.
    var reviewer: InvoiceReviewer?

    /// ovation#510. Whether the payment sheet is open, whether a press is being
    /// recorded, and why the last payment or clearing did nothing. Held here
    /// because the screen is rebuilt after every write, and a sheet that closed
    /// itself on the rebuild would lose a refusal it was showing.
    @State private var payingIsOpen = false
    @State private var paymentIsRecording = false
    @State private var refusedPayment: String?
    @State private var refusedClearing: String?
    /// Why the last Use it here, Use it or Remove did nothing, held here for the
    /// reason the payment's refusals are: the screen is rebuilt after every write.
    @State private var refusedHeldMoney: String?

    /// Which client's page is open on the Clients screen. Held here because the
    /// screen is rebuilt after every write, and a selection kept inside it would be
    /// lost each time (ovation#568).
    @State private var selectedClient: UUID?
    /// Which invoice is selected. It lives here rather than inside the list
    /// because coming back from an invoice has to find the row again (ovation#125).
    @State private var selectedInvoice: PersistentIdentifier?
    /// The invoice being worked on, or nil while the list is showing (ovation#457).
    @State private var openedInvoice: InvoiceScreenPresenter?
    /// Which one, so the screen can be built again after a write changes it.
    @State private var openedInvoiceID: PersistentIdentifier?
    /// Why the last due date was not saved, or nil. Held here rather than in the
    /// screen because the screen is rebuilt after every write.
    @State private var refusedDate: String?
    /// Why the last write was refused, or nil. A refusal here is a race (the row
    /// went, or the invoice was sent from elsewhere), because the field is not
    /// offered at all on an invoice that may not be edited. It is still SAID: a
    /// write that silently does nothing leaves typing it again as the only
    /// diagnosis (L109, L148).
    @State private var refusedWrite: String?
    /// Why the last tax status was not recorded, or nil. Held here for the same
    /// reason the refused date is: the screen is rebuilt after every write.
    @State private var refusedTax: String?
    /// Why the last line or service type was not written, or nil.
    @State private var refusedLine: String?
    /// Discount writes finished, saved or refused, handed to the screen so it can
    /// refill its field from the store after each (ovation#495).
    @State private var discountSettled = 0
    /// The review open over the invoice, or nil (ovation#42).
    @State private var openReview: InvoiceReview?
    @State private var reviewOnScreen = ReviewOnScreen<InvoiceReview>()
    /// ovation#471. The unsettled send Dan asked to mark as not sent, awaiting his
    /// confirmation, with the sentence naming what it does to that invoice.
    @State private var settling: Settling?
    /// Why the last Mark unsent or Send from the list did not happen, said on the
    /// list where it was pressed (L109).
    @State private var refusedOnTheList: String?
    /// Why the last Review could not be opened, or nil. Said, never swallowed: a
    /// control that silently does nothing leaves pressing it again as the only
    /// diagnosis (L109, L148).
    @State private var refusedReview: String?
    /// ovation#548. Why the last Remind or Send a copy could not open the sheet, said
    /// at the foot beside the word that was pressed (L109).
    @State private var refusedResend: String?
    /// ovation#556. Whether the invoice's history pane is open, and which of its
    /// entries are the payment just recorded (PRD 51o). Held here rather than in the
    /// screen because it is Record, which finishes here, that opens it, and the screen
    /// is rebuilt after every write.
    @State private var historyIsOpen = false
    @State private var historyMarks: Set<String> = []

    /// What a destination with no screen behind it says about itself. A constant
    /// because a test counts them, and because the same words appear once per
    /// unbuilt entry and must not drift between them.
    static let notBuiltMark = "not built yet"

    /// ovation#485. Lets a hosted test read this view while it is on screen, which is
    /// the only way to reach the invoice it keeps open in `@State`, and so the only
    /// way to prove the writes it is given reach that screen and the Edit menu. It
    /// never fires in the app (see `Inspection`).
    let inspection = Inspection<Self>()

    var body: some View {
        HStack(spacing: 0) {
            rail
            VStack(spacing: 0) {
                titleBar
                content
            }
        }
        // THE RAIL RUNS TO THE TOP OF THE WINDOW (ovation#593, the design record's
        // window top). The title bar is transparent, so the rail carries the traffic
        // lights and `titleBar` is the chrome over the content. The rail's 34 point
        // top padding was always the design's room for the traffic lights; it sat
        // under a system title bar only because this never reached the top.
        .ignoresSafeArea(.container, edges: .top)
        // THE MINIMUM IS HALF DAN'S SCREEN (ovation#110), from `OvationWindow`,
        // which the design record's check reads too. It was a literal 900 here,
        // chosen rather than measured and wider than the half screen he uses.
        .frame(minWidth: OvationWindow.minimumWidth, minHeight: 620, alignment: .topLeading)
        .ovationAppearance()
        // THE SHEET BELONGS TO THE WINDOW (PRD 52a) AND FLOATS OVER IT (PRD 48a,
        // ovation#547), centred below the title bar with every corner rounded, which a
        // system sheet cannot be: it hangs from the title bar with its top flat. Every
        // way it closes, Close, Done or the Escape key, goes through the reviewer,
        // which gives back a number the review took and nothing was sent under (Dan,
        // 2026-09-14). A send in flight holds it open, so Escape does nothing then.
        .overlay {
            if let review = openReview {
                FloatingSheet(below: Self.titleBarHeight, dim: .deep,
                              escape: review.state.holdsTheSheetOpen
                                  ? nil : { finishReview(review) }) {
                    ReviewSheet(presenter: review.presenter, review: review,
                                close: { finishReview(review) })
                }
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        // THE OPEN INVOICE FOLLOWS EVERY WRITE, not only this screen's own
        // (ovation#185). The list is read again after every committed write, and
        // some of those change the invoice on screen without it having asked: the
        // held money pass puts money on a draft the moment its times price it,
        // after this screen has already read it back. Keyed on the list's identity
        // because a new list is exactly what a write produces (L14).
        .onChange(of: invoices.map(ObjectIdentifier.init)) { _, _ in
            if let openedInvoiceID { openedInvoice = openInvoice?(openedInvoiceID) }
        }
        .onReceive(inspection.notice) { inspection.visit(self, $0) }
    }

    // MARK: the review (ovation#42)

    private func startReview() {
        guard let openedInvoiceID else { return }
        refusedReview = nil
        review(openedInvoiceID) { refusal in refusedReview = refusal }
    }

    /// ovation#517. Send from the list: the same review, opened over the list, so
    /// closing it leaves Dan on the list (Dan, 2026-09-24). A refusal is said on
    /// the list, where the press was.
    private func startReviewFromTheList(_ invoiceID: PersistentIdentifier,
                                        as kind: InvoiceMailKind? = nil) {
        refusedOnTheList = nil
        review(invoiceID, as: kind) { refusal in refusedOnTheList = refusal }
    }

    /// ovation#548. Remind or Send a copy from the invoice screen's foot: the same
    /// review, on that kind of send, with a refusal said beside the word pressed.
    private func startResend(_ kind: InvoiceMailKind) {
        guard let openedInvoiceID else { return }
        refusedResend = nil
        review(openedInvoiceID, as: kind) { refusal in refusedResend = refusal }
    }

    /// Opens the review of one invoice, whichever screen asked, through the one
    /// reviewer, so what is sent never depends on where the press came from.
    private func review(_ invoiceID: PersistentIdentifier, as kind: InvoiceMailKind? = nil,
                        refused: @escaping (String) -> Void) {
        guard let reviewer else { return }
        Task {
            switch await reviewer.open(invoiceID, as: kind) {
            case .success(let review):
                reviewOnScreen.opened(review)
                openReview = review
            case .failure(let refusal): refused(refusal.sentence)
            }
            // THE NUMBER MAY HAVE BEEN TAKEN, so the invoice screen behind the sheet,
            // when that is where it opened, is built again and shows it.
            if let openedInvoiceID { openedInvoice = openInvoice?(openedInvoiceID) }
        }
    }

    /// One invoice Dan asked to mark as not sent, and what doing so means for it.
    struct Settling: Identifiable {
        let invoiceID: PersistentIdentifier
        let consequence: String
        var id: PersistentIdentifier { invoiceID }
    }

    private var settlingIsAsked: Binding<Bool> {
        Binding(get: { settling != nil }, set: { if !$0 { settling = nil } })
    }

    /// Asks before anything changes, naming the invoice's own number (L180, L608).
    private func askToSettle(_ invoiceID: PersistentIdentifier) {
        refusedOnTheList = nil
        guard let consequence = reviewer?.confirmation(forSettling: invoiceID) else {
            refusedOnTheList = SendSettleRefusal.noSuchInvoice.sentence
            return
        }
        settling = Settling(invoiceID: invoiceID, consequence: consequence)
    }

    private func settle(_ invoiceID: PersistentIdentifier) {
        settling = nil
        Task { refusedOnTheList = await reviewer?.markNotSent(invoiceID) }
    }

    /// Closes the review ONCE, however many routes arrive: a second press of Close,
    /// or Escape landing with it, finds nothing left to settle and hands nothing
    /// back twice.
    private func finishReview(_ review: InvoiceReview) {
        guard reviewOnScreen.settle() === review else { return }
        openReview = nil
        Task {
            await reviewer?.close(review)
            if let openedInvoiceID { openedInvoice = openInvoice?(openedInvoiceID) }
            publishWhatIsOpen()
        }
    }

    // MARK: the title bar

    /// The design record's `.titlebar`: 38 points of `--chrome` over the content,
    /// ending in a one point `--rule`, with no title (ovation#123). It draws nothing
    /// else and is not a control, so a screen reader skips it and reads the
    /// window's own hidden title instead.
    static let titleBarHeight: CGFloat = 38

    private var titleBar: some View {
        OvationPalette.chrome
            .frame(height: Self.titleBarHeight)
            .overlay(alignment: .bottom) {
                OvationPalette.rule.frame(height: 1)
            }
            .accessibilityHidden(true)
    }

    // MARK: the rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 1) {
            card
            ForEach(shell.destinations, id: \.self) { destination in
                railItem(destination)
            }
            Spacer(minLength: 14)
            status
        }
        .padding(.horizontal, RailFoot.railInset)
        .padding(.top, 34)
        .padding(.bottom, 12)
        .frame(width: OvationWindow.railWidth, alignment: .topLeading)
        .background(OvationPalette.rail)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Needs you")
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .kerning(1.3)
                .foregroundStyle(OvationPalette.railCardHeading)
            Text("Nothing waiting")
                .font(.system(size: 12.5))
                .foregroundStyle(OvationPalette.railCardLine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(OvationPalette.railCardBackground)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(OvationPalette.railCardBorder))
        .padding(.horizontal, 3)
        .padding(.bottom, 10)
    }

    private func railItem(_ destination: Destination) -> some View {
        let isHere = destination == shell.selected
        return Button {
            shell.go(to: destination)
        } label: {
            HStack(spacing: 8) {
                Text(destination.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isHere ? OvationPalette.railOnText : OvationPalette.railItem)
                Spacer()
                if !destination.isBuilt {
                    // PRESENT AND SAYING SO (PRD 44a). A destination that is
                    // present and silent is a dead control nobody can ask about,
                    // and one that is simply absent teaches nothing (L49, L109).
                    Text(Self.notBuiltMark)
                        .font(.system(size: 10.5))
                        .foregroundStyle(OvationPalette.railDim)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHere ? OvationPalette.railOnBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(!destination.isBuilt)
    }

    // MARK: what is open, at the foot of the rail (ovation#99, ovation#566)

    /// THE ZERO RULE, FOR THE PROBLEM AND NOTICE LINES ONLY. With nothing open none
    /// is drawn, rather than saying nothing is wrong in the place reserved for
    /// things that are. The line saying Ovation only looks while it is open stays
    /// every day (Dan, 2026-09-27, "Keep that line", PRD 32), so a quiet foot still
    /// says Ovation is checking.
    ///
    /// A RUNNING YEAR END EXPORT IS SAID HERE, as a live line counting its seconds,
    /// because the shell now always owns the window and the problems window that
    /// used to carry it is never shown beside a store. Its outcome arrives as a
    /// notice in this same foot when it ends.
    ///
    /// EACH OPEN THING ON ITS OWN LINE, by its short name with its own Read beside
    /// it, newest first, at most two, then "and N more" (Dan, 2026-09-26). No count:
    /// read and unread look the same, because a notice closes once read and what
    /// stays is a standing problem, open until its condition clears. The sentence is
    /// behind Read, in a popover anchored to it, so nothing else on screen moves and
    /// an open invoice stays open.
    @ViewBuilder
    private var status: some View {
        let lines = RailFoot.lines(for: problems.open)
        VStack(alignment: .leading, spacing: 5) {
                if let command = exportCommand, case .running = command.progress {
                    RunningExportView(command: command, onRail: true)
                }
                ForEach(lines.shown) { problem in
                    footLine(problem, named: lines.grouping.name(of: problem), in: lines.grouping)
                }
                if let more = RailFoot.moreSentence(lines.more) {
                    // A CONTROL LIKE READ (Dan, 2026-09-26): what it opens lists every
                    // open thing, so nothing past the first two is out of reach.
                    ActionWord(word: more, size: RailFoot.textSize,
                               press: { shell.readEverything() },
                               ground: .rail, spoken: "Read all \(problems.open.count) open")
                        .popover(isPresented: readingEverythingBinding, arrowEdge: .trailing) {
                            everything()
                        }
                }
                Text(RailFoot.onlyWhileOpen)
                    .font(.system(size: 11.5))
                    .foregroundStyle(OvationPalette.railDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, RailFoot.footPadding)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .overlay(alignment: .top) { Divider().overlay(OvationPalette.railStatusBorder) }
            .padding(.horizontal, RailFoot.footInset)
    }

    /// One open thing, with what its Read opens anchored to that Read.
    private func footLine(_ problem: Problem, named name: String,
                          in grouping: RailFoot.Grouping) -> some View {
        RailFootLine(name: name,
                     read: { shell.read(problem.id) },
                     isReading: readingBinding(problem.id),
                     reading: reading(for: problem, in: grouping))
    }

    /// Whether this line's popover is open. Clicking away closes it, which is not
    /// reading it: only "I have read this" marks it read.
    private func readingBinding(_ id: Problem.ID) -> Binding<Bool> {
        Binding(get: { shell.reading == id },
                set: { if !$0, shell.reading == id { shell.stopReading() } })
    }

    private var readingEverythingBinding: Binding<Bool> {
        Binding(get: { shell.readingEverything },
                set: { if !$0 { shell.stopReadingEverything() } })
    }

    /// What "and N more" opens: every open thing, newest first, each with its own
    /// "I have read this". Named for the same reason `reading(for:)` is.
    func everything() -> FootReadingList {
        FootReadingList(problems: problems, read: { problem in
            problems.acknowledge(problem.id, now: now())
        })
    }

    /// What Read opens for one problem, and what "I have read this" does. Named so a
    /// test can take the popover's content from the same place the popover does,
    /// since a popover is its own window and no view tree test reaches it.
    ///
    /// A LINE SHARED BY SEVERAL (ovation#609) reads every one of them and is read
    /// as a whole: "I have read this" marks each member read.
    func reading(for problem: Problem, in grouping: RailFoot.Grouping? = nil) -> FootReading {
        let members = (grouping ?? RailFoot.Grouping(problems.open)).members(of: problem)
        return FootReading(sentence: RailFoot.sentence(for: members), done: {
            for member in members { problems.acknowledge(member.id, now: now()) }
            shell.stopReading()
        })
    }

    // MARK: what you are standing on

    /// Hands one typed time to the writer, then builds the screen again from the
    /// store.
    ///
    /// IT RE-READS RATHER THAN EDITING WHAT IS ON SCREEN. The presenter holds
    /// values, so the derived duration, the line's amount, the totals and the
    /// Review refusal all change together or not at all, and they come from the
    /// same read (L14). Editing the screen in place would be a second derivation
    /// of the same facts.
    private func typed(_ shoot: PersistentIdentifier, _ edge: InvoiceScreenView.Edge,
                       _ time: ClockTime?) async {
        refusedWrite = await writeTime?(shoot, edge, time)
        if let openedInvoiceID { openedInvoice = openInvoice?(openedInvoiceID) }
        publishWhatIsOpen()
    }

    /// The same shape for the due date: write, then re-read, so the foot and
    /// everything derived from the date change together or not at all (L14).
    private func dated(_ due: BusinessDate) async {
        guard let openedInvoiceID else { return }
        refusedDate = await writeDueDate?(openedInvoiceID, due)
        openedInvoice = openInvoice?(openedInvoiceID)
        publishWhatIsOpen()
    }

    /// ovation#510. The payment controls the invoice screen asks for, or nil where
    /// this launch cannot record a payment AND clear a check. Both are asked for,
    /// because the controls offer both, and Mark cleared with nowhere to write
    /// would be a word that does nothing (L109).
    private var paymentControls: InvoiceScreenView.PaymentControls? {
        guard writePayment != nil, writeCleared != nil else { return nil }
        return InvoiceScreenView.PaymentControls(
            isOpen: payingIsOpen, isRecording: paymentIsRecording,
            refused: refusedPayment, refusedClearing: refusedClearing,
            open: { refusedPayment = nil; refusedClearing = nil; payingIsOpen = true },
            record: { entry in Task { await paid(entry) } },
            close: { payingIsOpen = false; refusedPayment = nil },
            markCleared: { check in Task { await cleared(check) } },
            edited: { refusedPayment = nil })
    }

    /// Records one payment, then re-reads the invoice, so the lines under the Total,
    /// the foot and the sheet all change together or not at all (L14). The sheet
    /// says Recording while the write is in flight and closes only on success; a
    /// refusal stays in the sheet, beside the Record it answers (L608).
    ///
    /// ovation#556, PRD 51o. ONCE RECORD IS PRESSED THE HISTORY OPENS WITH THE NEW
    /// PAYMENT MARKED. The new payment is whatever payment entry the re-read has that
    /// the screen before it did not, found by identity (L237); a refused press finds
    /// none and opens nothing.
    private func paid(_ entry: PaymentEntry) async {
        guard let openedInvoiceID, !paymentIsRecording else { return }
        let before = openedInvoice?.history.entries ?? []
        paymentIsRecording = true
        refusedPayment = await writePayment?(openedInvoiceID, entry)
        paymentIsRecording = false
        if refusedPayment == nil { payingIsOpen = false }
        openedInvoice = openInvoice?(openedInvoiceID)
        let recorded = InvoiceHistory.newlyRecorded(before: before,
                                                    after: openedInvoice?.history.entries ?? [])
        if refusedPayment == nil, !recorded.isEmpty {
            historyMarks = recorded
            historyIsOpen = true
        }
        publishWhatIsOpen()
    }

    /// ovation#556. The history pane's state and its one control.
    ///
    /// THE MARK LASTS UNTIL THE HISTORY IS CLOSED (PRD 51o), so a payment is not still
    /// marked new an hour of edits later.
    private var historyControls: InvoiceScreenView.HistoryControls {
        InvoiceScreenView.HistoryControls(
            isOpen: historyIsOpen, marked: historyMarks,
            toggle: {
                historyIsOpen.toggle()
                if !historyIsOpen { historyMarks = [] }
            })
    }

    /// ovation#185. The held money controls, or nil where nothing can write them.
    private var heldMoneyControls: InvoiceScreenView.HeldMoneyControls? {
        guard writeHeldMoney != nil else { return nil }
        return InvoiceScreenView.HeldMoneyControls(
            refused: refusedHeldMoney,
            apply: { invoice in Task { await movedHeldMoney(invoice, .apply) } },
            remove: { invoice in Task { await movedHeldMoney(invoice, .remove) } })
    }

    /// Puts held money on or takes it off, then re-reads the invoice, so the held
    /// money line, Outstanding, the foot and the sheet's starting amount all
    /// change together or not at all (L14).
    private func movedHeldMoney(_ invoice: PersistentIdentifier, _ change: HeldMoneyChange) async {
        refusedHeldMoney = await writeHeldMoney?(invoice, change)
        if let openedInvoiceID { openedInvoice = openInvoice?(openedInvoiceID) }
        publishWhatIsOpen()
    }

    /// Clears one check, then re-reads the invoice the same way.
    private func cleared(_ check: PersistentIdentifier) async {
        refusedClearing = await writeCleared?(check)
        if let openedInvoiceID { openedInvoice = openInvoice?(openedInvoiceID) }
        publishWhatIsOpen()
    }

    /// The same shape again for the tax status: write, then re-read, so the tax
    /// row, the total, the question itself and the Review refusal all change
    /// together or not at all (L14). This is the one write on this screen that
    /// changes a fact about the CLIENT, so everything derived from it moves at
    /// once and none of it is edited in place.
    private func answered(_ client: PersistentIdentifier, _ status: TaxStatus) async {
        refusedTax = await writeTaxStatus?(client, status)
        if let openedInvoiceID { openedInvoice = openInvoice?(openedInvoiceID) }
        publishWhatIsOpen()
    }

    /// The same shape again for a line: write, then re-read, so the row, the
    /// money block and the Review refusal all change together or not at all
    /// (L14).
    private func lined(_ type: PersistentIdentifier, _ amount: Money) async {
        guard let openedInvoiceID else { return }
        refusedLine = await writeLine?(openedInvoiceID, type, amount)
        openedInvoice = openInvoice?(openedInvoiceID)
        publishWhatIsOpen()
    }

    /// And for a new service type, which changes what the list offers rather
    /// than the invoice, so the screen is rebuilt for the same reason.
    private func madeType(_ name: String, _ usual: Money?) async {
        refusedLine = await writeServiceType?(name, usual)
        if let openedInvoiceID { openedInvoice = openInvoice?(openedInvoiceID) }
        publishWhatIsOpen()
    }

    /// The same shape again for the discount: write, then re-read, so the line,
    /// the taxable figure, the total and the Review refusal all change together
    /// or not at all (L14).
    /// ADDRESSED BY THE INVOICE THE DECISION WAS MADE ABOUT, never by whatever
    /// is open when the write lands. The menu presses on the invoice it was
    /// describing, and using the screen's own id instead would act on a
    /// different one if it had changed in between (L166).
    private func discounted(_ invoice: PersistentIdentifier, _ discount: Discount?) async {
        refusedLine = await writeDiscount?(invoice, discount)
        guard let openedInvoiceID, openedInvoiceID == invoice else { return }
        openedInvoice = openInvoice?(openedInvoiceID)
        discountSettled += 1
        publishWhatIsOpen()
    }

    /// The same shape again for the referral credit, which moves the client's
    /// balance as well as the invoice, so BOTH surfaces showing either have to be
    /// rebuilt from the store rather than from what this thought it wrote (L14).
    private func creditChanged(_ invoice: PersistentIdentifier,
                               _ change: ReferralCreditChange) async {
        refusedLine = await writeReferralCredit?(invoice, change)
        guard let openedInvoiceID, openedInvoiceID == invoice else { return }
        openedInvoice = openInvoice?(openedInvoiceID)
        publishWhatIsOpen()
    }

    /// Tells the Edit menu what it is looking at.
    ///
    /// PUBLISHED FROM THE ONE PLACE THE SCREEN IS BUILT, so the menu can never
    /// describe an invoice that is no longer on screen: every path that changes
    /// what is open goes through `openedInvoice` and then through here (L14).
    private func publishWhatIsOpen() {
        edits?.open = openedInvoice?.editMenuFacts
        // WHAT THE MENU DOES IS GIVEN HERE, because writing and then re-reading
        // the screen is the shell's job: a menu that only wrote would change the
        // store and leave the invoice on screen describing what it used to be
        // (L14).
        edits?.addDiscount = writeDiscount == nil ? nil : { invoice, discount in
            Task { await discounted(invoice, discount) }
        }
        // PUBLISHED IN THE SAME BREATH AS THE REST, which is what stops the menu
        // describing an invoice it cannot act on: this function is the only place
        // that says what is open, so an entry whose action was set anywhere else
        // would go stale the first time the screen changed (L14).
        edits?.applyReferralCredit = writeReferralCredit == nil ? nil : { invoice in
            Task { await creditChanged(invoice, .apply) }
        }
        edits?.removeReferralCredit = writeReferralCredit == nil ? nil : { invoice in
            Task { await creditChanged(invoice, .remove) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch shell.selected {
        case .roster:
            RosterPassView(presenter: roster)
        case .invoices:
            // THE SCREEN THE WINDOW OPENS ON (ovation#49). `RosterLaunch` selects
            // this whenever the roster has nothing to ask, which since ovation#298
            // is always, so this is the first thing Dan sees.
            //
            // A LIST THAT COULD NOT BE READ IS NOT AN EMPTY LIST. When the fetch
            // threw, `InvoiceListSource` raised a problem and produced nothing,
            // and the rail's status block carries it; drawing the empty state here
            // would say every invoice is paid and cleared, on no evidence (L10).
            // ovation#457. THE INVOICE TAKES THE WHOLE CONTENT AREA (round 1), so
            // the list goes away while it is open rather than sitting beside it.
            // Coming back to a list you recognise, with its scroll position and
            // the row that moved, is ovation#125.
            if let open = openedInvoice {
                InvoiceScreenView(
                    presenter: open,
                    close: {
                        openedInvoice = nil
                        openedInvoiceID = nil
                        payingIsOpen = false
                        refusedPayment = nil
                        refusedClearing = nil
                        refusedHeldMoney = nil
                        refusedResend = nil
                        historyIsOpen = false
                        historyMarks = []
                        publishWhatIsOpen()
                    },
                    setTime: writeTime == nil ? nil : { shoot, edge, time in
                        Task { await typed(shoot, edge, time) }
                    },
                    setDueDate: writeDueDate == nil ? nil : { due in
                        Task { await dated(due) }
                    },
                    refusedDate: refusedDate,
                    refused: refusedWrite,
                    answerTax: writeTaxStatus == nil ? nil : { client, status in
                        Task { await answered(client, status) }
                    },
                    refusedTax: refusedTax,
                    addLine: writeLine == nil ? nil : { type, amount in
                        Task { await lined(type, amount) }
                    },
                    createType: writeServiceType == nil ? nil : { name, usual in
                        Task { await madeType(name, usual) }
                    },
                    refusedLine: refusedLine,
                    setDiscount: writeDiscount == nil ? nil : { discount in
                        guard let openedInvoiceID else { return }
                        Task { await discounted(openedInvoiceID, discount) }
                    },
                    discountSettled: discountSettled,
                    payment: paymentControls,
                    heldMoney: heldMoneyControls,
                    review: reviewer == nil ? nil : { startReview() },
                    refusedReview: refusedReview,
                    resend: reviewer == nil ? nil : { kind in startResend(kind) },
                    refusedResend: refusedResend,
                    history: historyControls)
            } else if let invoices {
                InvoiceListView(presenter: invoices, heldMoney: heldMoney,
                                selected: $selectedInvoice,
                                open: openInvoice == nil ? nil : { id in
                                    openedInvoiceID = id
                                    openedInvoice = openInvoice?(id)
                                    publishWhatIsOpen()
                                },
                                settle: reviewer == nil ? nil : { id in askToSettle(id) },
                                review: reviewer == nil ? nil : { id in startReviewFromTheList(id) },
                                remind: reviewer == nil ? nil : { id in
                                    startReviewFromTheList(id, as: .reminder)
                                })
                    .confirmationDialog("Mark unsent?", isPresented: settlingIsAsked,
                                        presenting: settling) { asked in
                        Button("Mark unsent", role: .destructive) { settle(asked.invoiceID) }
                        Button("Cancel", role: .cancel) {}
                    } message: { asked in
                        Text(asked.consequence)
                    }
                    // RESERVED AT THE FOOT, never laid over the rows, so a refusal
                    // cannot cover the last one at the real count (L189).
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if let refusedOnTheList {
                            Text(refusedOnTheList)
                                .font(.system(size: 12.5))
                                .foregroundStyle(OvationPalette.ink)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityAddTraits(.isStaticText)
                        }
                    }
            } else {
                couldNotBeRead
            }
        case .clients:
            // ovation#568. A CLIENTS SCREEN THAT COULD NOT BE READ IS NOT AN EMPTY
            // ONE: it comes from the same read as the list, which raised a problem
            // for the failure, and drawing no names would say there are no clients.
            if let clients {
                ClientsView(presenter: clients, selected: $selectedClient,
                            writeTax: writeTaxStatus, writeTerm: writePaymentTerm,
                            acknowledgeShared: acknowledgeSharedAddress)
            } else {
                clientsCouldNotBeRead
            }
        case .expenses:
            // Reachable only from a test today, because `go(to:)` refuses an
            // unbuilt destination. It is drawn rather than left blank so that
            // the state has a sentence if it is ever reached (L10).
            VStack(alignment: .leading, spacing: 6) {
                Text(shell.selected.title)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(OvationPalette.ink)
                Text("This screen has not been built yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(OvationPalette.soft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .background(OvationPalette.background)
        }
    }

    /// The same state for the Clients screen, which comes from the same read.
    private var clientsCouldNotBeRead: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The clients could not be read")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(OvationPalette.ink)
            Text("No client's details can be seen or corrected until this is fixed. "
                 + "What went wrong is at the foot of the rail.")
                .font(.system(size: 13))
                .foregroundStyle(OvationPalette.soft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(OvationPalette.background)
    }

    /// The state where the store opened and its invoices did not come out of it.
    /// It names what cannot be done rather than only that something failed, and it
    /// points at the rail, where the problem itself is written (L11, L111).
    private var couldNotBeRead: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The invoices could not be read")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(OvationPalette.ink)
            Text("Nothing can be sent, chased or marked paid until this is fixed. "
                 + "What went wrong is at the foot of the rail.")
                .font(.system(size: 13))
                .foregroundStyle(OvationPalette.soft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(OvationPalette.background)
    }
}

/// ovation#99 and ovation#566. The foot of the rail's measurements and vocabulary, in
/// one place, because `RailFootTests` measures every short name against the same
/// column the view lays out.
enum RailFoot {
    /// The most open things named before the rest become "and N more".
    static let most = 2
    static let textSize: CGFloat = 12.5
    /// The space between a name and its Read, the design record's `gap: 8px`.
    static let gap: CGFloat = 8
    static let readWord = "Read"
    static let readIt = "I have read this"
    static let onlyWhileOpen = "Ovation only looks while it is open."

    /// The rail's own side padding, the foot's inset inside it, and the foot's
    /// padding inside its rule, each used by the view.
    static let railInset: CGFloat = 9
    static let footInset: CGFloat = 3
    static let footPadding: CGFloat = 9
    /// What a line has to itself: 166 points in a 208 point rail.
    static let column: CGFloat = OvationWindow.railWidth - 2 * (railInset + footInset + footPadding)

    struct Lines: Equatable {
        let shown: [Problem]
        let more: Int
        /// The grouping the lines were cut from, so a view names each line from the
        /// one pass rather than working it out again per line.
        let grouping: Grouping
    }

    /// Newest first, by when each was last raised, so a standing condition found
    /// again at this launch comes back to the top. A tie goes to the one recorded
    /// later. Problems that share one line (ovation#609) stand as their newest, and
    /// "and N more" counts lines, not problems.
    static func lines(for open: [Problem]) -> Lines {
        let grouping = Grouping(open)
        let newest = grouping.lines
        return Lines(shown: Array(newest.prefix(most)), more: max(newest.count - most, 0),
                     grouping: grouping)
    }

    /// Every line, newest first, each standing as its newest member: the foot's
    /// order and the list behind "and N more", which groups exactly as the foot does
    /// so two backups of one day are one entry there too.
    static func everyLine(for open: [Problem]) -> [Problem] { Grouping(open).lines }

    /// Every open problem on the same line as this one, newest first: itself alone
    /// unless its kind shares a line (ovation#609).
    static func members(of problem: Problem, among open: [Problem]) -> [Problem] {
        Grouping(open).members(of: problem)
    }

    /// What the open problems come to in the foot, worked out ONCE per render: each
    /// problem's name, which line it stands on, and each line's members (ovation#609).
    /// Names depend on what else is open, so asking per problem rescanned the whole
    /// list for every line drawn (L383, L471).
    struct Grouping: Equatable {
        /// One problem per line, newest first.
        let lines: [Problem]
        private let names: [Problem.ID: String]
        private let keys: [Problem.ID: String]
        private let membersByKey: [String: [Problem]]

        init(_ open: [Problem]) {
            var perKind: [ProblemKind: Int] = [:]
            for problem in open { perKind[problem.kind, default: 0] += 1 }
            var names: [Problem.ID: String] = [:]
            var keys: [Problem.ID: String] = [:]
            var members: [String: [Problem]] = [:]
            var lines: [Problem] = []
            for problem in RailFoot.newestFirst(open) {
                let name = problem.shortName(sharingKind: (perKind[problem.kind] ?? 0) > 1)
                // A kind that shares one line per name (ovation#609) is keyed by that
                // name; every other problem has a line of its own.
                let key = ProblemKind.sharingOneLine.contains(problem.kind)
                    ? "line:\(problem.kind.rawValue):\(name)" : "problem:\(problem.id)"
                names[problem.id] = name
                keys[problem.id] = key
                if members[key] == nil { lines.append(problem) }
                members[key, default: []].append(problem)
            }
            self.lines = lines
            self.names = names
            self.keys = keys
            self.membersByKey = members
        }

        /// What the foot calls this problem, the same as `Problem.shortName(among:)`.
        func name(of problem: Problem) -> String { names[problem.id] ?? problem.shortName }

        func members(of problem: Problem) -> [Problem] {
            keys[problem.id].flatMap { membersByKey[$0] } ?? [problem]
        }
    }

    /// What Read opens for a line: its one sentence, or each member's in turn, a
    /// broken backup's led by its time so two of one day are told apart (Dan,
    /// 2026-09-30).
    static func sentence(for members: [Problem]) -> String {
        guard members.count > 1 else { return members.first?.sentence ?? "" }
        return members.map { member in
            ProblemKind.archiveTime(member.subject).map { "Taken at \($0). \(member.sentence)" }
                ?? member.sentence
        }.joined(separator: "\n\n")
    }

    /// The one order the foot and the list behind "and N more" share.
    static func newestFirst(_ open: [Problem]) -> [Problem] {
        open.enumerated()
            .sorted { a, b in
                a.element.lastRaised != b.element.lastRaised
                    ? a.element.lastRaised > b.element.lastRaised
                    : a.offset > b.offset
            }
            .map(\.element)
    }

    /// Nothing at all when nothing is left over, because "and 0 more" is noise.
    static func moreSentence(_ more: Int) -> String? {
        more > 0 ? "and \(more) more" : nil
    }
}

/// One line of the foot: the short name, and Read at the line's right edge, where
/// every line's Read lines up, with what Read opens in a popover pointing at it.
///
/// ITS OWN VIEW SO ITS REAL WIDTH CAN BE MEASURED. The first build put a Spacer
/// between the name and Read inside a spaced stack, which spent the gap twice and
/// cut "2026 export written" short, while arithmetic over the name's width said it
/// fitted. `RailFootLineTests` lays this view out for every name and holds it to
/// the column.
struct RailFootLine: View {
    let name: String
    let read: () -> Void
    @Binding var isReading: Bool
    let reading: FootReading

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(name)
                .font(.system(size: RailFoot.textSize, weight: .bold))
                .foregroundStyle(OvationPalette.railFault)
                .lineLimit(1)
            Spacer(minLength: RailFoot.gap)
            ActionWord(word: RailFoot.readWord, size: RailFoot.textSize, press: read,
                       ground: .rail, spoken: "\(RailFoot.readWord): \(name)")
                .popover(isPresented: $isReading, arrowEdge: .trailing) { reading }
        }
    }
}

/// What Read opens: the whole sentence and "I have read this", on the page's paper,
/// in a popover pointing at Read. It sets its own appearance, because a popover is
/// its own window and does not inherit the screen's (PRD 43).
struct FootReading: View {
    let sentence: String
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sentence)
                .font(.system(size: 13))
                .foregroundStyle(OvationPalette.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            ActionWord(word: RailFoot.readIt, size: 13, press: done)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300, alignment: .leading)
        .background(OvationPalette.background)
        .ovationAppearance()
    }
}

/// What "and N more" opens: every open thing, newest first as the foot is, each with
/// its whole sentence and its own "I have read this". It reads the store as it draws,
/// so a notice read here leaves the list and a standing problem stays in it, exactly
/// as in the foot. Scrolls past a height, because the open list has no bound.
struct FootReadingList: View {
    @Bindable var problems: ProblemsStore
    let read: (Problem) -> Void

    var body: some View {
        let grouping = RailFoot.Grouping(problems.open)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(grouping.lines.enumerated()), id: \.element.id) { index, problem in
                    if index > 0 { Divider().overlay(OvationPalette.rule) }
                    let name = grouping.name(of: problem)
                    // ONE ENTRY PER FOOT LINE (ovation#609): a line shared by several
                    // reads each of them, and is read as a whole.
                    let members = grouping.members(of: problem)
                    VStack(alignment: .leading, spacing: 6) {
                        // Headed by the name the foot calls it, as the design record
                        // draws the list (rules/rail-foot.js, PRD 44f).
                        Text(name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(OvationPalette.ink)
                        Text(RailFoot.sentence(for: members))
                            .font(.system(size: 13))
                            .foregroundStyle(OvationPalette.ink)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        ActionWord(word: RailFoot.readIt, size: 13,
                                   press: { members.forEach(read) },
                                   spoken: "\(RailFoot.readIt): \(name)")
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
        }
        .frame(width: 320)
        .frame(maxHeight: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(OvationPalette.background)
        .ovationAppearance()
    }
}
