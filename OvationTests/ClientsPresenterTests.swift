import Foundation
import SwiftData
import Testing

/// ovation#568 and ovation#482. The Clients screen as values, from
/// docs/design/clients.html and PRD 14f, 14l, 14n, 38c, 51j and 51j1.
@MainActor
struct ClientsPresenterTests {

    private static let noon = Date(timeIntervalSince1970: 1_794_531_600)

    private static func store() throws -> ModelContext {
        ModelContext(try OvationSchema.container(inMemory: true))
    }

    @discardableResult
    private static func client(_ context: ModelContext, _ name: String, tax: TaxStatus = .notExempt,
                               email: String? = nil) -> Client {
        let client = Client(name: name, taxStatus: tax)
        client.email = email ?? name.lowercased().filter(\.isLetter) + "@client.example"
        context.insert(client)
        return client
    }

    @discardableResult
    private static func invoice(_ context: ModelContext, for client: Client, number: Int64?,
                                dayKey: String?, shoot: String = "Autumn gala",
                                amount: Money = Money(dollars: 1_000)) -> Invoice {
        let invoice = Invoice(client: client, kind: .photography,
                              invoiceDate: dayKey.flatMap(BusinessCalendar.day(forKey:)),
                              hourlyRate: Money(dollars: 250), taxRate: .newYorkCity, createdOn: nil)
        context.insert(invoice)
        invoice.number = number
        invoice.add(Shoot(name: shoot, when: nil, venue: nil))
        invoice.add(LineItem.flat(amount, describedAs: shoot))
        return invoice
    }

    private static func sent(_ invoice: Invoice) {
        invoice.recordSendState(.sent(route: .ovationSentIt, at: noon))
    }

    // MARK: the names

    @Test("the names are in alphabetical order whatever order the store gave them")
    func thenamesAreOrdered() throws {
        let context = try Self.store()
        for name in ["Zephyr Hall Concerts", "ashgrove Chamber Players", "Marrowbone Percussion Group"] {
            Self.client(context, name)
        }
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))

        #expect(presenter.rows.map(\.name)
                == ["ashgrove Chamber Players", "Marrowbone Percussion Group", "Zephyr Hall Concerts"])
        #expect(presenter.count == 3)
    }

    @Test("with nothing selected the first name's page is the one shown")
    func thefirstPageIsShownByDefault() throws {
        let context = try Self.store()
        Self.client(context, "Bellweather Dance Collective")
        Self.client(context, "Ashgrove Chamber Players")
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))

        #expect(presenter.page(for: nil)?.name == "Ashgrove Chamber Players")
        #expect(presenter.page(for: UUID())?.name == "Ashgrove Chamber Players",
                "a selection that is no longer there falls back rather than showing nothing")
    }

    /// PRD 14n, and the defect the record's own check plants: a version drawing the
    /// figure only where the row is built is right on load and never again.
    @Test("the held figure rides on every holding row except the one whose page is open")
    func theheldFigureFollowsTheSelection() throws {
        let context = try Self.store()
        let ashgrove = Self.client(context, "Ashgrove Chamber Players")
        let harborlight = Self.client(context, "Harborlight Ballet")
        Self.client(context, "Calder Street Theatre")
        for (client, dollars) in [(ashgrove, 500), (harborlight, 1_250)] {
            context.insert(Payment(client: client, amount: Money(dollars: Int64(dollars)),
                                   method: .zelle, receivedOn: .stamping(Self.noon)))
        }
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))
        let row = { (name: String) in try #require(presenter.rows.first { $0.name == name }) }

        #expect(presenter.heldFigure(on: try row("Ashgrove Chamber Players"), selected: ashgrove.id) == nil)
        #expect(presenter.heldFigure(on: try row("Harborlight Ballet"), selected: ashgrove.id) == "$1,250.00")
        #expect(presenter.heldFigure(on: try row("Ashgrove Chamber Players"), selected: harborlight.id) == "$500.00")
        #expect(presenter.heldFigure(on: try row("Calder Street Theatre"), selected: ashgrove.id) == nil,
                "a quantity of nothing is not drawn")
    }

    // MARK: a page

    @Test("a client holding nothing has no money boxes, and one arrival is said, never listed")
    func themoneyBoxesFollowTheZeroRule() throws {
        let context = try Self.store()
        let quiet = Self.client(context, "Tobias Fenn")
        let deposit = Self.client(context, "Ashgrove Chamber Players")
        context.insert(Payment(client: deposit, amount: Money(dollars: 500), method: .zelle,
                               receivedOn: try #require(BusinessCalendar.day(forKey: "2026-08-28"))))
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))

        let none = try #require(presenter.pages[quiet.id])
        #expect(none.held == nil && none.heldSaid == nil && none.referral == nil)
        let one = try #require(presenter.pages[deposit.id])
        #expect(one.held == "$500.00")
        #expect(one.heldSaid == "Deposit received 28 Aug")
        #expect(one.arrivals.isEmpty)
    }

    @Test("two arrivals are listed, an overpayment named by the invoice it came in on")
    func twoArrivalsAreListed() throws {
        let context = try Self.store()
        let client = Self.client(context, "Harborlight Ballet")
        let paid = Self.invoice(context, for: client, number: 1_126, dayKey: "2026-10-02",
                                amount: Money(dollars: 750))
        let deposit = Payment(client: client, amount: Money(dollars: 1_000), method: .zelle,
                              receivedOn: try #require(BusinessCalendar.day(forKey: "2026-09-03")))
        let over = Payment(client: client, amount: Money(dollars: 1_000), method: .check,
                           receivedOn: try #require(BusinessCalendar.day(forKey: "2026-10-02")))
        context.insert(deposit)
        context.insert(over)
        let allocation = PaymentAllocation(payment: over, invoice: paid, amount: Money(dollars: 750),
                                           allocatedOn: over.receivedOn, source: .recordedWithThePayment)
        context.insert(allocation)
        over.allocations.append(allocation)
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))

        let page = try #require(presenter.pages[client.id])
        #expect(page.held == "$1,250.00")
        #expect(page.heldSaid == nil)
        #expect(page.arrivals == [
            .init(words: "Deposit received 3 Sep", amount: "$1,000.00"),
            .init(words: "Overpaid on invoice 1126", amount: "$250.00"),
        ])
    }

    @Test("referral credit is hours, spelled by the shared rule with its unit")
    func referralCreditIsHours() throws {
        let context = try Self.store()
        let client = Self.client(context, "Orchard Hill Symphonia")
        let entry = ReferralLedgerEntry(client: client, hours: Hours(whole: 1),
                                        occurredOn: .stamping(Self.noon),
                                        earnedFromBookingKey: nil, note: nil)
        context.insert(entry)
        client.referralEntries.append(entry)
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))

        #expect(presenter.pages[client.id]?.referral == "1.0 hr")
    }

    @Test("an override names who booked; the ordinary case names nobody")
    func bookedByOnlyWhereItDiffers() throws {
        let context = try Self.store()
        let ordinary = Self.client(context, "Calder Street Theatre", email: "box@calder.example")
        ordinary.contractEmail = "box@calder.example"
        let over = Self.client(context, "Harborlight Ballet", email: "studio@harborlight.example")
        over.contractEmail = "treasurer@harborlight.example"
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))

        #expect(presenter.pages[ordinary.id]?.bookedBy == nil)
        #expect(presenter.pages[ordinary.id]?.goesTo == "box@calder.example")
        #expect(presenter.pages[over.id]?.goesTo == "treasurer@harborlight.example")
        #expect(presenter.pages[over.id]?.bookedBy == "studio@harborlight.example")
    }

    @Test("an address that is not one is named as such, and two addresses are a value")
    func contactFactsAreSaid() throws {
        let context = try Self.store()
        let bad = Self.client(context, "Pennywhistle Folk Circle", email: "ask at the box office")
        let two = Self.client(context, "Thistledown Puppet Theatre",
                              email: "puppets@thistledown.example, admin@thistledown.example")
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))

        #expect(presenter.pages[bad.id]?.addressProblem == "Not an address")
        #expect(presenter.pages[two.id]?.addressProblem == nil)
        #expect(presenter.pages[two.id]?.recipients == "Two recipients")
    }

    @Test("a shared address asks on both clients until it is said to be correct for that address")
    func asharedAddressAsks() throws {
        let context = try Self.store()
        let drayton = Self.client(context, "Drayton Wind Ensemble", email: "office@draytonarts.example")
        let eastvale = Self.client(context, "Eastvale Opera Workshop", email: "office@draytonarts.example")
        Self.client(context, "Tobias Fenn")
        eastvale.acknowledgeSharedAddress(on: .stamping(Self.noon))
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))

        #expect(presenter.pages[drayton.id]?.sharedAddressAsks == true)
        #expect(presenter.pages[eastvale.id]?.sharedAddressAsks == false)
    }

    @Test("the payment terms read the client's own, and the default where none is recorded")
    func thetermsAreTheClients() throws {
        let context = try Self.store()
        let standing = Self.client(context, "Calder Street Theatre")
        let own = Self.client(context, "Harborlight Ballet")
        own.paymentTermDays = 30
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))

        #expect(presenter.pages[standing.id]?.paymentTerm.says == "14 days")
        #expect(presenter.pages[own.id]?.paymentTerm.says == "30 days")
    }

    @Test("the invoices are newest first, with the words for where each stands")
    func theinvoicesAreListed() throws {
        let context = try Self.store()
        let client = Self.client(context, "Calder Street Theatre")
        Self.sent(Self.invoice(context, for: client, number: 1_112, dayKey: "2026-02-09", shoot: "Winter matinee"))
        Self.sent(Self.invoice(context, for: client, number: 1_131, dayKey: "2026-11-14"))
        Self.invoice(context, for: client, number: nil, dayKey: nil, shoot: "Spring showcase")
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))

        let lines = try #require(presenter.pages[client.id]).invoices
        #expect(lines.map(\.number) == ["", "1131", "1112"])
        #expect(lines.map(\.status) == ["Draft", "Sent, unpaid", "Sent, unpaid"])
        #expect(lines[1].shoot == "Autumn gala")
        #expect(lines[1].date == "14 Nov 2026")
        #expect(lines[1].amount == "1,088.75")
    }

    // MARK: correcting a tax status (ovation#482, PRD 51j1)

    @Test("an answer where none was recorded is saved at once, and the same answer does nothing")
    func afirstAnswerIsSavedAtOnce() throws {
        let context = try Self.store()
        let unanswered = Self.client(context, "Bellweather Dance Collective", tax: .neverRecorded)
        let answered = Self.client(context, "Calder Street Theatre", tax: .notExempt)
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))

        #expect(presenter.pages[unanswered.id]?.taxSaid == "Not recorded")
        #expect(presenter.pages[unanswered.id]?.press(.exempt) == .record(.exempt))
        #expect(presenter.pages[answered.id]?.press(.notExempt) == .nothing)
    }

    @Test("changing a recorded status asks first, counting the sent invoices charged under it")
    func achangeAsksFirst() throws {
        let context = try Self.store()
        let client = Self.client(context, "Calder Street Theatre", tax: .notExempt)
        Self.sent(Self.invoice(context, for: client, number: 1_131, dayKey: "2026-11-14"))
        Self.sent(Self.invoice(context, for: client, number: 1_126, dayKey: "2026-10-02"))
        Self.invoice(context, for: client, number: nil, dayKey: nil)
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))
        let page = try #require(presenter.pages[client.id])

        guard case .ask(let question) = page.press(.exempt) else {
            Issue.record("a recorded status changed without being asked"); return
        }
        #expect(question.sentence == "2 invoices already sent to this client were charged sales tax, "
                + "and stay as they were sent. Drafts and every invoice from now on will be Exempt.")
        #expect(question.change == "Change to Exempt")
        #expect(question.keep == "Keep Not exempt")
    }

    /// Dan, 2026-09-27 on ovation#600: where nothing went out under the old status
    /// the sentence says so plainly, never "0 invoices ... were charged". The words
    /// are Claude's drafting under that instruction.
    @Test("with nothing sent under the old status, the sentence says so plainly", arguments: [false, true])
    func thezeroCaseIsSaidPlainly(exempt: Bool) throws {
        let context = try Self.store()
        let client = Self.client(context, "Tobias Fenn", tax: exempt ? .exempt : .notExempt)
        Self.invoice(context, for: client, number: nil, dayKey: nil)
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))

        guard case .ask(let question) = try #require(presenter.pages[client.id])
            .press(exempt ? .notExempt : .exempt) else {
            Issue.record("not asked"); return
        }
        if exempt {
            #expect(question.sentence == "No invoice already sent to this client went out without "
                    + "sales tax, so none change. Drafts and every invoice from now on will be Not exempt.")
            return
        }
        #expect(question.sentence == "No invoice already sent to this client was charged sales tax, "
                + "so none change. Drafts and every invoice from now on will be Exempt.")
    }

    /// Review of ovation#600 (L629): the count is of invoices the same page lists as
    /// SENT. A send not yet settled is listed as "Send not settled", so it is not
    /// counted as sent; and "charged sales tax" is said only of an invoice that was.
    @Test("the count takes only settled sends, and only those actually charged sales tax")
    func thecountIsOfSettledChargedSends() throws {
        let context = try Self.store()
        let client = Self.client(context, "Calder Street Theatre", tax: .notExempt)
        Self.sent(Self.invoice(context, for: client, number: 1_131, dayKey: "2026-11-14"))
        Self.invoice(context, for: client, number: 1_130, dayKey: "2026-11-10")
            .recordSendState(.couldNotDetermine(checkedAt: Self.noon))
        Self.sent(Self.invoice(context, for: client, number: 1_129, dayKey: "2026-11-01",
                               amount: .zero))
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))
        let page = try #require(presenter.pages[client.id])

        #expect(page.invoices.map(\.status).contains("Send not settled"))
        guard case .ask(let question) = page.press(.exempt) else { Issue.record("not asked"); return }
        #expect(question.sentence == "1 invoice already sent to this client was charged sales tax, "
                + "and stay as they were sent. Drafts and every invoice from now on will be Exempt.")
    }

    @Test("the count is of invoices sent under the OLD status, and one reads in the singular")
    func thecountIsOfTheOldStatus() throws {
        let context = try Self.store()
        let client = Self.client(context, "Larkspur Community Chorus", tax: .exempt)
        Self.sent(Self.invoice(context, for: client, number: 1_119, dayKey: "2026-05-18"))
        let before = Self.invoice(context, for: client, number: 1_104, dayKey: "2026-03-01")
        // Sent under another status, which a correction to that status would not reach.
        client.taxStatus = .notExempt
        Self.sent(before)
        client.taxStatus = .exempt
        let presenter = ClientsPresenter(clients: try context.fetch(FetchDescriptor<Client>()))

        guard case .ask(let question) = try #require(presenter.pages[client.id]).press(.notExempt) else {
            Issue.record("not asked"); return
        }
        #expect(question.sentence == "1 invoice already sent to this client was not charged sales tax, "
                + "and stay as they were sent. Drafts and every invoice from now on will be Not exempt.")
    }
}

/// ovation#482. What the presses on a client's page do, as a value (PRD 51j1).
@MainActor
struct ClientPageInteractionTests {

    private static func page(_ status: TaxStatus) throws -> ClientsPresenter.Page {
        let context = ModelContext(try OvationSchema.container(inMemory: true))
        let client = Client(name: "Calder Street Theatre", taxStatus: status)
        context.insert(client)
        return try #require(ClientsPresenter(clients: [client]).pages[client.id])
    }

    @Test("pressing the value opens the two answers and pressing it again closes them")
    func thevalueOpensTheAnswers() {
        var state = ClientPageInteraction()
        state.pressTaxValue()
        #expect(state.taxIsOpen)
        state.pressTaxValue()
        #expect(!state.taxIsOpen)
    }

    @Test("a change to a recorded status writes nothing until Change to is pressed")
    func achangeWaitsForChangeTo() throws {
        var state = ClientPageInteraction()
        state.pressTaxValue()

        #expect(state.pressAnswer(.exempt, on: try Self.page(.notExempt)) == nil)
        #expect(state.asking?.to == .exempt)
        #expect(!state.taxIsOpen, "the answers close while it asks")

        #expect(state.change() == .exempt)
        #expect(state.asking == nil)
    }

    @Test("Keep writes nothing and closes the question")
    func keepWritesNothing() throws {
        var state = ClientPageInteraction()
        _ = state.pressAnswer(.exempt, on: try Self.page(.notExempt))

        state.keep()

        #expect(state.asking == nil)
        #expect(state.change() == nil, "nothing is left to change to")
    }

    @Test("a first answer is written at once, with no question")
    func afirstAnswerIsWrittenAtOnce() throws {
        var state = ClientPageInteraction()
        #expect(state.pressAnswer(.notExempt, on: try Self.page(.neverRecorded)) == .notExempt)
        #expect(state.asking == nil)
    }
}
