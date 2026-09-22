// ovation#457. Pictures of the invoice screen, so it can be judged by being
// looked at rather than described.
//
// SAME CAMERA AS THE OTHER TWO SHOT SUITES (ovation#318 B7, ovation#319), so a
// third copy of the window handling does not exist to disagree with them.
//
// ONE THEME, AND THE OTHER IS ASSERTED TO MATCH IT, which is not the usual rule
// and is the recorded decision rather than a shortcut. `OvationPalette`'s own
// header records it: there is no dark half, because Dan's Mac is set to dark and
// he accepted a bright window. So capturing both themes and filing two pictures
// would file the SAME picture twice while implying a comparison that cannot
// differ, which is worse than one picture (L606's reason, not its letter).
//
// SO THE SECOND CAPTURE IS A GUARD INSTEAD. It takes the dark one and asserts it
// is byte for byte the light one. That makes the claim real: the day a system
// colour or a material leaks onto this screen, the two diverge and this says so,
// which is exactly what a pair of identical files could never do (L1).
//
// MORE THAN ONE STATE, EVERY TIME. The states that matter are the ones no
// ordinary fixture produces: an invoice waiting on a time, and one carrying a
// credit and a discount at once, which is where the money block is longest and
// the columns have the most to line up.
//
// AT THE REAL SHAPE, not a two row fixture. A one line invoice is the commonest
// case and it is drawn, but so is a three line one, because the column widths
// exist to keep figures lined up down a page and one row cannot show that (L606,
// L578).
//
// OPT IN, AND IT SAYS WHEN IT DID NOTHING (L98).
import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Ovation

@MainActor
struct InvoiceScreenShotTests {

    private static var outputDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        let named = environment["OVATION_SHOT_DIR"]
            ?? environment["TEST_RUNNER_OVATION_SHOT_DIR"] ?? ""
        return named.isEmpty ? nil : URL(fileURLWithPath: named)
    }

    /// 2026-11-12, pinned so a picture taken today and one taken next week are the
    /// same picture (L130).
    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let today = BusinessDate.stamping(noon)

    @Test("the invoice screen is captured, and dark draws the same, or it says it captured nothing")
    func capturetheScreen() throws {
        guard let directory = Self.outputDirectory else {
            print("INVOICE SCREEN SHOTS: no TEST_RUNNER_OVATION_SHOT_DIR, so nothing was captured.")
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var written: [String] = []
        for state in State.allCases {
            let presenter = try Self.presenter(for: state)
            let file = directory.appending(path: "invoice-\(state.rawValue).png")
            try OffscreenShot.capture(
                // A REAL SETTER, so the time fields are drawn as the controls they
                // will be rather than as the plain text a nil setter draws. The
                // picture exists to show what Dan will meet.
                InvoiceScreenView(presenter: presenter, close: {},
                                  setTime: { _, _, _ in },
                                  answerTax: { _, _ in }, review: {}),
                size: Self.windowSize, scheme: .light, to: file)
            written.append(file.lastPathComponent)

            // THE GUARD. The dark capture goes to a throwaway and is compared,
            // never filed beside the light one: two identical files read as a
            // comparison somebody made, and nobody made it.
            let darkFile = directory.appending(path: "dark-check-\(state.rawValue).png")
            try OffscreenShot.capture(
                InvoiceScreenView(presenter: presenter, close: {},
                                  setTime: { _, _, _ in },
                                  answerTax: { _, _ in }, review: {}),
                size: Self.windowSize, scheme: .dark, to: darkFile)
            let light = try Data(contentsOf: file)
            let dark = try Data(contentsOf: darkFile)
            try FileManager.default.removeItem(at: darkFile)
            #expect(light == dark,
                    "\(state.rawValue) draws differently in dark, so something on this screen takes a colour from the system rather than from OvationPalette, whose header records that there is no dark half")
        }
        // THE COUNT IS ASSERTED, so a capture that silently wrote fewer than it
        // meant to is a failure rather than a shorter set nobody counts.
        #expect(written.count == State.allCases.count)
        print("INVOICE SCREEN SHOTS: wrote \(written.count) into \(directory.path)")
    }

    /// The states worth photographing, named rather than numbered.
    enum State: String, CaseIterable {
        /// One shoot, one line, nothing outstanding. The commonest invoice.
        case ordinary
        /// Three lines, a referral credit and a discount, which is where the money
        /// block is longest and the columns have the most to keep lined up.
        case theBusiestItGets
        /// Waiting on the time the shoot ended, which is the ordinary state of
        /// every draft (Dan, 2026-09-08) and the one the foot's refusal is for.
        case waitingOnATime
        /// A draft that took a number at Review and was never sent, so it holds
        /// that number until it is sent or closed (PRD 10c, ovation#411). No
        /// ordinary fixture produces it, and until this it had no surface at all.
        case holdingANumber
        /// The client's tax status was never recorded, which is 25 of Dan's 31
        /// real clients as the roster pass found them (ovation#298). The money
        /// block asks the question instead of drawing a tax figure and a total
        /// nobody has decided, and the two answers are in it.
        case waitingOnTheTaxStatus
    }

    private static func presenter(for state: State) throws -> InvoiceScreenPresenter {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let client = Client(name: "Cedar Hill Youth Orchestra",
                            taxStatus: state == .waitingOnTheTaxStatus
                                ? .neverRecorded : .notExempt)
        client.email = "booker@example.com"
        context.insert(client)
        let invoice = Invoice(client: client, kind: .photography, invoiceDate: today,
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity)
        invoice.dueDate = .stamping(noon.addingTimeInterval(14 * 86_400))
        context.insert(invoice)

        let shoot = Shoot(name: "Autumn Evensong", when: .dayOnly(today), venue: "St Anne's")
        shoot.shotFrom = ClockTime("19:00")
        if state != .waitingOnATime { shoot.shotUntil = ClockTime("20:30") }
        if state == .holdingANumber { invoice.number = 1_123 }
        invoice.add(shoot)

        // A REAL DRAFT HAS ITS SHOOT AND NO PRICED LINE. PRD 3c: "A drafted
        // invoice carries NO duration, and cannot be sent until Dan supplies one.
        // Until then it has no hours and no amount." The row is drawn from the
        // SHOOT, with a word where the amount would be (round 3).
        if state != .waitingOnATime {
            invoice.add(LineItem.hourly(hours: shoot.billedHours ?? Hours(whole: 1),
                                        at: Money(dollars: 250),
                                        describedAs: "Photography", for: shoot))
        }
        if state == .theBusiestItGets {
            invoice.add(LineItem.flat(Money(dollars: 150), describedAs: "Rush turnaround"))
            invoice.add(LineItem.flat(Money(dollars: 75), describedAs: "Preview images"))
            invoice.referralCredit = ReferralCredit(hours: Hours(whole: 1),
                                                    at: invoice.hourlyRate, earnedFrom: nil)
            invoice.discount = Discount(dollars: Money(dollars: 50))
        }
        return InvoiceScreenPresenter(invoice: invoice, footer: .fixed, today: today)
    }

    /// THE WINDOW'S OWN SIZE, from the design record: the invoice screen holds the
    /// window at 560px high rather than growing it, because an ordinary invoice is
    /// one line and a taller window is empty space that pushes the screen below
    /// the fold on a laptop. The width is the settled 1120px shell's content area
    /// less its rail.
    private static let windowSize = CGSize(width: 856, height: 560)
}
