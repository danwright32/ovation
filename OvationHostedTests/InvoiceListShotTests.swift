// ovation#450. A picture of the invoice list at its real population, so which
// words are offered as controls can be judged by looking rather than described.
//
// IT IS THE FIRST SCREEN THE APP OPENS ON (`RosterLaunch.presenters` selects
// `.invoices`, and since ovation#298 the roster never has anything to ask), and
// there was no picture of it anywhere. A change to how eleven rows END is the
// change that a two row fixture and a green suite would both let through (L606).
//
// SAME CAMERA AS THE OTHER SHOT SUITES, so a fourth copy of the window handling
// does not exist to disagree with them.
//
// ONE THEME, AND THE OTHER IS ASSERTED TO MATCH IT, which is the recorded
// decision rather than a shortcut: `OvationPalette`'s own header says there is no
// dark half, because Dan's Mac is dark and he accepted a bright window. So the
// dark capture goes to a throwaway and is compared byte for byte, which makes the
// claim real in a way two identical filed pictures never could (L1).
//
// AT THE REAL POPULATION, thirteen rows rather than two: drafts waiting on their
// times, two priced drafts, an invoice whose send could not be settled, sent
// invoices still open, and two checks waiting to clear, one of them late
// (ovation#546), with Cedar Hill holding 500.00 against four open invoices so the
// held money band leads. TWO OF THOSE FOUR ARE THE PRICED DRAFTS, which are Cedar
// Hill's: since ovation#453 a draft counts as an open invoice (PRD 14j), so they
// are drawn in the band offering `Use it here`, not among the drafts to send.
// It does NOT carry every one of the eight action words, and that is stated
// rather than implied, and asserted below: `Remind` needs an overdue invoice and
// none is in this fixture, and `Send` needs a priced draft whose client holds no
// money, and none is either. What it does carry is one word of each KIND, a live
// one and two with nowhere to go, which is what this picture is for (L11).
//
// OPT IN, AND IT SAYS WHEN IT DID NOTHING (L98).
import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import Ovation

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct InvoiceListShotTests {

    private static var outputDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        let named = environment["OVATION_SHOT_DIR"]
            ?? environment["TEST_RUNNER_OVATION_SHOT_DIR"] ?? ""
        return named.isEmpty ? nil : URL(fileURLWithPath: named)
    }

    @Test("the invoice list is captured at its real count, and dark draws the same")
    func capturetheList() throws {
        guard let directory = Self.outputDirectory else {
            print("INVOICE LIST SHOTS: no TEST_RUNNER_OVATION_SHOT_DIR, so nothing was captured.")
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let context = ModelContext(try OvationSchema.container(inMemory: true))
        // BUILT ONCE. It was built twice, once for the invoices and once for the
        // held money, so the money was held by a SECOND Cedar Hill that owned
        // none of the invoices drawn, and the held money band this picture claims
        // to show was never in it (L1).
        let population = Self.population(context)
        let presenter = InvoiceListPresenter(
            invoices: population.invoices, heldMoney: population.held, today: Self.today)
        let view = InvoiceListView(presenter: presenter, heldMoney: "500.00",
                                   selected: .constant(nil), open: { _ in }, settle: { _ in }, review: { _ in })

        let file = directory.appending(path: "invoice-list.png")
        try OffscreenShot.capture(view, size: Self.windowSize, scheme: .light, to: file)
        let darkFile = directory.appending(path: "dark-check-invoice-list.png")
        try OffscreenShot.capture(view, size: Self.windowSize, scheme: .dark, to: darkFile)
        let light = try Data(contentsOf: file)
        let dark = try Data(contentsOf: darkFile)
        try FileManager.default.removeItem(at: darkFile)

        #expect(light == dark,
                "the list draws differently in dark, so something on it takes a colour from the system rather than from OvationPalette")
        // THE PICTURE IS OF SOMETHING, asserted rather than assumed: a capture of
        // an empty list would be a file nobody looks at twice (L98).
        // AND AT THE HALF SCREEN MINIMUM (ovation#110), where the shoot goes under
        // the client, which is the shape Dan works at and the one to look at.
        let half = directory.appending(path: "invoice-list-half-screen.png")
        try OffscreenShot.capture(view, size: Self.halfScreenSize, scheme: .light, to: half)
        #expect(FileManager.default.fileExists(atPath: half.path))

        let rows = presenter.bands.flatMap { $0.rows }
        #expect(rows.count == 13, "the population is \(rows.count) rows, not the real thirteen")
        // ovation#546: the late check LEADS the invoices that need Dan, under the
        // held money band, and the recent one keeps its place among the checks.
        #expect(Array(presenter.bands.map(\.band).prefix(2))
                == [.toPlace, .checkNotClearedAfterSevenDays])
        #expect(presenter.bands.contains { $0.band == .checkNotCleared })
        // ovation#453, ovation#656: what the header says this picture holds, held
        // here rather than only written. It said the priced drafts were drawn as
        // drafts to send after they had joined the held money band.
        let place = try #require(presenter.bands.first { $0.band == .toPlace })
        #expect(Set(place.rows.map(\.shoot))
                == ["Winter Gala", "Advent Carols", "Spring Series", "Summer Proms"])
        #expect(!rows.contains { $0.action == InvoiceListPresenter.Action.send })
        #expect(!rows.contains { $0.action == InvoiceListPresenter.Action.remind })

        // ovation#449: A SEARCH, and a search that finds nothing, each in both
        // appearances, dark asserted to draw the same as light.
        presenter.query = "Cedar Hill"
        #expect(presenter.shown.flatMap(\.rows).count == 6,
                "the search found \(presenter.shown.flatMap(\.rows).count) rows, not Cedar Hill's six")
        try Self.captureBoth(view, named: "invoice-list-search", in: directory)
        presenter.query = "Westfield"
        #expect(presenter.shown.isEmpty)
        try Self.captureBoth(view, named: "invoice-list-search-no-match", in: directory)
        presenter.query = ""
        print("INVOICE LIST SHOTS: wrote \(file.lastPathComponent) into \(directory.path)")
    }

    /// Captures one picture in light, and a throwaway in dark that must match it.
    private static func captureBoth(_ view: InvoiceListView, named name: String,
                                    in directory: URL) throws {
        let file = directory.appending(path: "\(name).png")
        try OffscreenShot.capture(view, size: windowSize, scheme: .light, to: file)
        let darkFile = directory.appending(path: "dark-check-\(name).png")
        try OffscreenShot.capture(view, size: windowSize, scheme: .dark, to: darkFile)
        let light = try Data(contentsOf: file)
        let dark = try Data(contentsOf: darkFile)
        try FileManager.default.removeItem(at: darkFile)
        #expect(light == dark, "\(name) draws differently in dark")
    }

    /// 2026-11-12, pinned so a picture taken today and one taken next week are the
    /// same picture (L130).
    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)
    private static let today = BusinessDate.stamping(noon)

    private static func day(_ offset: Int) -> BusinessDate {
        .stamping(noon.addingTimeInterval(Double(offset) * 86_400))
    }

    /// THE SAME POPULATION `InvoiceListViewTests` DRIVES, rebuilt here rather
    /// than shared, because that suite's fixture is private to it and a picture
    /// that quietly stopped matching what the cases assert would be worse than
    /// two fixtures that are each stated. The count is asserted above, so a
    /// divergence shows.
    private static func population(_ context: ModelContext)
        -> (invoices: [Invoice], held: [Client: Money]) {
        func client(_ name: String) -> Client {
            let made = Client(name: name, taxStatus: .notExempt)
            context.insert(made)
            return made
        }
        func invoice(_ owner: Client, _ shoot: String, on day: BusinessDate,
                     hours: Hours?, number: Int64? = nil) -> Invoice {
            let made = Invoice(client: owner, kind: .photography, invoiceDate: day,
                               hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
            made.dueDate = Self.day(14)
            context.insert(made)
            let event = Shoot(name: shoot, when: .dayOnly(day), venue: "St Anne's")
            made.add(event)
            let line = LineItem.hourly(hours: hours ?? Hours(whole: 1),
                                       at: Money(dollars: 250),
                                       describedAs: "Photography", for: event)
            if hours == nil { line.hours = nil }
            made.add(line)
            made.number = number
            return made
        }

        let cedar = client("Cedar Hill Youth Orchestra")
        let ashgrove = client("Ashgrove Chamber Players")
        let marlowe = client("Marlowe Early Music")

        var all: [Invoice] = []
        // Drafts waiting on the times, which is what ovation#461 makes.
        all.append(invoice(cedar, "Autumn Evensong", on: day(0), hours: nil))
        all.append(invoice(ashgrove, "A rehearsal shoot", on: day(-2), hours: nil))
        all.append(invoice(marlowe, "Candlemas", on: day(-5), hours: nil))
        // Cedar Hill's two priced drafts, drawn in the held money band offering
        // `Use it here` (see the header), not among the drafts to send.
        for (index, name) in ["Winter Gala", "Advent Carols"].enumerated() {
            let ready = invoice(cedar, name, on: day(-8 - index), hours: Hours(whole: 2))
            ready.orderedShoots.first?.shotFrom = ClockTime("19:00")
            ready.orderedShoots.first?.shotUntil = ClockTime("21:00")
            all.append(ready)
        }
        // Sent 40 days ago, and NOT overdue: every invoice here is due on day 14.
        for (index, name) in ["Epiphany Recital", "New Year Concert"].enumerated() {
            let sent = invoice(ashgrove, name, on: day(-40 - index), hours: Hours(whole: 3),
                               number: Int64(1_030 + index))
            sent.recordSendState(.sent(route: .ovationSentIt,
                                    at: noon.addingTimeInterval(Double(-40 - index) * 86_400)))
            all.append(sent)
        }
        // Sent, not yet due.
        let recent = invoice(marlowe, "Lenten Vespers", on: day(-3), hours: Hours(whole: 1),
                             number: 1_032)
        recent.recordSendState(.sent(route: .ovationSentIt, at: noon.addingTimeInterval(-3 * 86_400)))
        all.append(recent)
        // A send Ovation could not settle.
        let unknown = invoice(cedar, "Choral Evensong", on: day(-6), hours: Hours(whole: 2),
                              number: 1_033)
        unknown.recordSendState(.couldNotDetermine(checkedAt: noon.addingTimeInterval(-6 * 86_400)))
        all.append(unknown)
        // Two more open invoices for the client holding money.
        for (index, name) in ["Spring Series", "Summer Proms"].enumerated() {
            let open = invoice(cedar, name, on: day(-20 - index), hours: Hours(whole: 2),
                               number: Int64(1_034 + index))
            open.recordSendState(.sent(route: .ovationSentIt,
                                    at: noon.addingTimeInterval(Double(-20 - index) * 86_400)))
            all.append(open)
        }

        // ovation#546. Two checks waiting to clear: one recorded 9 days ago, which
        // leads the list, and one recorded 3 days ago, which keeps its place.
        let saints = client("Saint Anne's Chamber Series")
        let linden = client("Linden Park Brass")
        for (owner, name, recorded, number) in [(saints, "Advent Vespers", -9, Int64(1_028)),
                                                (linden, "Summer serenade", -3, Int64(1_036))] {
            let paid = invoice(owner, name, on: day(-30), hours: Hours(whole: 4), number: number)
            paid.recordSendState(.sent(route: .ovationSentIt, at: noon.addingTimeInterval(-30 * 86_400)))
            let payment = Payment(client: owner, amount: paid.total, method: .check,
                                  receivedOn: day(recorded))
            context.insert(payment)
            let allocation = PaymentAllocation(payment: payment, invoice: paid, amount: paid.total,
                                               allocatedOn: day(recorded),
                                               source: .recordedWithThePayment)
            context.insert(allocation)
            paid.allocations.append(allocation)
            payment.allocations.append(allocation)
            all.append(paid)
        }

        return (all, [cedar: Money(dollars: 500)])
    }

    /// The settled shell's content area, from the design record.
    private static let windowSize = CGSize(width: 856, height: 620)
    /// The content area of the narrowest window, beside the rail (ovation#110).
    private static let halfScreenSize = CGSize(
        width: OvationWindow.minimumWidth - OvationWindow.railWidth, height: 900)
}
