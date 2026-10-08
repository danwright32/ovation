import AppKit
import SwiftData
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#457, PRD 5.4. The row being filled in when a line is being added.
///
/// ITS STATE IS THE SCREEN'S, AND THAT IS WHY IT IS ITS OWN VIEW. A view tree
/// test cannot press a word on the invoice and then see what the screen's
/// `@State` did with it, so a row drawn from that state is a row nothing can
/// check (L442). Every state of it is a case here instead.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AddingLineRowTests {

    private static let columns: (hours: CGFloat, rate: CGFloat, amount: CGFloat,
                                 gap: CGFloat, side: CGFloat) = (66, 92, 96, 14, 24)

    private static let types = [
        PopupList.Choice(id: "Photography", says: "Photography"),
        PopupList.Choice(id: "Rush turnaround", says: "Rush turnaround"),
    ]

    private static func chosen(_ name: String, _ usually: Money?)
        -> InvoiceScreenPresenter.ServiceChoice {
        let context = ModelContext(try! OvationSchema.container(inMemory: true))
        let type = ServiceType(name: name, role: .ordinary, defaultUnitAmount: usually)
        context.insert(type)
        return InvoiceScreenPresenter.ServiceChoice(id: type.persistentModelID,
                                                    name: name, usually: usually)
    }

    private static func row(chosen: InvoiceScreenPresenter.ServiceChoice? = nil,
                            amount: String? = nil,
                            listIsOpen: Bool = false,
                            askNewType: (() -> Void)? = {},
                            choose: @escaping (PopupList.Choice) -> Void = { _ in },
                            commit: @escaping () -> Void = {},
                            escape: @escaping () -> Void = {}) -> AddingLineRow {
        var line = LineBeingAdded()
        if let chosen { line.choose(chosen) }
        if let amount { line.amount = amount }
        line.listIsOpen = listIsOpen
        return AddingLineRow(line: .constant(line), types: Self.types,
                             askNewType: askNewType, choose: choose, commit: commit,
                             escape: escape, columns: Self.columns)
    }

    private static func text(in view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    // MARK: before a type is chosen

    /// THE TYPE IS ASKED FOR FIRST, in the row's own description cell, which is
    /// the order the design record draws.
    @Test("a row with no type yet asks for one")
    func arowWithNoTypeAsksForOne() throws {
        let drawn = try Self.text(in: Self.row())

        #expect(drawn.contains("Choose a type"))
    }

    /// AND IT IS A CONTROL AT REST rather than on hover only (L49), so it is a
    /// button whether or not anybody is pointing at it.
    @Test("the type is a control, not a label")
    func thetypeIsAControl() throws {
        let pressable = try Self.row().inspect().findAll(ViewType.Button.self)

        #expect(pressable.count == 1)
    }

    // MARK: once it is chosen

    /// THE NAME TAKES THE QUESTION'S PLACE, because the question has been
    /// answered and a control still asking it reads as the answer not having
    /// landed (L152).
    @Test("a row with a type drawn shows its name and asks nothing")
    func arowWithATypeShowsItsName() throws {
        let view = Self.row(chosen: Self.chosen("Rush turnaround", Money(dollars: 150)))

        let drawn = try Self.text(in: view)

        #expect(drawn.contains("Rush turnaround"))
        #expect(!drawn.contains("Choose a type"))
    }

    /// AND THE NAME IS STILL THE CHOOSER (ovation#489, PRD 51t), so a type
    /// chosen by mistake is changed where it was chosen rather than by starting
    /// the line again. Rejected by Dan: plain text that reopens the list, which
    /// reads as a line already written.
    @Test("a chosen type stays a control that opens the list")
    func achosenTypeStaysTheChooser() throws {
        let view = Self.row(chosen: Self.chosen("Rush turnaround", Money(dollars: 150)))

        let chooser = try view.inspect().find(ViewType.Button.self)

        #expect(try chooser.labelView().find(text: "Rush turnaround").string() == "Rush turnaround")
        #expect(try chooser.accessibilityLabel().string() == "Type")
        #expect(try chooser.accessibilityValue().string() == "Rush turnaround")
    }

    /// PRESSING IT OPENS THE LIST, through the value the screen holds, so Escape
    /// can see it is open (PRD 51s).
    @Test("pressing the chooser opens the list on the line")
    func pressingTheChooserOpensTheList() throws {
        var line = LineBeingAdded()
        line.choose(Self.chosen("Rush turnaround", Money(dollars: 150)))
        let binding = Binding(get: { line }, set: { line = $0 })
        let view = AddingLineRow(line: binding, types: Self.types, askNewType: {},
                                 choose: { _ in }, commit: {}, escape: {},
                                 columns: Self.columns)

        try view.inspect().find(ViewType.Button.self).tap()

        #expect(line.listIsOpen)
    }

    // MARK: leaving it (ovation#489)

    /// ESCAPE IS HANDED TO THE SCREEN, which decides between the list and the
    /// line, because cancelling the line removes this row (PRD 51s).
    @Test("Escape on the row is handed to the screen")
    func escapeIsHandedOn() throws {
        var escaped = 0
        let view = Self.row(escape: { escaped += 1 })

        try view.inspect().find(AddingLineRow.self).hStack().callOnExitCommand()

        #expect(escaped == 1)
    }

    /// LEAVING THE FIELD COMMITS (PRD 51q), and leaving it for the row's own list
    /// does not, because that is Dan changing the type rather than leaving the
    /// line (PRD 51r).
    @Test("leaving the field commits, and leaving it for the open list does not",
          arguments: [false, true])
    func leavingTheField(listIsOpen: Bool) throws {
        var committed = 0
        let view = Self.row(chosen: Self.chosen("Rush turnaround", nil), amount: "75",
                            listIsOpen: listIsOpen, commit: { committed += 1 })

        try view.inspect().find(ViewType.TextField.self)
            .callOnChange(oldValue: true, newValue: false)

        #expect(committed == (listIsOpen ? 0 : 1))
    }

    /// THE SHADING REACHES 8 PAST THE COLUMNS ON EACH SIDE and the chosen type
    /// sits 8 inside it (Dan, 2026-09-29, PRD 51t). MEASURED ON THE DRAWN ROW,
    /// through the same camera the shot suites use, rather than read off the
    /// source, because the fault Dan objected to was only ever visible in a
    /// picture (L606): the chooser's edge touching the shaded row's.
    ///
    /// EACH COLOUR IS FOUND BY A SWATCH OF ITS TOKEN drawn through the same
    /// camera, never by its hex value, because the picture's colour space does not
    /// round trip (measured here: a hex match found no shading at all, which is
    /// what `MainWindowTitleTests` records too).
    @Test("the shading starts 8 before the column edge, and the chosen type starts on it")
    func theinsetIsEightOnTheDrawnRow() throws {
        let width: CGFloat = 700
        let size = CGSize(width: width, height: 60)
        let row = Self.row(chosen: Self.chosen("Rush turnaround", Money(dollars: 150)),
                           amount: "150.00")
            .frame(width: width)
            .background(OvationPalette.background)
        let drawn = try Self.picture(of: row, size: size)
        let swatches = try Self.picture(
            of: HStack(spacing: 0) { OvationPalette.sunk; OvationPalette.selection }
                .frame(width: width, height: size.height),
            size: size)
        let scale = CGFloat(drawn.pixelsWide) / width
        let middle = drawn.pixelsHigh / 2
        let sunk = Self.hex(swatches, x: Int(width / 4 * scale), y: middle)
        let selection = Self.hex(swatches, x: Int(width * 3 / 4 * scale), y: middle)

        /// The first point along the middle of the drawn row in `hex`.
        func firstPoint(in hex: String) -> CGFloat? {
            (0..<drawn.pixelsWide).first { Self.hex(drawn, x: $0, y: middle) == hex }
                .map { (CGFloat($0) / scale).rounded() }
        }

        let side = Self.columns.side
        let shading = firstPoint(in: sunk)
        let chosen = firstPoint(in: selection)
        #expect(shading == side - AddingLineRow.inset,
                "the shading starts at \(String(describing: shading)), not 8 before the column edge")
        #expect(chosen == side,
                "the chosen type starts at \(String(describing: chosen)), not on the column edge the other lines use")
    }

    /// What the shot suites' camera draws for a view, read back from the picture
    /// it writes.
    private static func picture(of view: some View, size: CGSize) throws -> NSBitmapImageRep {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "adding-row-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        try OffscreenShot.capture(view, size: size, scheme: .light, to: file)
        return try #require(NSBitmapImageRep(data: try Data(contentsOf: file)))
    }

    /// A pixel's components as the picture holds them, NOT CONVERTED, as hex.
    private static func hex(_ bitmap: NSBitmapImageRep, x: Int, y: Int) -> String {
        guard let c = bitmap.colorAt(x: x, y: y) else { return "none" }
        return String(format: "%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    /// THE HOURS AND THE RATE STAY BLANK. A flat charge has neither, and a
    /// quantity of nothing is not drawn, which is the rule the rows above this
    /// one already keep (PRD 5.1b). Asked before a type and after one, because
    /// the row now draws the same cells in both.
    @Test("the hours and the rate are drawn as nothing, not as zero")
    func thehoursAndRateAreBlank() throws {
        for view in [Self.row(), Self.row(chosen: Self.chosen("Rush turnaround", nil))] {
            let drawn = try Self.text(in: view)

            #expect(!drawn.contains("0"))
            #expect(!drawn.contains("0.00"))
        }
    }

    // MARK: the amount

    /// THE FIELD IS WHAT IT WAS GIVEN, so a prefilled amount is drawn and an
    /// empty one is empty. `LineBeingAdded.prefill` is what decides which.
    @Test("the amount field shows what it was given")
    func theamountFieldShowsWhatItWasGiven() throws {
        let view = Self.row(chosen: Self.chosen("Rush turnaround", Money(dollars: 150)),
                            amount: "150.00")

        let field = try view.inspect().find(ViewType.TextField.self)

        #expect(try field.input() == "150.00")
    }

    /// AND IT HAS NO PLACEHOLDER READING 0.00, which the design record states and
    /// PRD 5.1b gives the reason for: a zero total is a legitimate comped invoice,
    /// so a figure the screen has not been given is never drawn as one.
    @Test("an empty amount field offers no zero of its own")
    func anemptyAmountOffersNoZero() throws {
        let view = Self.row(chosen: Self.chosen("Rush turnaround", nil))

        let field = try view.inspect().find(ViewType.TextField.self)

        #expect(try field.input() == "")
        #expect(try Self.text(in: view).allSatisfy { !$0.contains("0.00") })
    }

    /// A FIELD THAT DOES NOTHING ON ENTER IS A FIELD THAT LOST WHAT WAS TYPED, so
    /// the row commits on submit.
    @Test("submitting the amount commits the row")
    func submittingtheAmountCommits() throws {
        var committed = 0
        let view = Self.row(chosen: Self.chosen("Rush turnaround", nil),
                            commit: { committed += 1 })

        try view.inspect().find(ViewType.TextField.self).callOnSubmit()

        #expect(committed == 1)
    }
}
