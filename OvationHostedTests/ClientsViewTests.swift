import AppKit
import SwiftData
import SwiftUI
import Testing
import ViewInspector
@testable import Ovation

/// ovation#568 and ovation#482. The Clients screen, drawn, at the real count.
///
/// THE POPULATION IS THE DESIGN RECORD'S 31 CLIENTS (docs/design/clients.html),
/// every name invented there, with its shapes: three holding money (one of them
/// by two arrivals), four with referral credit, one sending invoices elsewhere,
/// one address that is not an address, one field carrying two, and two sharing an
/// address. What the rules decide is `ClientsPresenterTests`; this is what a
/// person sees (L442, L606).
@MainActor
struct ClientsViewTests {

    static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    static let names = [
        "Ashgrove Chamber Players", "Bellweather Dance Collective", "Brackenridge Youth Orchestra",
        "Calder Street Theatre", "Cormorant Bay Singers", "Drayton Wind Ensemble",
        "Eastvale Opera Workshop", "Fenwick Early Music Society", "Gallowmere Brass Band",
        "Harborlight Ballet", "Inglenook Jazz Collective", "Juniper Row Playhouse",
        "Kestrel Lane Quartet", "Larkspur Community Chorus", "Marisol Okonkwo-Reyes",
        "Marrowbone Percussion Group", "Nettlefield Baroque Consort", "Orchard Hill Symphonia",
        "Pennywhistle Folk Circle", "Priya Raghunathan", "Quillon Contemporary Dance",
        "Redbourne Light Opera", "Saltmarsh String Orchestra", "Thistledown Puppet Theatre",
        "Tobias Fenn", "Underhill Gospel Choir", "Vesper Lane Chamber Society",
        "Westfield Choral Society", "Wrenfield Academy of Dance", "Yarrow Street Collective",
        "Zephyr Hall Concerts",
    ]

    /// The 31, in memory, and the client whose page the pictures open on.
    static func population() throws -> (clients: [Client], context: ModelContext) {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        var byName: [String: Client] = [:]
        for name in names {
            let client = Client(name: name, taxStatus: .exempt)
            client.email = name.lowercased().filter(\.isLetter).prefix(18) + "@client.example"
            context.insert(client)
            byName[name] = client
        }
        func day(_ key: String) throws -> BusinessDate { try #require(BusinessCalendar.day(forKey: key)) }

        let harborlight = try #require(byName["Harborlight Ballet"])
        harborlight.taxStatus = .notExempt
        harborlight.email = "studio@harborlightballet.example"
        harborlight.contractEmail = "treasurer@harborlightballet.example"
        byName["Calder Street Theatre"]?.taxStatus = .notExempt
        byName["Zephyr Hall Concerts"]?.taxStatus = .notExempt
        byName["Bellweather Dance Collective"]?.taxStatus = .neverRecorded
        byName["Pennywhistle Folk Circle"]?.email = "ask at the box office"
        byName["Thistledown Puppet Theatre"]?.email = "puppets@thistledownpt.example, admin@thistledownpt.example"
        byName["Drayton Wind Ensemble"]?.email = "office@draytonarts.example"
        byName["Eastvale Opera Workshop"]?.email = "office@draytonarts.example"

        // Four invoices for Harborlight, three sent under Not exempt and a draft.
        let shoots = [("1131", "Autumn gala", "2026-11-14", 1_000), ("1126", "Studio portraits", "2026-10-02", 750),
                      ("1119", "Spring showcase", "2026-05-18", 1_250), ("", "Winter matinee", "2026-12-09", 625)]
        var paid: Invoice?
        for (number, shoot, key, dollars) in shoots {
            let invoice = Invoice(client: harborlight, kind: .photography, invoiceDate: try day(key),
                                  hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
            context.insert(invoice)
            invoice.number = Int64(number)
            invoice.add(Shoot(name: shoot, when: nil, venue: nil))
            invoice.add(LineItem.flat(Money(dollars: Int64(dollars)), describedAs: shoot))
            if !number.isEmpty { invoice.recordSendState(.sent(route: .ovationSentIt, at: noon)) }
            if number == "1126" { paid = invoice }
        }
        // Held money: Harborlight by two arrivals, Ashgrove and Zephyr by one each.
        let deposit = Payment(client: harborlight, amount: Money(dollars: 1_000), method: .zelle,
                              receivedOn: try day("2026-09-03"))
        context.insert(deposit)
        let over = Payment(client: harborlight, amount: Money(cents: 106_656), method: .check,
                           receivedOn: try day("2026-10-02"))
        context.insert(over)
        let settled = try #require(paid)
        let allocation = PaymentAllocation(payment: over, invoice: settled, amount: settled.total,
                                           allocatedOn: over.receivedOn, source: .recordedWithThePayment)
        context.insert(allocation)
        over.allocations.append(allocation)
        for (name, cents, key) in [("Ashgrove Chamber Players", Int64(50_000), "2026-08-28"),
                                    ("Zephyr Hall Concerts", Int64(8_750), "2026-08-14")] {
            context.insert(Payment(client: byName[name], amount: Money(cents: cents), method: .zelle,
                                   receivedOn: try day(key)))
        }
        // Referral credit on four.
        for (name, quarters) in [("Fenwick Early Music Society", Int64(10)), ("Harborlight Ballet", 12),
                                 ("Marisol Okonkwo-Reyes", 16), ("Orchard Hill Symphonia", 4)] {
            let client = try #require(byName[name])
            let entry = ReferralLedgerEntry(client: client, hours: Hours(quarters: quarters),
                                            occurredOn: .stamping(noon), earnedFromBookingKey: nil, note: nil)
            context.insert(entry)
            client.referralEntries.append(entry)
        }
        try context.save()
        return (try context.fetch(FetchDescriptor<Client>()), context)
    }

    static func id(of name: String, in clients: [Client]) throws -> UUID {
        try #require(clients.first { $0.name == name }).id
    }

    private static func text(in view: some View) throws -> [String] {
        try view.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
    }

    @Test("every one of the 31 names is drawn, and the toolbar counts them once")
    func all31AreDrawn() throws {
        let (clients, _) = try Self.population()
        let view = ClientsView(presenter: ClientsPresenter(clients: clients), selected: .constant(nil))

        let drawn = try Self.text(in: view)
        for name in Self.names { #expect(drawn.contains(name), "\(name) is not on the screen") }
        #expect(drawn.filter { $0 == "31 clients" }.count == 1)
    }

    @Test("the open client's page draws its facts, both boxes and its invoices")
    func thepageDrawsItsFacts() throws {
        let (clients, _) = try Self.population()
        let harborlight = try Self.id(of: "Harborlight Ballet", in: clients)
        let view = ClientsView(presenter: ClientsPresenter(clients: clients),
                               selected: .constant(harborlight), writeTax: { _, _ in nil })

        let drawn = try Self.text(in: view)
        #expect(drawn.contains("treasurer@harborlightballet.example"))
        #expect(drawn.contains("studio@harborlightballet.example"), "who booked, since it differs")
        #expect(drawn.contains("Not exempt"))
        #expect(drawn.contains("14 days"))
        #expect(drawn.contains("Deposit received 3 Sep"))
        #expect(drawn.contains("3.0 hrs"))
        #expect(drawn.contains("Autumn gala"))
        #expect(drawn.contains("Draft"))
        #expect(drawn.filter { $0 == "$1,250.00" }.isEmpty == false)
    }

    /// THE QUESTION IS ASKED BEFORE A RECORDED STATUS CHANGES, with the count taken
    /// from the page's own invoices (PRD 51j1). Drawn from the state the presses
    /// leave, which `ClientPageInteractionTests` drives.
    @Test("a change to a recorded status draws the question and its two words")
    func thequestionIsDrawn() throws {
        let (clients, _) = try Self.population()
        let harborlight = try Self.id(of: "Harborlight Ballet", in: clients)
        let presenter = ClientsPresenter(clients: clients)
        var state = ClientPageInteraction()
        _ = state.pressAnswer(.exempt, on: try #require(presenter.pages[harborlight]))
        let view = ClientsView(presenter: presenter, selected: .constant(harborlight),
                               writeTax: { _, _ in nil }, interaction: state)

        let drawn = try Self.text(in: view)
        #expect(drawn.contains("3 invoices already sent to this client were charged sales tax, and stay "
                               + "as they were sent. Drafts and every invoice from now on will be Exempt."))
        #expect(drawn.contains("Change to Exempt"))
        #expect(drawn.contains("Keep Not exempt"))
    }

    /// Review of ovation#600 (L20). A value that opens something says to VoiceOver
    /// whether it is open, since the chips appearing beside it are otherwise silent.
    @Test("the Sales tax value says to VoiceOver whether its answers are showing")
    func thevalueSaysWhetherItIsOpen() throws {
        let (clients, _) = try Self.population()
        let harborlight = try Self.id(of: "Harborlight Ballet", in: clients)
        let presenter = ClientsPresenter(clients: clients)
        func value(_ state: ClientPageInteraction) throws -> String? {
            let view = ClientsView(presenter: presenter, selected: .constant(harborlight),
                                   writeTax: { _, _ in nil }, writeTerm: { _, _ in nil },
                                   interaction: state)
            let button = try view.inspect().find(ViewType.Button.self) {
                (try? $0.accessibilityLabel().string()) == "Sales tax, Not exempt"
            }
            return try? button.accessibilityValue().string()
        }
        var open = ClientPageInteraction()
        open.pressTaxValue()

        #expect(try value(open) == "Answers showing")
        #expect(try value(ClientPageInteraction()) == "Closed")
    }

    /// L20: the question, Saving and a refusal appear without moving the focus, so
    /// each is said to VoiceOver. Hosted, because only a view on screen runs what a
    /// change of its own state triggers.
    @Test("the question, Saving and a refusal are each said to VoiceOver as they appear")
    func eachChangeIsAnnounced() async throws {
        @MainActor final class Heard { var said: [String] = [] }
        let heard = Heard()
        let (clients, _) = try Self.population()
        let harborlight = try Self.id(of: "Harborlight Ballet", in: clients)
        let presenter = ClientsPresenter(clients: clients)
        var asking = ClientPageInteraction()
        asking.pressTaxValue()
        let view = ClientsView(presenter: presenter, selected: .constant(harborlight),
                               writeTax: { _, _ in "That tax status could not be saved." },
                               announce: { heard.said.append($0) }, interaction: asking)
        ViewHosting.host(view: view)
        defer { ViewHosting.expel() }

        try await view.inspection.inspect { shown in
            try shown.find(button: "Exempt").tap()
        }
        for _ in 0..<200 where heard.said.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(heard.said.first?.hasPrefix("3 invoices already sent") == true)

        try await view.inspection.inspect { shown in
            try shown.find(button: "Change to Exempt").tap()
        }
        for _ in 0..<200 where heard.said.count < 3 { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(heard.said.dropFirst().contains("Saving"))
        #expect(heard.said.contains("That tax status could not be saved."))
    }

    @Test("with nothing that can write, the tax status is a value with nothing to press")
    func withoutAWriterNothingIsPressable() throws {
        let (clients, _) = try Self.population()
        let view = ClientsView(presenter: ClientsPresenter(clients: clients),
                               selected: .constant(try Self.id(of: "Harborlight Ballet", in: clients)))

        let labels = try view.inspect().findAll(ViewType.Button.self)
            .compactMap { try? $0.labelView().text().string() }
        #expect(!labels.contains("Not exempt"))
    }

    @Test("a shared address asks, with a way to say it is correct")
    func asharedAddressAsks() throws {
        let (clients, _) = try Self.population()
        let view = ClientsView(presenter: ClientsPresenter(clients: clients),
                               selected: .constant(try Self.id(of: "Drayton Wind Ensemble", in: clients)),
                               acknowledgeShared: { _ in nil })

        let drawn = try Self.text(in: view)
        #expect(drawn.contains("That is correct"))
    }

    /// ovation#616. The notice names the other client, so "That is correct" is said
    /// about somebody Dan can see, and the name is a way to that client (L80).
    @Test("the shared address notice names the other client, as a way to that client")
    func thesharedAddressNamesTheOther() throws {
        let (clients, _) = try Self.population()
        let chosen = WholeRowTests.Box<UUID?>(try Self.id(of: "Drayton Wind Ensemble", in: clients))
        let view = ClientsView(presenter: ClientsPresenter(clients: clients),
                               selected: chosen.binding, acknowledgeShared: { _ in nil })

        let drawn = try Self.text(in: view)
        #expect(!drawn.contains("Another client uses this address too."),
                "the notice still says another client without saying which")
        #expect(drawn.contains(" uses this address too."))

        // THE NOTICE'S NAME, not the list's row, which carries the same name and
        // selects the same client, and so would pass this for the wrong reason.
        // A row's label is its line of name and figure; the notice's is the word.
        let named = try view.inspect().findAll(ViewType.Button.self).filter {
            (try? $0.labelView().text().string()) == "Eastvale Opera Workshop"
        }
        #expect(named.count == 1)
        try #require(named.first).tap()
        #expect(chosen.value == (try Self.id(of: "Eastvale Opera Workshop", in: clients)))
    }
}

/// The pictures, at the real count, at the full and the half screen window, and the
/// question state. OPT IN, and it says when it did nothing (L98). ONE THEME, and the
/// dark capture is compared byte for byte, for the reason `InvoiceListShotTests`
/// gives: OvationPalette has no dark half, by Dan's decision.
@MainActor
struct ClientsShotTests {

    private static var outputDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        let named = environment["OVATION_SHOT_DIR"] ?? environment["TEST_RUNNER_OVATION_SHOT_DIR"] ?? ""
        return named.isEmpty ? nil : URL(fileURLWithPath: named)
    }

    /// The content beside the rail, in a 1064 and an 860 point window.
    private static let full = CGSize(width: 1_064 - OvationWindow.railWidth, height: 620)
    private static let half = CGSize(width: OvationWindow.minimumWidth - OvationWindow.railWidth, height: 620)

    @Test("the Clients screen is captured at its real count, and dark draws the same")
    func capturetheScreen() throws {
        guard let directory = Self.outputDirectory else {
            print("CLIENTS SHOTS: no TEST_RUNNER_OVATION_SHOT_DIR, so nothing was captured.")
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (clients, _) = try ClientsViewTests.population()
        let presenter = ClientsPresenter(clients: clients)
        #expect(presenter.count == 31, "the population is \(presenter.count), not the real 31")
        let harborlight = try ClientsViewTests.id(of: "Harborlight Ballet", in: clients)
        let view = ClientsView(presenter: presenter, selected: .constant(harborlight),
                               writeTax: { _, _ in nil }, writeTerm: { _, _ in nil },
                               acknowledgeShared: { _ in nil })

        let file = directory.appending(path: "clients.png")
        try OffscreenShot.capture(view, size: Self.full, scheme: .light, to: file)
        let darkFile = directory.appending(path: "dark-check-clients.png")
        try OffscreenShot.capture(view, size: Self.full, scheme: .dark, to: darkFile)
        let light = try Data(contentsOf: file)
        let dark = try Data(contentsOf: darkFile)
        try FileManager.default.removeItem(at: darkFile)
        #expect(light == dark, "the Clients screen takes a colour from the system in dark")

        try OffscreenShot.capture(view, size: Self.half, scheme: .light,
                                  to: directory.appending(path: "clients-half-screen.png"))

        var asking = ClientPageInteraction()
        _ = asking.pressAnswer(.exempt, on: try #require(presenter.pages[harborlight]))
        let question = ClientsView(presenter: presenter, selected: .constant(harborlight),
                                   writeTax: { _, _ in nil }, writeTerm: { _, _ in nil },
                                   acknowledgeShared: { _ in nil }, interaction: asking)
        try OffscreenShot.capture(question, size: Self.full, scheme: .light,
                                  to: directory.appending(path: "clients-tax-correction.png"))
        var open = ClientPageInteraction()
        open.pressTaxValue()
        let chips = ClientsView(presenter: presenter, selected: .constant(harborlight),
                                writeTax: { _, _ in nil }, writeTerm: { _, _ in nil },
                                acknowledgeShared: { _ in nil }, interaction: open)
        try OffscreenShot.capture(chips, size: Self.full, scheme: .light,
                                  to: directory.appending(path: "clients-tax-open.png"))
        let drayton = ClientsView(presenter: presenter,
                                  selected: .constant(try ClientsViewTests.id(of: "Drayton Wind Ensemble", in: clients)),
                                  writeTax: { _, _ in nil }, writeTerm: { _, _ in nil },
                                  acknowledgeShared: { _ in nil })
        try OffscreenShot.capture(drayton, size: Self.full, scheme: .light,
                                  to: directory.appending(path: "clients-shared-address.png"))
        print("CLIENTS SHOTS: wrote five pictures into \(directory.path)")
    }
}
